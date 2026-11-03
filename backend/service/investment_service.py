import io
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import pandas as pd
# pyrefly: ignore [missing-import]
import yfinance as yf

from service.database import get_pg
from service.portfolio import allocation
from service.portfolio import cost_basis as cb
from service.portfolio import dividends as dv
from service.portfolio import groups as grp
from service.portfolio import history as hist
from service.portfolio import performance as perf
from service.portfolio.categories import (
    ALLOCATION_CATEGORIES,
    CASH_CATEGORIES,
    CATEGORY_LABELS,
    CATEGORY_ORDER,
    PRICED_CATEGORIES,
)
from service.portfolio.fx import (
    MissingRateError,
    RateTable,
    brl_in_currency,
    latest_close_on_or_before,
    quote_currency_mismatch,
    transaction_rate,
)
from service.portfolio.settings import DEFAULT_SETTINGS, sanitize_settings

_portfolio_cache: dict = {}
_PORTFOLIO_CACHE_TTL = 300  # 5 minutes

# Market prices are cached separately from portfolio positions and keyed by
# symbol rather than family. A transaction changes positions, never prices, so
# recording one must not evict the prices — that was making every save wait on a
# full Yahoo round-trip.
_price_cache: dict = {}
_PRICE_CACHE_TTL = 600  # 10 minutes

# Category definitions live in service.portfolio.categories — a single source of
# truth, enforced by tests, because keeping these lists in sync by hand already
# went wrong once.


def _invalidate_portfolio_cache(family_id):
    _portfolio_cache.pop(str(family_id), None)


# ─── Per-family settings (concentration thresholds) ──────────────────────────

def get_settings(family_id: str) -> dict:
    """Stored row, or the defaults when the family never saved anything."""
    client = get_pg()
    rows = (client.from_('investment_settings')
            .select('*')
            .eq('family_id', family_id)
            .execute()).data or []
    if not rows:
        return {**DEFAULT_SETTINGS, 'is_default': True}
    row = rows[0]
    out = {}
    for key, default in DEFAULT_SETTINGS.items():
        value = row.get(key)
        if value is None:
            value = default
        out[key] = int(value) if key == 'report_reminder_days' else float(value)
    out['is_default'] = False
    return out


def update_settings(family_id: str, data: dict) -> dict:
    """Validated partial upsert. Raises ValueError on a bad payload."""
    clean = sanitize_settings(data)
    # Thresholds shape the concentration section of the portfolio response.
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    (client.from_('investment_settings')
     .upsert({'family_id': family_id, **clean}, on_conflict='family_id')
     .execute())
    return get_settings(family_id)


# ─── Historical FX rate (form prefill) ───────────────────────────────────────

# Direct BRL pairs, so a historical rate needs no cross-rate arithmetic.
_FX_HISTORY_TICKERS = {'USD': 'BRL=X', 'EUR': 'EURBRL=X', 'PLN': 'PLNBRL=X'}

_fx_rate_cache: dict = {}
_FX_RATE_CACHE_TTL = 86400  # a historical close never changes; 24h is plenty


def get_fx_rate_for_date(currency: str, target_date: str) -> dict:
    """
    Closing rate to BRL on (or last before) `target_date`, for prefilling the
    transaction form. Absence stays absent: no close means rate_brl None with a
    reason, never a guessed number — the user types the rate in that case.
    """
    c = (currency or 'BRL').upper()
    if c == 'BRL':
        return {'currency': c, 'date': target_date, 'rate_brl': 1.0,
                'rate_date': target_date, 'source': 'fixed'}
    symbol = _FX_HISTORY_TICKERS.get(c)
    if not symbol:
        return {'currency': c, 'date': target_date, 'rate_brl': None,
                'rate_date': None, 'reason': f'Unsupported currency {c}'}
    target = date.fromisoformat(target_date)  # ValueError → 400 in the route

    key = (c, target_date)
    now = time.time()
    cached = _fx_rate_cache.get(key)
    if cached and (now - cached['ts']) < _FX_RATE_CACHE_TTL:
        return cached['data']

    closes: dict = {}
    try:
        hist = yf.Ticker(symbol).history(
            start=target - timedelta(days=7), end=target + timedelta(days=1))
        for idx, row in hist.iterrows():
            close = float(row['Close'])
            if close > 0:
                closes[idx.date()] = close
    except Exception as e:
        print(f'[WARN] FX history fetch failed for {symbol}: {e}')

    picked = latest_close_on_or_before(closes, target)
    if picked is None:
        return {'currency': c, 'date': target_date, 'rate_brl': None,
                'rate_date': None,
                'reason': f'No {c}/BRL close on or before {target_date}'}
    rate_date, close = picked
    data = {'currency': c, 'date': target_date, 'rate_brl': close,
            'rate_date': rate_date.isoformat(), 'source': 'yahoo'}
    # Only successful lookups are cached, so a transient Yahoo failure retries.
    _fx_rate_cache[key] = {'data': data, 'ts': now}
    return data


# ─── Asset CRUD ──────────────────────────────────────────────────────────────

def get_assets(family_id: str) -> list:
    client = get_pg()
    res = (client.from_('investment_assets')
           .select('*')
           .eq('family_id', family_id)
           .order('category')
           .order('name')
           .execute())
    return res.data or []


def _assert_quote_currency(category: str, symbol: str | None,
                           currency: str | None) -> None:
    """
    Refuse a priced asset whose ticker is quoted in another currency than the
    asset's — its value would be silently wrong. Unreachable Yahoo is not a
    refusal; the portfolio re-checks at every valuation.
    """
    if category not in PRICED_CATEGORIES or not symbol:
        return
    reason = quote_currency_mismatch(
        symbol, quote_currency(symbol), currency or 'BRL')
    if reason:
        raise ValueError(reason)


def add_asset(family_id: str, data: dict) -> dict:
    _assert_quote_currency(
        data['category'], data.get('symbol'), data.get('currency', 'BRL'))
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    payload = {
        'family_id': family_id,
        'category': data['category'],
        'name': data['name'],
        'symbol': data.get('symbol'),
        'currency': data.get('currency', 'BRL'),
        'account': data.get('account'),
        'notes': data.get('notes'),
        # Classification for the allocation breakdowns. Free text — a CHECK here
        # would mean a migration every time reality produces a sector the enum
        # did not anticipate.
        'sector': data.get('sector'),
        'country': data.get('country'),
    }
    res = client.from_('investment_assets').insert(payload).execute()
    return res.data[0] if res.data else {}


def update_asset(asset_id: str, family_id: str, data: dict) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    allowed = {'name', 'symbol', 'currency', 'account', 'notes', 'category',
               'sector', 'country'}
    payload = {k: v for k, v in data.items() if k in allowed}
    if not payload:
        raise ValueError('No editable fields supplied')
    if {'category', 'symbol', 'currency'} & set(payload):
        current = (client.from_('investment_assets')
                   .select('category, symbol, currency')
                   .eq('id', asset_id)
                   .eq('family_id', family_id)
                   .execute()).data or [{}]
        merged = {**current[0], **payload}
        _assert_quote_currency(merged.get('category'), merged.get('symbol'),
                               merged.get('currency'))
    res = (client.from_('investment_assets')
           .update(payload)
           .eq('id', asset_id)
           .eq('family_id', family_id)
           .execute())
    return res.data[0] if res.data else {}


def delete_asset(asset_id: str, family_id: str) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    (client.from_('investment_assets')
     .delete()
     .eq('id', asset_id)
     .eq('family_id', family_id)
     .execute())
    return {'deleted': True}


# ─── Transaction CRUD ─────────────────────────────────────────────────────────

def get_transactions(family_id: str, asset_id: str = None, year: int = None) -> list:
    client = get_pg()
    query = (client.from_('investment_transactions')
             .select('*, investment_assets(name, symbol, category, account, currency)')
             .eq('family_id', family_id))
    if asset_id:
        query = query.eq('asset_id', asset_id)
    if year:
        query = (query
                 .gte('transaction_date', f'{year}-01-01')
                 .lte('transaction_date', f'{year}-12-31'))
    query = query.order('transaction_date', desc=True)
    rows = query.execute().data or []

    def asset_ccy(r):
        return ((r.get('investment_assets') or {}).get('currency')
                or 'BRL').upper()

    # The list follows the BRL/foreign toggle. `usd_amount` and `asset_amount`
    # (in the asset's own currency, for EUR/PLN assets) are `brl_amount` at
    # that trade's own rate: its frozen rate when paid in that currency, else
    # the day's close. Null when no close exists — never today's rate.
    closes = _conversion_closes(
        [('USD', r) for r in rows] + [(asset_ccy(r), r) for r in rows])
    for r in rows:
        tx = cb.from_row(r)
        brl = float(r.get('brl_amount') or 0)
        r['usd_amount'] = brl_in_currency(
            brl, 'USD', tx.original_currency, tx.exchange_rate,
            closes.get('USD'), tx.transaction_date)
        r['asset_amount'] = brl_in_currency(
            brl, asset_ccy(r), tx.original_currency, tx.exchange_rate,
            closes.get(asset_ccy(r)), tx.transaction_date)

    # Which cash account each trade moved money in, so the form can show it on
    # edit and default to the last one used.
    try:
        links = (client.from_('investment_transactions')
                 .select('linked_transaction_id, asset_id')
                 .eq('family_id', family_id)
                 .not_.is_('linked_transaction_id', 'null')
                 .execute()).data or []
    except Exception as e:
        print(f'[WARN] linked cash lookup failed (migration not run?): {e}')
        links = []
    cash_by_parent = {l['linked_transaction_id']: l['asset_id'] for l in links}
    for r in rows:
        r['cash_asset_id'] = cash_by_parent.get(r.get('id'))
    return rows


def _asset_rows(client, family_id: str, asset_id: str) -> list:
    return (client.from_('investment_transactions')
            .select('*')
            .eq('asset_id', asset_id)
            .eq('family_id', family_id)
            .execute()).data or []


def _assert_ledger_replayable(rows: list) -> None:
    """
    Replays the would-be ledger and lets OversellError (a ValueError) escape.

    Run BEFORE every write: an oversell only surfaces during replay, so once a
    bad row is stored it would fail every subsequent portfolio load instead of
    being a 400 at entry time.
    """
    cb.replay([cb.from_row(r) for r in rows])


# ─── Linked cash movements ───────────────────────────────────────────────────
#
# A buy / sell / dividend / coupon can name a cash account (`cash_asset_id`):
# the matching withdrawal or deposit is then written with it, pointing back at
# the trade through `linked_transaction_id`. Logged by hand it was three rows,
# and a forgotten withdrawal counted the same money twice — in the portfolio
# total and in the TWR flows.

_LINKED_ROW_LOCKED = ('This cash movement was created automatically by '
                      'another transaction — edit or delete that one instead.')
_REPLAY_LAST = '9999-12-31T00:00:00'  # same-day candidates replay last


def _cash_account(client, family_id: str, cash_asset_id: str,
                  currency: str) -> dict:
    """The cash account a trade moves money in, validated for this trade."""
    rows = (client.from_('investment_assets')
            .select('id, name, category, currency')
            .eq('id', cash_asset_id)
            .eq('family_id', family_id)
            .execute()).data
    if not rows:
        raise ValueError('Cash account not found or does not belong to this '
                         'family')
    account = rows[0]
    if account['category'] not in CASH_CATEGORIES:
        raise ValueError(f"{account['name']} is not a cash account")
    # The movement is booked in the trade's currency; a cash account in another
    # currency would store dollars as reais (or the reverse) in its balance.
    if (account.get('currency') or 'BRL').upper() != (currency or 'BRL').upper():
        raise ValueError(
            f"{account['name']} holds {account.get('currency') or 'BRL'}, the "
            f"transaction is in {currency} — pick a cash account in the same "
            f"currency.")
    return account


def _linked_cash_payload(parent: dict, label: str) -> dict | None:
    """The cash row a trade payload implies, or None when it moves no cash."""
    move = cb.linked_cash_movement(
        parent['transaction_type'], parent['original_amount'],
        parent['fees_original'], parent['withholding_tax_original'])
    if move is None:
        return None
    kind, amount = move
    return _build_transaction_payload({
        'transaction_type': kind,
        'transaction_date': parent['transaction_date'],
        'quantity': 0,
        'original_currency': parent['original_currency'],
        'original_amount': amount,
        # Same frozen rate as the trade: one event, one rate.
        'exchange_rate': parent['exchange_rate'],
        'fees_original': 0,
        'notes': f'Auto: {label}',
    })


def _assert_cash_replayable(rows: list, account: dict) -> None:
    """Replay a cash ledger; an overdraft reads as what it is."""
    try:
        _assert_ledger_replayable(rows)
    except cb.OversellError as e:
        raise ValueError(
            f"Not enough money in {account['name']} for this transaction "
            f"({e})") from e


def _linked_child(client, family_id: str, parent_id: str) -> dict | None:
    try:
        rows = (client.from_('investment_transactions')
                .select('*')
                .eq('family_id', family_id)
                .eq('linked_transaction_id', parent_id)
                .execute()).data or []
    except Exception as e:
        # Column missing until linked_cash_transactions.sql is run: there can
        # be no linked rows yet, and ordinary edits must keep working.
        print(f'[WARN] linked cash lookup failed (migration not run?): {e}')
        return None
    return rows[0] if rows else None


def add_transaction(family_id: str, data: dict) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()

    asset_res = (client.from_('investment_assets')
                 .select('id, family_id, name, symbol, category')
                 .eq('id', data['asset_id'])
                 .eq('family_id', family_id)
                 .execute())
    if not asset_res.data:
        raise ValueError('Asset not found or does not belong to this family')
    asset = asset_res.data[0]

    payload = _build_transaction_payload(data)

    candidate = {**payload, 'asset_id': data['asset_id'],
                 # Replays last among same-day rows, matching insertion order.
                 'created_at': _REPLAY_LAST}
    _assert_ledger_replayable(
        _asset_rows(client, family_id, data['asset_id']) + [candidate])

    # Validate the cash side BEFORE writing anything, so a refused overdraft
    # leaves no half-recorded trade behind.
    cash_id = data.get('cash_asset_id')
    child = None
    if cash_id:
        if cash_id == data['asset_id'] or asset['category'] in CASH_CATEGORIES:
            raise ValueError('A cash account cannot fund its own movements')
        account = _cash_account(client, family_id, cash_id,
                                payload['original_currency'])
        child = _linked_cash_payload(
            payload, f"{payload['transaction_type']} "
                     f"{asset.get('symbol') or asset.get('name')}")
        if child:
            _assert_cash_replayable(
                _asset_rows(client, family_id, cash_id)
                + [{**child, 'asset_id': cash_id, 'created_at': _REPLAY_LAST}],
                account)

    payload['asset_id'] = data['asset_id']
    payload['family_id'] = family_id

    res = client.from_('investment_transactions').insert(payload).execute()
    created = res.data[0] if res.data else {}

    if child and created.get('id'):
        try:
            client.from_('investment_transactions').insert({
                **child, 'asset_id': cash_id, 'family_id': family_id,
                'linked_transaction_id': created['id'],
            }).execute()
        except Exception:
            # PostgREST has no multi-statement transaction here: undo the trade
            # so the ledger never holds a buy whose cash never moved.
            (client.from_('investment_transactions').delete()
             .eq('id', created['id']).eq('family_id', family_id).execute())
            raise
        created['cash_asset_id'] = cash_id
    return created


def _build_transaction_payload(data: dict) -> dict:
    """
    Derive the stored row from the user's inputs.

    `brl_amount` is computed here and never taken from the client — it is the
    authoritative tax figure, so it is produced by the same rule the cost-basis
    engine applies. Any `brl_amount` in the request is ignored.
    """
    tx_type = data['transaction_type']
    original_amount = float(data['original_amount'])
    original_currency = data.get('original_currency', 'BRL')
    exchange_rate = data.get('exchange_rate')

    # Fees are entered in the transaction currency. Older clients sent only the
    # converted figure, so fall back to that and convert back.
    if data.get('fees_original') is not None:
        fees_original = float(data['fees_original'] or 0)
    else:
        legacy_brl = float(data.get('fees_brl', 0) or 0)
        rate_guess = float(exchange_rate) if exchange_rate else 1.0
        fees_original = legacy_brl / rate_guess if rate_guess else legacy_brl

    # Raises MissingRateError when a non-BRL transaction has no usable rate.
    brl_amount, rate = cb.brl_amount_for(
        tx_type, original_amount, fees_original, original_currency, exchange_rate)

    # Cash deposits/withdrawals carry no share count, so the amount becomes the
    # quantity. Storing it explicitly keeps the ledger self-describing rather
    # than relying on every reader to re-derive it.
    quantity = cb.effective_quantity(
        tx_type, data.get('quantity', 0), original_amount)

    return {
        'transaction_type': tx_type,
        'transaction_date': data['transaction_date'],
        'quantity': quantity,
        'price_per_unit_original': data.get('price_per_unit_original'),
        'original_currency': original_currency,
        'original_amount': original_amount,
        'exchange_rate': exchange_rate,
        'brl_amount': brl_amount,
        'fees_original': fees_original,
        'fees_brl': fees_original * rate,
        'withholding_tax_original': float(data.get('withholding_tax_original', 0) or 0),
        'fx_spread_original': float(data.get('fx_spread_original', 0) or 0),
        'notes': data.get('notes'),
    }


def update_transaction(tx_id: str, family_id: str, data: dict) -> dict:
    """
    Patch a transaction and re-derive `brl_amount`.

    The existing row is merged with the incoming fields and the whole payload is
    rebuilt, because editing the amount, the fee, the rate or the type all
    change the BRL figure. Patching fields individually would leave a stale
    authoritative number behind.
    """
    _invalidate_portfolio_cache(family_id)
    client = get_pg()

    existing = (client.from_('investment_transactions')
                .select('*')
                .eq('id', tx_id)
                .eq('family_id', family_id)
                .execute()).data
    if not existing:
        raise ValueError('Transaction not found or does not belong to this family')
    if existing[0].get('linked_transaction_id'):
        raise ValueError(_LINKED_ROW_LOCKED)

    editable = {
        'transaction_type', 'transaction_date', 'quantity',
        'price_per_unit_original', 'original_currency', 'original_amount',
        'exchange_rate', 'fees_original', 'fees_brl',
        'withholding_tax_original', 'fx_spread_original', 'notes',
    }
    merged = {**existing[0], **{k: v for k, v in data.items() if k in editable}}

    # If the caller changed the fee in BRL terms only, drop the original-currency
    # figure so it is re-derived rather than silently kept at its old value.
    if 'fees_brl' in data and 'fees_original' not in data:
        merged.pop('fees_original', None)

    payload = _build_transaction_payload(merged)

    rows = _asset_rows(client, family_id, existing[0]['asset_id'])
    updated_row = {**existing[0], **payload}
    _assert_ledger_replayable(
        [updated_row if r['id'] == existing[0]['id'] else r for r in rows])

    # Keep the linked cash movement in step with the edited trade. A missing
    # `cash_asset_id` keeps the current account; an explicit null unlinks it.
    old_child = _linked_child(client, family_id, tx_id)
    if 'cash_asset_id' in data:
        target_id = data.get('cash_asset_id') or None
    else:
        target_id = old_child['asset_id'] if old_child else None
    new_child = None
    if target_id:
        if target_id == existing[0]['asset_id']:
            raise ValueError('A cash account cannot fund its own movements')
        account = _cash_account(client, family_id, target_id,
                                payload['original_currency'])
        asset = (client.from_('investment_assets').select('name, symbol')
                 .eq('id', existing[0]['asset_id']).execute()).data or [{}]
        new_child = _linked_cash_payload(
            payload, f"{payload['transaction_type']} "
                     f"{asset[0].get('symbol') or asset[0].get('name')}")
    # Replay every cash ledger the edit touches, before writing anything.
    for cash_id in {old_child['asset_id'] if old_child else None, target_id} - {None}:
        cash_rows = [r for r in _asset_rows(client, family_id, cash_id)
                     if not old_child or r['id'] != old_child['id']]
        if new_child and cash_id == target_id:
            cash_rows.append({**new_child, 'asset_id': cash_id,
                              'created_at': (old_child or {}).get('created_at')
                              or _REPLAY_LAST})
        account = (client.from_('investment_assets').select('name')
                   .eq('id', cash_id).execute()).data or [{'name': cash_id}]
        _assert_cash_replayable(cash_rows, account[0])

    res = (client.from_('investment_transactions')
           .update(payload)
           .eq('id', tx_id)
           .eq('family_id', family_id)
           .execute())

    if old_child and new_child and old_child['asset_id'] == target_id:
        (client.from_('investment_transactions').update(new_child)
         .eq('id', old_child['id']).eq('family_id', family_id).execute())
    else:
        if old_child:
            (client.from_('investment_transactions').delete()
             .eq('id', old_child['id']).eq('family_id', family_id).execute())
        if new_child:
            client.from_('investment_transactions').insert({
                **new_child, 'asset_id': target_id, 'family_id': family_id,
                'linked_transaction_id': tx_id,
            }).execute()

    updated = res.data[0] if res.data else {}
    updated['cash_asset_id'] = target_id if new_child else None
    return updated


def delete_transaction(tx_id: str, family_id: str) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()

    existing = (client.from_('investment_transactions')
                .select('*')
                .eq('id', tx_id)
                .eq('family_id', family_id)
                .execute()).data
    if existing:
        if existing[0].get('linked_transaction_id'):
            raise ValueError(_LINKED_ROW_LOCKED)
        # Removing a buy that funds a later sell would leave an unreplayable
        # ledger behind — reject with a readable error instead.
        rows = _asset_rows(client, family_id, existing[0]['asset_id'])
        _assert_ledger_replayable(
            [r for r in rows if r['id'] != existing[0]['id']])
        # Its cash movement goes with it; the cash ledger must survive that
        # (deleting a sale whose proceeds were already spent would overdraw).
        child = _linked_child(client, family_id, tx_id)
        if child:
            account = (client.from_('investment_assets').select('name')
                       .eq('id', child['asset_id']).execute()).data or [{}]
            _assert_cash_replayable(
                [r for r in _asset_rows(client, family_id, child['asset_id'])
                 if r['id'] != child['id']],
                {'name': account[0].get('name', child['asset_id'])})
            (client.from_('investment_transactions').delete()
             .eq('id', child['id']).eq('family_id', family_id).execute())

    (client.from_('investment_transactions')
     .delete()
     .eq('id', tx_id)
     .eq('family_id', family_id)
     .execute())
    return {'deleted': True}


# ─── Core position engine: preço médio (weighted average cost) ───────────────

def _compute_position(transactions: list, asset_currency: str | None = None,
                      asset_closes: dict | None = None) -> dict:
    """
    Adapter over the shared cost-basis engine.

    Keeps the historical return keys so existing callers are unaffected, and
    adds the native-currency realized figure, total fees, and the audit trail.
    The trail comes from the same walk that produced the totals, so the two can
    never disagree.

    With `asset_currency`, every *_original figure is in that currency even
    when some transactions were paid in another; `asset_closes` (day → BRL per
    unit of it) supplies the trade-date rates. A missing close nulls the native
    figures instead of approximating them.
    """
    txs = [cb.from_row(t) for t in transactions]
    if asset_currency:
        txs = cb.with_asset_currency(txs, asset_currency, asset_closes or {})
    state, trail = cb.replay(txs)
    native = state.orig_complete
    return {
        'quantity': state.quantity,
        'avg_cost_brl': state.avg_brl,
        'total_invested_brl': state.invested_brl,
        'realized_gains_brl': state.realized_brl,
        'dividends_brl': state.income_brl,
        'native_available': native,
        'avg_cost_original': state.avg_orig if native else None,
        'total_invested_original': state.invested_orig if native else None,
        'realized_gains_original': state.realized_orig if native else None,
        'dividends_original': state.income_orig if native else None,
        'withholding_brl': state.withholding_brl,
        'fees_brl_total': state.fees_brl_total,
        'fees_orig_total': state.fees_orig_total if native else None,
        'audit_trail': trail,
    }


def _conversion_closes(pairs) -> dict:
    """
    Daily closes for every target currency that some transaction was NOT paid
    in, keyed by currency. `pairs` yields (target_currency, transaction row).
    Fetched only when such a transaction exists, so a single-currency ledger
    costs no extra Yahoo round-trip.
    """
    earliest: dict = {}
    for ccy, row in pairs:
        ccy = (ccy or 'BRL').upper()
        tx = cb.from_row(row)
        if cb.needs_asset_rate(tx, ccy):
            d = tx.transaction_date
            earliest[ccy] = min(earliest.get(ccy, d), d)
    # A week of lead-in so a trade on a weekend or holiday finds the previous
    # close inside the fetched window.
    return {ccy: get_fx_closes(ccy, start - timedelta(days=7), date.today())
            for ccy, start in earliest.items()}


def _asset_currency_closes(assets: list, txns_by_asset: dict) -> dict:
    """Closes taking each asset's off-currency trades into its own currency."""
    return _conversion_closes(
        (asset.get('currency'), row)
        for asset in assets
        for row in txns_by_asset.get(asset['id'], []))


def _sum_or_none(values) -> float | None:
    """Sum, or None when any term is missing — a partial sum reads as whole."""
    total = 0.0
    for v in values:
        if v is None:
            return None
        total += v
    return total


# ─── Yahoo Finance price fetcher (reused from original service) ───────────────

def _fetch_one(ticker) -> tuple[float, float, str | None]:
    """
    Pull last price, previous close and the quote currency for one ticker.
    The currency is None when Yahoo does not say — never assumed.
    """
    price = 0.0
    prev_close = 0.0
    currency = None
    # Read fast_info once — each access can trigger its own lazy lookup.
    info = getattr(ticker, 'fast_info', None)
    if info is not None:
        try:
            price = info['last_price']
        except Exception:
            pass
        try:
            prev_close = info['previous_close']
        except Exception:
            pass
        try:
            currency = info['currency'] or None
        except Exception:
            pass
    if price == 0.0 or prev_close == 0.0:
        hist = ticker.history(period='2d')
        if not hist.empty:
            if price == 0.0:
                price = hist['Close'].iloc[-1]
            if prev_close == 0.0 and len(hist) >= 2:
                prev_close = hist['Close'].iloc[-2]
    return float(price), float(prev_close), currency


def quote_currency(symbol: str) -> str | None:
    """
    The currency `symbol` is quoted in, for validating an asset on save.
    Served from the price cache when known; None when Yahoo cannot be reached
    (an unverifiable symbol is saved — valuation re-checks it every load).
    """
    entry = _price_cache.get(symbol)
    if entry and entry.get('currency'):
        return entry['currency']
    try:
        return yf.Ticker(symbol).fast_info['currency'] or None
    except Exception as e:
        print(f'[WARN] quote currency lookup failed for {symbol}: {e}')
        return None


def _fetch_prices(symbols: list, force_refresh: bool = False) -> tuple[dict, dict, RateTable, dict]:
    """
    Fetch current prices and previous closes from Yahoo Finance, serving fresh
    entries from _price_cache and fetching only stale ones — in parallel.
    Returns (prices, prev_closes, RateTable, per-symbol metadata).
    """
    rates_tickers = {'BRL': 'BRL=X', 'EUR': 'EURUSD=X', 'PLN': 'USDPLN=X'}
    all_tickers = list(set(symbols + list(rates_tickers.values())))

    prices = {}
    prev_closes = {}
    now = time.time()

    # Serve what is still fresh; collect the rest.
    stale = []
    for sym in all_tickers:
        entry = _price_cache.get(sym)
        if entry and not force_refresh and (now - entry['ts']) < _PRICE_CACHE_TTL:
            prices[sym] = entry['price']
            prev_closes[sym] = entry['prev']
        else:
            stale.append(sym)

    if stale:
        print(f'[DEBUG] Fetching {len(stale)} stale ticker(s), '
              f'{len(all_tickers) - len(stale)} served from cache')
        try:
            data = yf.Tickers(' '.join(stale))

            def worker(sym):
                # Never raise: pool.map re-raises on iteration, which would
                # abort every other ticker's result along with this one.
                try:
                    return sym, _fetch_one(data.tickers[sym])
                except Exception as e:
                    print(f'[WARN] Price fetch error for {sym}: {e}')
                    return sym, (0.0, 0.0, None)

            with ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(worker, stale))
        except Exception as e:
            print(f'[ERROR] Batch price fetch failed: {e}')
            results = [(sym, (0.0, 0.0, None)) for sym in stale]

        for sym, (price, prev_close, quote_ccy) in results:
            if price > 0:
                prices[sym] = price
                prev_closes[sym] = prev_close
                _price_cache[sym] = {'price': price, 'prev': prev_close,
                                     'currency': quote_ccy, 'ts': time.time()}
                continue
            # Fetch produced nothing. Keep the last known value rather than
            # zeroing the position out, and leave its cache entry untouched so
            # the next call retries instead of serving a zero.
            entry = _price_cache.get(sym)
            if entry and entry['price'] > 0:
                print(f'[WARN] {sym} fetch returned nothing, using cached price')
                prices[sym] = entry['price']
                prev_closes[sym] = entry['prev']
            else:
                prices[sym] = 0.0
                prev_closes[sym] = 0.0

    # Rule 4: an unavailable rate stays unavailable. The previous code
    # substituted 5.0 / 1.0 / 4.0 here, which produced a portfolio total derived
    # from an invented rate with nothing on screen to say so.
    def _rate(sym: str) -> float | None:
        value = prices.get(sym)
        if value is None or value <= 0.1:
            print(f'[WARN] {sym} unavailable — values that depend on it will '
                  f'report no data rather than a guess')
            return None
        return float(value)

    timestamps = [
        _price_cache[s]['ts'] for s in all_tickers
        if s in _price_cache and _price_cache[s].get('price', 0) > 0
    ]

    rates = RateTable(
        usd_brl=_rate('BRL=X'),
        eur_usd=_rate('EURUSD=X'),
        usd_pln=_rate('USDPLN=X'),
        as_of=min(timestamps) if timestamps else None,
    )

    # Per-symbol provenance so the UI can show when a quote was taken and flag
    # anything served past its TTL (Rule 6).
    now_ts = time.time()
    meta = {}
    for sym in all_tickers:
        entry = _price_cache.get(sym)
        ts = entry['ts'] if entry else None
        meta[sym] = {
            'as_of': ts,
            'stale': bool(ts is not None and (now_ts - ts) > _PRICE_CACHE_TTL),
            'available': bool(prices.get(sym, 0) > 0),
            'currency': entry.get('currency') if entry else None,
        }

    return prices, prev_closes, rates, meta


# ─── Portfolio summary ────────────────────────────────────────────────────────

def get_portfolio_summary(family_id: str, force_refresh: bool = False) -> dict:
    cache_key = str(family_id)
    now = time.time()
    cached = _portfolio_cache.get(cache_key)
    if cached and not force_refresh and (now - cached['ts']) < _PORTFOLIO_CACHE_TTL:
        print(f'[CACHE HIT] get_portfolio_summary family_id={cache_key}')
        return cached['data']

    client = get_pg()

    assets = (client.from_('investment_assets')
              .select('*')
              .eq('family_id', family_id)
              .execute()).data or []

    all_txns = (client.from_('investment_transactions')
                .select('*')
                .eq('family_id', family_id)
                .order('transaction_date', desc=False)
                .execute()).data or []

    txns_by_asset = defaultdict(list)
    for tx in all_txns:
        txns_by_asset[tx['asset_id']].append(tx)

    # The USD/BRL series over the whole ledger also covers every USD asset's
    # own off-currency trades, so it is fetched once and shared.
    usd_closes = _conversion_closes(
        ('USD', row) for row in all_txns).get('USD')
    asset_closes = _asset_currency_closes(
        [a for a in assets if (a.get('currency') or 'BRL').upper() != 'USD'],
        txns_by_asset)
    asset_closes['USD'] = usd_closes
    positions = {
        a['id']: _compute_position(
            txns_by_asset.get(a['id'], []),
            asset_currency=a.get('currency') or 'BRL',
            asset_closes=asset_closes.get((a.get('currency') or 'BRL').upper()))
        for a in assets
    }
    # The same ledgers replayed into USD, so the USD view of every asset is
    # exact whatever currency each trade was paid in: cost at each trade's own
    # USD/BRL close, never today's rate (which would invent an FX gain).
    usd_positions = {
        a['id']: _compute_position(txns_by_asset.get(a['id'], []),
                                   asset_currency='USD',
                                   asset_closes=usd_closes)
        for a in assets
    }

    symbols = [a['symbol'] for a in assets if a['category'] in PRICED_CATEGORIES and a.get('symbol')]
    prices, prev_closes, rates, price_meta = _fetch_prices(symbols, force_refresh)

    category_totals = {cat: {'value_brl': 0.0, 'invested_brl': 0.0} for cat in CATEGORY_ORDER}
    total_value_brl = 0.0
    total_invested_brl = 0.0
    enriched_assets = []
    unavailable = []
    usd_rate = rates.usd_brl
    today = date.today()

    def present_usd(brl):
        # Present-day values only: today's rate is the right one for them.
        return None if brl is None or not usd_rate else brl / usd_rate

    for asset in assets:
        pos = positions[asset['id']]
        upos = usd_positions[asset['id']]
        qty = pos['quantity']
        cat = asset['category']
        native_currency = asset.get('currency', 'BRL')

        current_price = None
        daily_change_pct = None
        reason = None
        sym = asset.get('symbol')

        if cat in PRICED_CATEGORIES and sym and qty <= cb.QTY_EPSILON:
            # Nothing held, nothing to value. A sold-out position whose ticker
            # was delisted or mismatched must not mark the totals incomplete —
            # that would also block every future snapshot.
            val_native = 0.0
        elif cat in PRICED_CATEGORIES and sym:
            quote = prices.get(sym, 0.0)
            mismatch = quote_currency_mismatch(
                sym, price_meta.get(sym, {}).get('currency'), native_currency)
            if mismatch:
                # A quote in another unit than the asset's would value it
                # silently wrong (IWDA.SA in BRL read as USD: ~5x). Excluded
                # and explained, like an unpriced position.
                val_native = None
                reason = mismatch
            elif quote > 0:
                current_price = quote
                val_native = qty * quote
                prev_close = prev_closes.get(sym, 0.0)
                if prev_close > 0:
                    daily_change_pct = (quote - prev_close) / prev_close * 100
            else:
                # No quote: the position cannot be valued. Reporting 0 here
                # would read as a worthless holding (Rule 4/6).
                val_native = None
                reason = f'No price available for {sym}'
        elif cat in CASH_CATEGORIES:
            # A cash balance is its quantity, denominated in its own currency
            # and priced at 1.0. Converting at today's rate means a USD balance
            # reflects FX movement instead of sitting frozen at cost.
            val_native = qty
            current_price = 1.0
        else:
            # Bonds have no market quote; cost basis is the value.
            val_native = pos['total_invested_brl']
            native_currency = 'BRL'
            current_price = 1.0

        cost_brl = pos['total_invested_brl']

        if val_native is None:
            val_brl = None
        else:
            val_brl = rates.to_brl(val_native, native_currency)
            if val_brl is None:
                reason = rates.missing_for(native_currency)

        if val_brl is None:
            unrealized_pnl_brl = None
            unrealized_pnl_pct = None
            unavailable.append({'asset_id': asset['id'],
                                'name': asset.get('name'),
                                'reason': reason})
        else:
            unrealized_pnl_brl = val_brl - cost_brl
            unrealized_pnl_pct = (
                unrealized_pnl_brl / cost_brl * 100) if cost_brl > 0 else 0.0

        # A position sold down to zero still owns its realized gain and its
        # transaction history, which is exactly what the tax report is built
        # from. It must stay reachable, so it carries enough metadata for the
        # UI to list it separately rather than dropping it.
        trail = pos['audit_trail']
        is_closed = bool(trail) and qty <= cb.QTY_EPSILON

        dividends_12m = dv.trailing_income_brl(trail, today)

        current_price_brl = (None if current_price is None
                             else rates.to_brl(current_price, native_currency))
        # USD side: costs from the USD replay (None when a trade-date close is
        # missing), present values at today's rate.
        usd_ok = upos['native_available']
        invested_usd = upos['total_invested_original']
        value_usd = present_usd(val_brl)
        pnl_usd = (None if value_usd is None or invested_usd is None
                   else value_usd - invested_usd)

        meta = price_meta.get(sym, {}) if sym else {}
        enriched = {
            **asset,
            'quantity': qty,
            'transaction_count': len(trail),
            'first_transaction_date':
                trail[0].transaction_date.isoformat() if trail else None,
            'last_transaction_date':
                trail[-1].transaction_date.isoformat() if trail else None,
            'is_closed': is_closed,
            'avg_cost_brl': pos['avg_cost_brl'],
            'total_invested_brl': cost_brl,
            'realized_gains_brl': pos['realized_gains_brl'],
            'realized_gains_original': pos['realized_gains_original'],
            'dividends_brl': pos['dividends_brl'],
            'dividends_original': pos['dividends_original'],
            'dividends_12m_brl': dividends_12m,
            'yield_on_cost_pct': dv.yield_on_cost_pct(dividends_12m, cost_brl),
            'withholding_brl': pos['withholding_brl'],
            'fees_brl_total': pos['fees_brl_total'],
            'fees_original_total': pos['fees_orig_total'],
            'current_price': current_price,
            # Today's quote at today's rate — a present value, so converting
            # it is exact (unlike a historical cost). None when unconvertible.
            'current_price_brl': current_price_brl,
            'daily_change_pct': daily_change_pct,
            # USD view, whatever currency each trade was paid in. Costs are at
            # each trade's own USD/BRL close; null means a close was missing,
            # never an approximation.
            'avg_cost_usd': upos['avg_cost_original'],
            'total_invested_usd': invested_usd,
            'realized_gains_usd': upos['realized_gains_original'],
            'dividends_usd': upos['dividends_original'],
            'dividends_12m_usd': (
                dv.trailing_income(upos['audit_trail'], today,
                                   attr='income_orig') if usd_ok else None),
            'current_price_usd': present_usd(current_price_brl),
            'current_value_usd': value_usd,
            'unrealized_pnl_usd': pnl_usd,
            'unrealized_pnl_pct_usd': (
                pnl_usd / invested_usd * 100
                if pnl_usd is not None and invested_usd > 0 else
                (0.0 if pnl_usd is not None else None)),
            'current_value_brl': val_brl,
            'unrealized_pnl_brl': unrealized_pnl_brl,
            'unrealized_pnl_pct': unrealized_pnl_pct,
            # Native-currency view, so the UI can show avg cost against the
            # Yahoo quote in the ticker's own units.
            'native_currency': native_currency,
            # False when a transaction in another currency had no trade-date
            # close: the *_original figures are then null, not approximated.
            'native_available': pos['native_available'],
            'avg_cost_original': pos['avg_cost_original'],
            'total_invested_original': pos['total_invested_original'],
            'current_value_original': val_native,
            # Rule 4/6 surface: never render a figure without its provenance.
            'value_available': val_brl is not None,
            'unavailable_reason': reason,
            'price_as_of': meta.get('as_of'),
            'price_stale': meta.get('stale', False),
        }
        enriched_assets.append(enriched)

        # Assets that could not be valued are excluded from the totals and
        # reported separately, so a total is never quietly understated.
        if val_brl is not None:
            category_totals[cat]['value_brl'] += val_brl
            total_value_brl += val_brl
        category_totals[cat]['invested_brl'] += cost_brl
        total_invested_brl += cost_brl

    total_pnl_brl = total_value_brl - total_invested_brl
    total_pnl_pct = (total_pnl_brl / total_invested_brl * 100) if total_invested_brl > 0 else 0.0

    # USD totals. Value follows the BRL exclusions (same assets, today's rate);
    # invested is the sum of each asset's own USD cost, so it is None if any
    # one of them is missing.
    total_value_usd = present_usd(total_value_brl)
    total_invested_usd = _sum_or_none(
        a['total_invested_usd'] for a in enriched_assets)
    total_pnl_usd = (None if total_value_usd is None or total_invested_usd is None
                     else total_value_usd - total_invested_usd)
    for cat, entry in category_totals.items():
        entry['value_usd'] = present_usd(entry['value_brl'])
        entry['invested_usd'] = _sum_or_none(
            a['total_invested_usd'] for a in enriched_assets
            if a['category'] == cat)
    dividends_12m_usd = _sum_or_none(
        a['dividends_12m_usd'] for a in enriched_assets)

    # Second pass: a position's share can only be known once every position has
    # been valued.
    allocation_base_brl, allocation_complete = allocation.annotate(
        enriched_assets, ALLOCATION_CATEGORIES)

    # Concentration: per-position and per-group shares against the family's own
    # thresholds. Slim dicts only — the full asset is already in `assets`.
    settings = get_settings(family_id)
    position_breaches = [
        {'asset_id': a['id'], 'name': a.get('name'), 'symbol': a.get('symbol'),
         'portfolio_pct': a['portfolio_pct']}
        for a in allocation.concentration_breaches(
            enriched_assets, settings['max_position_pct'])
    ]
    by_currency = allocation.group_totals(enriched_assets, 'native_currency')
    by_sector = allocation.group_totals(enriched_assets, 'sector')
    by_country = allocation.group_totals(enriched_assets, 'country')

    result = {
        'total_value_brl': total_value_brl,
        'total_invested_brl': total_invested_brl,
        'total_pnl_brl': total_pnl_brl,
        'total_pnl_pct': total_pnl_pct,
        'total_value_usd': total_value_usd,
        'total_invested_usd': total_invested_usd,
        'total_pnl_usd': total_pnl_usd,
        'total_pnl_pct_usd': (
            total_pnl_usd / total_invested_usd * 100
            if total_pnl_usd is not None and total_invested_usd > 0 else
            (0.0 if total_pnl_usd is not None else None)),
        'exchange_rate_usd_brl': rates.usd_brl,
        'rates_as_of': rates.as_of,
        'by_category': category_totals,
        'assets': enriched_assets,
        # Denominator behind every portfolio_pct: stocks, ETFs and broker cash.
        'allocation_base_brl': allocation_base_brl,
        'allocation_complete': allocation_complete,
        'allocation_categories': sorted(ALLOCATION_CATEGORIES),
        # Non-empty means the totals above exclude something.
        'unavailable_assets': unavailable,
        'totals_complete': not unavailable,
        # Allocation breakdowns along each labelling axis (base positions only).
        'by_currency': by_currency,
        'by_sector': by_sector,
        'by_country': by_country,
        'concentration': {
            'settings': {k: settings[k] for k in DEFAULT_SETTINGS},
            'position_breaches': position_breaches,
            'sector_breaches': allocation.group_breaches(
                by_sector, settings['max_sector_pct']),
            'currency_breaches': allocation.group_breaches(
                by_currency, settings['max_currency_pct']),
            'country_breaches': allocation.group_breaches(
                by_country, settings['max_country_pct']),
        },
        # Portfolio-level cost and income figures (net = gross − withholding).
        'fees_brl_total': sum(p['fees_brl_total'] for p in positions.values()),
        'withholding_brl_total': sum(
            p['withholding_brl'] for p in positions.values()),
        'dividends_net_brl_total': sum(
            p['dividends_brl'] for p in positions.values()),
        # The two top-level UI sections: exchange (stock, etf) vs off-exchange.
        'by_group': grp.group_summaries(enriched_assets),
        'dividends': {
            'total_net_brl': sum(
                p['dividends_brl'] for p in positions.values()),
            'last_12m_net_brl': sum(
                a['dividends_12m_brl'] for a in enriched_assets),
            'portfolio_yield_on_cost_pct': dv.yield_on_cost_pct(
                sum(a['dividends_12m_brl'] for a in enriched_assets),
                total_invested_brl),
            'total_net_usd': _sum_or_none(
                p['dividends_original'] for p in usd_positions.values()),
            'last_12m_net_usd': dividends_12m_usd,
        },
    }

    # Materialize-at-visit: every fresh computation leaves a daily snapshot
    # behind (cache hits skip this path entirely, so no redundant writes).
    _maybe_write_snapshot(family_id, result)

    _portfolio_cache[cache_key] = {'data': result, 'ts': time.time()}
    return result


# ─── Portfolio history (equity curve) ────────────────────────────────────────

HISTORY_RANGES = {'3mo': 90, '1y': 365, 'all': None}


def _maybe_write_snapshot(family_id: str, summary: dict) -> None:
    """
    Best-effort daily snapshot. Incomplete valuations are refused by
    `snapshot_from_summary`, a same-day recomputation replaces the earlier row
    (fresher read = better read), and any write failure is logged rather than
    allowed to break the portfolio response.
    """
    row = hist.snapshot_from_summary(summary, date.today())
    if row is None:
        return
    try:
        client = get_pg()
        (client.from_('portfolio_snapshots')
         .upsert({'family_id': family_id, 'source': 'visit', **row},
                 on_conflict='family_id,snapshot_date')
         .execute())
    except Exception as e:
        print(f'[WARN] snapshot write failed for family {family_id}: {e}')


def get_history(family_id: str, range_key: str) -> dict:
    """Daily equity-curve points, forward-filled through today."""
    if range_key not in HISTORY_RANGES:
        raise ValueError(
            f'Invalid range {range_key!r}. Allowed: {sorted(HISTORY_RANGES)}')
    client = get_pg()
    query = (client.from_('portfolio_snapshots')
             .select('snapshot_date, total_value_brl, total_invested_brl,'
                     ' usd_brl_rate')
             .eq('family_id', family_id)
             .order('snapshot_date', desc=False))
    days = HISTORY_RANGES[range_key]
    if days is not None:
        cutoff = (date.today() - timedelta(days=days)).isoformat()
        query = query.gte('snapshot_date', cutoff)
    rows = query.execute().data or []
    return {'range': range_key,
            'points': hist.fill_gaps(rows, date.today())}


# ─── Performance: TWR / XIRR vs S&P 500 ──────────────────────────────────────

PERFORMANCE_RANGES = {'1y': 365, 'all': None}
PERFORMANCE_CURRENCIES = ('BRL', 'USD')
BENCHMARK_SYMBOL = '^GSPC'
USD_BRL_SYMBOL = 'BRL=X'

_benchmark_cache: dict = {}
_BENCHMARK_CACHE_TTL = 3600
_fx_series_cache: dict = {}


def get_benchmark_closes(start: date, end: date) -> dict:
    """Daily ^GSPC closes for [start, end], cached for an hour."""
    key = (start.isoformat(), end.isoformat())
    now = time.time()
    cached = _benchmark_cache.get(key)
    if cached and (now - cached['ts']) < _BENCHMARK_CACHE_TTL:
        return cached['data']
    closes: dict = {}
    try:
        raw = yf.Ticker(BENCHMARK_SYMBOL).history(
            start=start.isoformat(),
            end=(end + timedelta(days=1)).isoformat())
        for idx, row in raw.iterrows():
            close = float(row['Close'])
            if close > 0:
                closes[idx.date()] = close
    except Exception as e:
        print(f'[WARN] benchmark fetch failed: {e}')
    if closes:  # failures are not cached, so the next call retries
        _benchmark_cache[key] = {'data': closes, 'ts': now}
    return closes


def get_usd_brl_closes(start: date, end: date) -> dict:
    """Daily USD/BRL closes for [start, end] — see `get_fx_closes`."""
    return get_fx_closes('USD', start, end)


def get_fx_closes(currency: str, start: date, end: date) -> dict:
    """
    Daily `currency`/BRL closes for [start, end], cached for an hour.

    Same shape and failure policy as `get_benchmark_closes`: a fetch failure
    returns an empty map and is NOT cached, so the next call retries instead of
    freezing an outage into the hour. An unsupported currency is an empty map
    too — never a 1:1 stand-in.
    """
    c = (currency or 'BRL').upper()
    symbol = _FX_HISTORY_TICKERS.get(c)
    if not symbol:
        return {}
    key = (c, start.isoformat(), end.isoformat())
    now = time.time()
    cached = _fx_series_cache.get(key)
    if cached and (now - cached['ts']) < _BENCHMARK_CACHE_TTL:
        return cached['data']
    closes: dict = {}
    try:
        raw = yf.Ticker(symbol).history(
            start=start.isoformat(),
            end=(end + timedelta(days=1)).isoformat())
        for idx, row in raw.iterrows():
            close = float(row['Close'])
            if close > 0:
                closes[idx.date()] = close
    except Exception as e:
        print(f'[WARN] {c}/BRL series fetch failed: {e}')
    if closes:
        _fx_series_cache[key] = {'data': closes, 'ts': now}
    return closes


def get_performance(family_id: str, range_key: str,
                    currency: str = 'BRL') -> dict:
    """
    TWR (chain-linked over observed snapshots), XIRR and an S&P 500 index
    aligned to the portfolio series. Not enough data is a 200 with nulls and
    a warning — an empty history is a state, not an error.
    """
    if range_key not in PERFORMANCE_RANGES:
        raise ValueError(
            f'Invalid range {range_key!r}. '
            f'Allowed: {sorted(PERFORMANCE_RANGES)}')
    if currency not in PERFORMANCE_CURRENCIES:
        raise ValueError(
            f'Invalid currency {currency!r}. '
            f'Allowed: {sorted(PERFORMANCE_CURRENCIES)}')

    client = get_pg()
    # Performance measures the invested portfolio only — the allocation base
    # (stocks, ETFs, crypto, cash equivalents, broker cash). Bonds valued at
    # cost (Tesouro), bank and home cash are reserves: folding idle money into
    # a return compared against the S&P 500 makes the invested part look worse
    # than it works.
    query = (client.from_('portfolio_snapshots')
             .select('snapshot_date, allocation_base_brl')
             .eq('family_id', family_id)
             .order('snapshot_date', desc=False))
    days = PERFORMANCE_RANGES[range_key]
    if days is not None:
        cutoff = (date.today() - timedelta(days=days)).isoformat()
        query = query.gte('snapshot_date', cutoff)
    rows = [r for r in (query.execute().data or [])
            if r.get('allocation_base_brl') is not None]
    # Days before anything was invested have no base to grow from; a leading
    # zero would make the first subperiod's return undefined.
    while rows and float(rows[0]['allocation_base_brl']) <= 0:
        rows.pop(0)

    # Observed span, first snapshot to last — the only history the figures can
    # honestly rest on. A lone snapshot spans no time, so the wait stays full.
    observed_days = 0
    if rows:
        observed_days = (
            date.fromisoformat(rows[-1]['snapshot_date'][:10])
            - date.fromisoformat(rows[0]['snapshot_date'][:10])).days
    avail = perf.availability(observed_days)

    empty = {'twr_pct': None, 'xirr_pct': None, 'benchmark': None,
             'series': [], 'currency': currency,
             'history_days': observed_days, **avail,
             'flows_convention': perf.FLOWS_CONVENTION}
    if len(rows) < 2:
        return {**empty,
                'warnings': ['At least two daily snapshots are needed — '
                             'history builds up from visits.']}

    valuations = [
        (date.fromisoformat(r['snapshot_date'][:10]),
         float(r['allocation_base_brl']))
        for r in rows
    ]
    first_date, first_value = valuations[0]
    last_date, last_value = valuations[-1]

    txns = (client.from_('investment_transactions')
            .select('transaction_date, transaction_type, brl_amount,'
                    ' original_currency, exchange_rate,'
                    ' withholding_tax_original, investment_assets(category)')
            .eq('family_id', family_id)
            .execute()).data or []
    for t in txns:
        t['category'] = (t.get('investment_assets') or {}).get('category')
    # Flows before the first snapshot are already embodied in its value. Only
    # flows across the invested boundary count: bank → broker cash is new
    # money in, the bank side is outside the measured portfolio.
    window_flows = [
        (d, f) for d, f in perf.external_flows(txns, ALLOCATION_CATEGORIES)
        if first_date < d <= last_date
    ]

    currency_warnings: list = [
        'Covers the invested portfolio only (stocks, ETFs, crypto, cash '
        'equivalents, broker cash); bonds, bank and home cash are excluded.']
    if currency == 'USD':
        # Every date is converted at ITS OWN close, never at today's rate: a
        # single rate applied across the window would smuggle FX movement into
        # the return, which is exactly what the USD view exists to strip out.
        rates = get_usd_brl_closes(first_date, last_date)
        converted_vals, missing_vals = perf.convert_pairs(valuations, rates)
        converted_flows, missing_flows = perf.convert_pairs(window_flows, rates)
        missing = sorted(set(missing_vals) | set(missing_flows))
        if missing:
            # A partially converted series would be a silent lie about the
            # return, so the figures are withheld rather than approximated.
            return {**empty,
                    'warnings': ['No USD/BRL close available for '
                                 f'{len(missing)} date(s) starting '
                                 f'{missing[0].isoformat()} — USD figures are '
                                 'withheld rather than estimated.']}
        valuations = converted_vals
        window_flows = converted_flows
        first_value = valuations[0][1]
        last_value = valuations[-1][1]
        currency_warnings.append(
            'Portfolio and S&P 500 are both in USD; each day is converted at '
            'its own USD/BRL close.')

    result = perf.twr(valuations, window_flows)
    warnings = list(result['warnings'])

    twr_pct = result['twr_pct']
    twr_left = avail['twr_days_remaining']
    if twr_left is not None:
        # The chart still draws both indexed lines — a short series looks short.
        # It is the headline number that waits, because a percentage carries no
        # visible hint of how thin the window behind it is.
        twr_pct = None
        warnings.append(
            f'TWR needs {perf.TWR_MIN_DAYS} days of history to mean '
            f'something — {twr_left} day(s) to go.')

    xirr_pct = None
    xirr_left = avail['xirr_days_remaining']
    if xirr_left is not None:
        warnings.append(
            f'XIRR needs {perf.XIRR_MIN_DAYS} days of history — '
            f'{xirr_left} day(s) to go; annualizing a shorter window '
            'would mislead.')
    else:
        cashflows = ([(first_date, -first_value)]
                     + [(d, -f) for d, f in window_flows]
                     + [(last_date, last_value)])
        rate = perf.xirr(cashflows)
        if rate is None:
            warnings.append('XIRR did not converge for these cash flows.')
        else:
            xirr_pct = rate * 100

    benchmark = None
    series = [{'date': p['date'], 'portfolio_index': p['index'],
               'benchmark_index': None} for p in result['series']]
    closes = get_benchmark_closes(first_date, last_date)
    if closes:
        series_dates = [date.fromisoformat(p['date'])
                        for p in result['series']]
        bench_idx = perf.index_series(closes, series_dates)
        for point, idx in zip(series, bench_idx):
            point['benchmark_index'] = idx
        final = next((i for i in reversed(bench_idx) if i is not None), None)
        benchmark = {'symbol': BENCHMARK_SYMBOL,
                     'return_pct': None if final is None else final - 100}
        if currency == 'BRL':
            warnings.append('S&P 500 is indexed in USD, the portfolio in BRL — '
                            'FX movement is not adjusted out.')
    else:
        warnings.append('Benchmark data unavailable.')

    return {'twr_pct': twr_pct, 'xirr_pct': xirr_pct,
            'benchmark': benchmark, 'series': series,
            'warnings': warnings + currency_warnings, 'currency': currency,
            'history_days': observed_days, **avail,
            'flows_convention': perf.FLOWS_CONVENTION}


# ─── Price history (asset chart) ─────────────────────────────────────────────

PRICE_HISTORY_RANGES = ('1mo', '6mo', '1y', '5y', 'max')

_history_cache: dict = {}
_HISTORY_CACHE_TTL = 3600  # candles move slowly; an hour is fresh enough


def get_price_history(asset_id: str, family_id: str, range_key: str) -> dict:
    """
    Daily closes for one asset's chart, in the instrument's own currency.

    Historical prices are deliberately NOT converted at today's FX rate —
    re-pricing history with the current rate invents gains (same rule as
    `asset_display.dart` on the client).
    """
    if range_key not in PRICE_HISTORY_RANGES:
        raise ValueError(
            f'Invalid range {range_key!r}. Allowed: {list(PRICE_HISTORY_RANGES)}')

    client = get_pg()
    rows = (client.from_('investment_assets')
            .select('id, symbol, category, currency')
            .eq('id', asset_id)
            .eq('family_id', family_id)
            .execute()).data or []
    if not rows:
        raise LookupError('Asset not found or does not belong to this family')
    asset = rows[0]
    sym = asset.get('symbol')
    if asset.get('category') not in PRICED_CATEGORIES or not sym:
        raise ValueError('Asset has no market symbol — no price history exists')

    key = (sym, range_key)
    now = time.time()
    cached = _history_cache.get(key)
    if cached and (now - cached['ts']) < _HISTORY_CACHE_TTL:
        data = cached['data']
    else:
        points = []
        try:
            hist = yf.Ticker(sym).history(period=range_key)
            for idx, row in hist.iterrows():
                close = float(row['Close'])
                if close > 0:
                    points.append(
                        {'date': idx.date().isoformat(), 'close': close})
        except Exception as e:
            print(f'[WARN] price history fetch failed for {sym}: {e}')
        data = {'symbol': sym, 'points': points, 'as_of': now}
        if points:  # only successful fetches are cached, so failures retry
            _history_cache[key] = {'data': data, 'ts': now}

    return {**data, 'currency': asset.get('currency') or 'BRL',
            'range': range_key}


# ─── Realized gains for tax reporting ────────────────────────────────────────

def compute_realized_gains(family_id: str, year: int) -> list:
    """
    Per-asset realized gains and income for one calendar year.

    Replays the full history through the shared cost-basis engine so the tax
    report and the dashboard can never disagree — this previously carried its
    own copy of the averaging logic, including a date-only sort that made
    same-day results depend on row order.
    """
    client = get_pg()

    assets = (client.from_('investment_assets')
              .select('*')
              .eq('family_id', family_id)
              .execute()).data or []

    all_txns = (client.from_('investment_transactions')
                .select('*')
                .eq('family_id', family_id)
                .order('transaction_date', desc=False)
                .execute()).data or []

    asset_map = {a['id']: a for a in assets}
    notes_by_tx = {str(t.get('id')): t.get('notes') for t in all_txns}
    tx_by_id = {str(t.get('id')): t for t in all_txns}

    txns_by_asset = defaultdict(list)
    for tx in all_txns:
        txns_by_asset[tx['asset_id']].append(tx)

    results = []
    for asset_id, txns in txns_by_asset.items():
        asset = asset_map.get(asset_id, {})
        pos = _compute_position(txns)

        year_sells = []
        year_dividends = []
        realized_in_year = 0.0
        realized_in_year_orig = 0.0
        dividends_in_year = 0.0          # net of withholding
        dividends_gross_in_year = 0.0
        withholding_in_year = 0.0

        for step in pos['audit_trail']:
            if step.transaction_date.year != year:
                continue
            note = notes_by_tx.get(step.transaction_id)

            if step.transaction_type in cb.SELL_TYPES:
                realized_in_year += step.realized_brl
                realized_in_year_orig += step.realized_orig
                year_sells.append({
                    'date': step.transaction_date.isoformat(),
                    'quantity': -step.quantity_delta,
                    'proceeds_brl': step.proceeds_brl,
                    'proceeds_original': step.proceeds_orig,
                    'avg_cost_brl_per_unit': step.avg_brl_before,
                    'avg_cost_original_per_unit': step.avg_orig_before,
                    'cost_basis_brl': step.cost_of_sold_brl,
                    'cost_basis_original': step.cost_of_sold_orig,
                    'gain_brl': step.realized_brl,
                    'gain_original': step.realized_orig,
                    'original_currency': step.original_currency,
                    'exchange_rate': step.exchange_rate,
                    'notes': note,
                })

            elif step.transaction_type in cb.INCOME_TYPES:
                # The row stores gross (the tax report needs it and the credit
                # for tax withheld abroad); the engine's income figure is net.
                # Gross is reconstructed as net + withholding at the same rate,
                # so the three figures can never disagree.
                raw = tx_by_id.get(step.transaction_id, {})
                withholding_orig = float(
                    raw.get('withholding_tax_original') or 0)
                withholding_brl = withholding_orig * (step.exchange_rate or 1.0)
                gross_brl = step.income_brl + withholding_brl
                dividends_in_year += step.income_brl
                dividends_gross_in_year += gross_brl
                withholding_in_year += withholding_brl
                year_dividends.append({
                    'date': step.transaction_date.isoformat(),
                    'amount_brl': step.income_brl,
                    'amount_original': step.income_orig,
                    'gross_brl': gross_brl,
                    'withholding_brl': withholding_brl,
                    'original_currency': step.original_currency,
                    'notes': note,
                })

        if year_sells or year_dividends:
            results.append({
                'asset_id': asset_id,
                'asset_name': asset.get('name', ''),
                'symbol': asset.get('symbol'),
                'category': asset.get('category'),
                'account': asset.get('account'),
                'currency': asset.get('currency', 'BRL'),
                'sells': year_sells,
                'dividends': year_dividends,
                'realized_gain_brl': realized_in_year,
                'realized_gain_original': realized_in_year_orig,
                'dividend_income_brl': dividends_in_year,
                'dividend_gross_brl': dividends_gross_in_year,
                'dividend_withholding_brl': withholding_in_year,
                'qty_at_year_end': pos['quantity'],
                'avg_cost_at_year_end': pos['avg_cost_brl'],
            })

    return results


# ─── Yearly Excel tax report ──────────────────────────────────────────────────

def generate_yearly_report(family_id: str, year: int) -> io.BytesIO:
    """
    Build a professional Excel workbook for annual tax reporting with 3 sheets:
      1. Ganhos Realizados — realized gains/losses per asset
      2. Transações        — all transactions in the year
      3. Posição Final     — portfolio holdings at year end
    """
    gains_data = compute_realized_gains(family_id, year)
    all_txns = get_transactions(family_id, year=year)
    portfolio = get_portfolio_summary(family_id)

    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
        wb = writer.book

        # ── Formats ──────────────────────────────────────────────────────────
        hdr_fmt = wb.add_format({
            'bold': True, 'bg_color': '#1F4E79', 'font_color': 'white',
            'border': 1, 'align': 'center', 'valign': 'vcenter',
        })
        money_fmt = wb.add_format({'num_format': '#,##0.00', 'border': 1})
        date_fmt = wb.add_format({'num_format': 'dd/mm/yyyy', 'border': 1})
        cell_fmt = wb.add_format({'border': 1})
        pos_fmt = wb.add_format({'num_format': '#,##0.00', 'border': 1, 'font_color': '#1F7A1F'})
        neg_fmt = wb.add_format({'num_format': '#,##0.00', 'border': 1, 'font_color': '#C00000'})
        total_fmt = wb.add_format({'bold': True, 'border': 1, 'num_format': '#,##0.00'})
        total_lbl_fmt = wb.add_format({'bold': True, 'border': 1})
        pct_fmt = wb.add_format({'num_format': '0.00"%"', 'border': 1})

        # ── Sheet 1: Ganhos Realizados ────────────────────────────────────────
        ws1 = wb.add_worksheet('Ganhos Realizados')
        ws1.set_column('A:A', 28)
        ws1.set_column('B:B', 14)
        ws1.set_column('C:C', 10)
        ws1.set_column('D:D', 18)
        ws1.set_column('E:E', 16)
        ws1.set_column('F:F', 18)
        ws1.set_column('G:I', 20)

        # Dividends split gross / withheld / net: the accountant needs the
        # gross figure plus the foreign tax credit, not one ambiguous number.
        headers1 = ['Ativo', 'Categoria', 'Ticker', 'Conta',
                    'Total Vendas (BRL)', 'Ganho/Perda (BRL)',
                    'Dividendos Brutos (BRL)', 'Imposto Retido (BRL)',
                    'Dividendos Líquidos (BRL)']
        for col, h in enumerate(headers1):
            ws1.write(0, col, h, hdr_fmt)
        ws1.set_row(0, 18)

        row = 1
        total_gains = 0.0
        total_divs_gross = 0.0
        total_withholding = 0.0
        total_divs_net = 0.0
        for item in gains_data:
            proceeds = sum(s['proceeds_brl'] for s in item['sells'])
            g = item['realized_gain_brl']
            total_gains += g
            total_divs_gross += item['dividend_gross_brl']
            total_withholding += item['dividend_withholding_brl']
            total_divs_net += item['dividend_income_brl']
            ws1.write(row, 0, item['asset_name'], cell_fmt)
            ws1.write(row, 1, CATEGORY_LABELS.get(item.get('category', ''), item.get('category', '')), cell_fmt)
            ws1.write(row, 2, item.get('symbol') or '-', cell_fmt)
            ws1.write(row, 3, item.get('account') or '-', cell_fmt)
            ws1.write(row, 4, proceeds, money_fmt)
            ws1.write(row, 5, g, pos_fmt if g >= 0 else neg_fmt)
            ws1.write(row, 6, item['dividend_gross_brl'], money_fmt)
            ws1.write(row, 7, item['dividend_withholding_brl'], money_fmt)
            ws1.write(row, 8, item['dividend_income_brl'], money_fmt)
            row += 1

        ws1.write(row, 3, 'TOTAL', total_lbl_fmt)
        ws1.write(row, 5, total_gains, total_fmt)
        ws1.write(row, 6, total_divs_gross, total_fmt)
        ws1.write(row, 7, total_withholding, total_fmt)
        ws1.write(row, 8, total_divs_net, total_fmt)

        # ── Sheet 2: Transações ───────────────────────────────────────────────
        tx_rows = []
        for tx in all_txns:
            asset_info = tx.get('investment_assets') or {}
            tx_rows.append({
                'Data': tx['transaction_date'],
                'Ativo': asset_info.get('name', ''),
                'Ticker': asset_info.get('symbol') or '-',
                'Categoria': CATEGORY_LABELS.get(asset_info.get('category', ''), asset_info.get('category', '')),
                'Conta': asset_info.get('account') or '-',
                'Tipo': tx['transaction_type'],
                'Quantidade': float(tx.get('quantity') or 0),
                'Moeda Original': tx['original_currency'],
                'Valor Original': float(tx['original_amount']),
                'Taxa de Câmbio': float(tx.get('exchange_rate') or 1.0),
                'Valor BRL': float(tx['brl_amount']),
                'Taxas BRL': float(tx.get('fees_brl') or 0),
                'Notas': tx.get('notes') or '',
            })

        if tx_rows:
            df_tx = pd.DataFrame(tx_rows)
            df_tx.to_excel(writer, sheet_name='Transações', index=False)
            ws2 = writer.sheets['Transações']
            ws2.set_column('A:A', 12)
            ws2.set_column('B:B', 28)
            ws2.set_column('C:C', 10)
            ws2.set_column('D:D', 16)
            ws2.set_column('E:E', 18)
            ws2.set_column('F:F', 14)
            ws2.set_column('G:G', 12)
            ws2.set_column('H:H', 14)
            ws2.set_column('I:I', 14)
            ws2.set_column('J:J', 14)
            ws2.set_column('K:K', 12)
            ws2.set_column('L:L', 10)
            ws2.set_column('M:M', 25)
        else:
            ws2 = wb.add_worksheet('Transações')
            ws2.write(0, 0, f'Nenhuma transação em {year}', cell_fmt)

        # ── Sheet 3: Posição Final ────────────────────────────────────────────
        pos_rows = []
        for asset in portfolio['assets']:
            pos_rows.append({
                'Ativo': asset['name'],
                'Ticker': asset.get('symbol') or '-',
                'Categoria': CATEGORY_LABELS.get(asset.get('category', ''), asset.get('category', '')),
                'Conta': asset.get('account') or '-',
                'Quantidade': asset['quantity'],
                'Preço Médio (BRL)': asset['avg_cost_brl'],
                'Custo Total (BRL)': asset['total_invested_brl'],
                'Valor Atual (BRL)': asset['current_value_brl'],
                'Ganho Não Realizado (BRL)': asset['unrealized_pnl_brl'],
                'Ganho Não Realizado (%)': asset['unrealized_pnl_pct'],
                'Ganhos Realizados (BRL)': asset['realized_gains_brl'],
                'Dividendos Líquidos (BRL)': asset['dividends_brl'],
                'Imposto Retido (BRL)': asset['withholding_brl'],
                'Taxas (BRL)': asset['fees_brl_total'],
            })

        if pos_rows:
            df_pos = pd.DataFrame(pos_rows)
            df_pos.to_excel(writer, sheet_name='Posição Final', index=False)
            ws3 = writer.sheets['Posição Final']
            ws3.set_column('A:A', 28)
            ws3.set_column('B:C', 12)
            ws3.set_column('D:D', 18)
            ws3.set_column('E:L', 20)
        else:
            ws3 = wb.add_worksheet('Posição Final')
            ws3.write(0, 0, 'Nenhuma posição encontrada.', cell_fmt)

    output.seek(0)
    return output

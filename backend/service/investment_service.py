import io
import time
from collections import defaultdict

import pandas as pd
# pyrefly: ignore [missing-import]
import yfinance as yf

from service.database import get_pg

_portfolio_cache: dict = {}
_PORTFOLIO_CACHE_TTL = 300  # 5 minutes

PRICED_CATEGORIES = {'stock', 'crypto'}
CATEGORY_ORDER = ['stock', 'crypto', 'bond', 'cash_broker', 'cash_home', 'cash_bank']
CATEGORY_LABELS = {
    'stock': 'Ações',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
}


def _invalidate_portfolio_cache(family_id):
    _portfolio_cache.pop(str(family_id), None)


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


def add_asset(family_id: str, data: dict) -> dict:
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
    }
    res = client.from_('investment_assets').insert(payload).execute()
    return res.data[0] if res.data else {}


def update_asset(asset_id: str, family_id: str, data: dict) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    allowed = {'name', 'symbol', 'currency', 'account', 'notes', 'category'}
    payload = {k: v for k, v in data.items() if k in allowed}
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
    res = query.execute()
    return res.data or []


def add_transaction(family_id: str, data: dict) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()

    asset_res = (client.from_('investment_assets')
                 .select('id, family_id')
                 .eq('id', data['asset_id'])
                 .eq('family_id', family_id)
                 .execute())
    if not asset_res.data:
        raise ValueError('Asset not found or does not belong to this family')

    original_amount = float(data['original_amount'])
    exchange_rate = data.get('exchange_rate')
    brl_amount = data.get('brl_amount')

    if brl_amount is None:
        if exchange_rate is not None:
            brl_amount = original_amount * float(exchange_rate)
        else:
            brl_amount = original_amount

    payload = {
        'asset_id': data['asset_id'],
        'family_id': family_id,
        'transaction_type': data['transaction_type'],
        'transaction_date': data['transaction_date'],
        'quantity': data.get('quantity', 0),
        'price_per_unit_original': data.get('price_per_unit_original'),
        'original_currency': data.get('original_currency', 'BRL'),
        'original_amount': original_amount,
        'exchange_rate': exchange_rate,
        'brl_amount': float(brl_amount),
        'fees_brl': float(data.get('fees_brl', 0)),
        'notes': data.get('notes'),
    }
    res = client.from_('investment_transactions').insert(payload).execute()
    return res.data[0] if res.data else {}


def update_transaction(tx_id: str, family_id: str, data: dict) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    allowed = {
        'transaction_type', 'transaction_date', 'quantity',
        'price_per_unit_original', 'original_currency', 'original_amount',
        'exchange_rate', 'brl_amount', 'fees_brl', 'notes',
    }
    payload = {k: v for k, v in data.items() if k in allowed}
    res = (client.from_('investment_transactions')
           .update(payload)
           .eq('id', tx_id)
           .eq('family_id', family_id)
           .execute())
    return res.data[0] if res.data else {}


def delete_transaction(tx_id: str, family_id: str) -> dict:
    _invalidate_portfolio_cache(family_id)
    client = get_pg()
    (client.from_('investment_transactions')
     .delete()
     .eq('id', tx_id)
     .eq('family_id', family_id)
     .execute())
    return {'deleted': True}


# ─── Core position engine: preço médio (weighted average cost) ───────────────

def _compute_position(transactions: list) -> dict:
    """
    Apply the average cost (preço médio) method to a chronologically sorted list
    of transactions for a single asset.

    Brazilian tax rules:
    - brl_amount on a buy includes fees (fees raise the cost basis, lowering tax).
    - On a sell, avg_cost does NOT change — only quantity and realized gain update.
    - Dividends are income; they don't affect quantity or cost basis.
    """
    qty = 0.0
    avg_cost_brl = 0.0
    total_invested_brl = 0.0
    realized_gains_brl = 0.0
    dividends_brl = 0.0

    for tx in sorted(transactions, key=lambda t: t['transaction_date']):
        tx_type = tx['transaction_type']
        tx_qty = float(tx.get('quantity') or 0)
        tx_brl = float(tx['brl_amount'])

        if tx_type in ('buy', 'deposit'):
            new_total_cost = avg_cost_brl * qty + tx_brl
            qty += tx_qty
            avg_cost_brl = new_total_cost / qty if qty > 0 else 0.0
            total_invested_brl += tx_brl

        elif tx_type in ('sell', 'withdrawal'):
            cost_of_sold = avg_cost_brl * tx_qty
            realized_gains_brl += tx_brl - cost_of_sold
            qty = max(qty - tx_qty, 0.0)
            total_invested_brl = max(total_invested_brl - cost_of_sold, 0.0)

        elif tx_type == 'dividend':
            dividends_brl += tx_brl

    return {
        'quantity': max(qty, 0.0),
        'avg_cost_brl': avg_cost_brl,
        'total_invested_brl': max(total_invested_brl, 0.0),
        'realized_gains_brl': realized_gains_brl,
        'dividends_brl': dividends_brl,
    }


# ─── Yahoo Finance price fetcher (reused from original service) ───────────────

def _fetch_prices(symbols: list) -> tuple[dict, dict, float, float, float]:
    """
    Batch-fetch current prices and previous closes from Yahoo Finance.
    Returns (prices, prev_closes, usd_to_brl, eur_to_usd, usd_to_pln).
    """
    rates_tickers = {'BRL': 'BRL=X', 'EUR': 'EURUSD=X', 'PLN': 'USDPLN=X'}
    all_tickers = list(set(symbols + list(rates_tickers.values())))

    prices = {}
    prev_closes = {}

    if all_tickers:
        tickers_str = ' '.join(all_tickers)
        try:
            data = yf.Tickers(tickers_str)
            for sym in all_tickers:
                try:
                    ticker = data.tickers[sym]
                    price = 0.0
                    prev_close = 0.0
                    if hasattr(ticker, 'fast_info'):
                        try:
                            price = ticker.fast_info['last_price']
                        except Exception:
                            pass
                        try:
                            prev_close = ticker.fast_info['previous_close']
                        except Exception:
                            pass
                    if price == 0.0 or prev_close == 0.0:
                        hist = ticker.history(period='2d')
                        if not hist.empty:
                            if price == 0.0:
                                price = hist['Close'].iloc[-1]
                            if prev_close == 0.0 and len(hist) >= 2:
                                prev_close = hist['Close'].iloc[-2]
                    prices[sym] = float(price)
                    prev_closes[sym] = float(prev_close)
                except Exception as e:
                    print(f'[WARN] Price fetch error for {sym}: {e}')
                    prices[sym] = 0.0
                    prev_closes[sym] = 0.0
        except Exception as e:
            print(f'[ERROR] Batch price fetch failed: {e}')

    usd_to_brl = prices.get('BRL=X', 5.0)
    eur_to_usd = prices.get('EURUSD=X', 1.0)
    usd_to_pln = prices.get('USDPLN=X', 4.0)

    if usd_to_brl <= 0.1:
        print(f'[WARN] Invalid USD/BRL rate ({usd_to_brl}), using fallback 5.0')
        usd_to_brl = 5.0
    if eur_to_usd <= 0.1:
        print(f'[WARN] Invalid EUR/USD rate ({eur_to_usd}), using fallback 1.0')
        eur_to_usd = 1.0
    if usd_to_pln <= 0.1:
        print(f'[WARN] Invalid USD/PLN rate ({usd_to_pln}), using fallback 4.0')
        usd_to_pln = 4.0

    return prices, prev_closes, usd_to_brl, eur_to_usd, usd_to_pln


def _native_to_brl(val_native: float, currency: str, usd_to_brl: float,
                   eur_to_usd: float, usd_to_pln: float) -> float:
    if currency == 'BRL':
        return val_native
    elif currency == 'USD':
        return val_native * usd_to_brl
    elif currency == 'EUR':
        return val_native * eur_to_usd * usd_to_brl
    elif currency == 'PLN':
        return val_native / usd_to_pln * usd_to_brl
    return val_native


# ─── Portfolio summary ────────────────────────────────────────────────────────

def get_portfolio_summary(family_id: str) -> dict:
    cache_key = str(family_id)
    now = time.time()
    cached = _portfolio_cache.get(cache_key)
    if cached and (now - cached['ts']) < _PORTFOLIO_CACHE_TTL:
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

    positions = {a['id']: _compute_position(txns_by_asset.get(a['id'], [])) for a in assets}

    symbols = [a['symbol'] for a in assets if a['category'] in PRICED_CATEGORIES and a.get('symbol')]
    prices, prev_closes, usd_to_brl, eur_to_usd, usd_to_pln = _fetch_prices(symbols)

    category_totals = {cat: {'value_brl': 0.0, 'invested_brl': 0.0} for cat in CATEGORY_ORDER}
    total_value_brl = 0.0
    total_invested_brl = 0.0
    enriched_assets = []

    for asset in assets:
        pos = positions[asset['id']]
        qty = pos['quantity']
        cat = asset['category']
        native_currency = asset.get('currency', 'BRL')

        current_price = 0.0
        daily_change_pct = 0.0

        if cat in PRICED_CATEGORIES and asset.get('symbol'):
            sym = asset['symbol']
            current_price = prices.get(sym, 0.0)
            val_native = qty * current_price
            prev_close = prev_closes.get(sym, 0.0)
            if prev_close > 0:
                daily_change_pct = (current_price - prev_close) / prev_close * 100
        else:
            val_native = pos['total_invested_brl']
            native_currency = 'BRL'
            current_price = 1.0

        val_brl = _native_to_brl(val_native, native_currency, usd_to_brl, eur_to_usd, usd_to_pln)
        cost_brl = pos['total_invested_brl']
        unrealized_pnl_brl = val_brl - cost_brl
        unrealized_pnl_pct = (unrealized_pnl_brl / cost_brl * 100) if cost_brl > 0 else 0.0

        enriched = {
            **asset,
            'quantity': qty,
            'avg_cost_brl': pos['avg_cost_brl'],
            'total_invested_brl': cost_brl,
            'realized_gains_brl': pos['realized_gains_brl'],
            'dividends_brl': pos['dividends_brl'],
            'current_price': current_price,
            'daily_change_pct': daily_change_pct,
            'current_value_brl': val_brl,
            'unrealized_pnl_brl': unrealized_pnl_brl,
            'unrealized_pnl_pct': unrealized_pnl_pct,
        }
        enriched_assets.append(enriched)

        category_totals[cat]['value_brl'] += val_brl
        category_totals[cat]['invested_brl'] += cost_brl
        total_value_brl += val_brl
        total_invested_brl += cost_brl

    total_pnl_brl = total_value_brl - total_invested_brl
    total_pnl_pct = (total_pnl_brl / total_invested_brl * 100) if total_invested_brl > 0 else 0.0

    result = {
        'total_value_brl': total_value_brl,
        'total_invested_brl': total_invested_brl,
        'total_pnl_brl': total_pnl_brl,
        'total_pnl_pct': total_pnl_pct,
        'exchange_rate_usd_brl': usd_to_brl,
        'by_category': category_totals,
        'assets': enriched_assets,
    }

    _portfolio_cache[cache_key] = {'data': result, 'ts': time.time()}
    return result


# ─── Realized gains for tax reporting ────────────────────────────────────────

def compute_realized_gains(family_id: str, year: int) -> list:
    """
    Compute realized gains/losses per asset for the given calendar year using
    preço médio. Replays ALL historical transactions to get the correct avg_cost
    at the time of each sell in the target year.
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

    txns_by_asset = defaultdict(list)
    for tx in all_txns:
        txns_by_asset[tx['asset_id']].append(tx)

    results = []
    for asset_id, txns in txns_by_asset.items():
        asset = asset_map.get(asset_id, {})
        year_sells = []
        year_dividends = []
        qty = 0.0
        avg_cost_brl = 0.0
        realized_in_year = 0.0
        dividends_in_year = 0.0

        for tx in sorted(txns, key=lambda t: t['transaction_date']):
            tx_type = tx['transaction_type']
            tx_qty = float(tx.get('quantity') or 0)
            tx_brl = float(tx['brl_amount'])
            tx_year = int(tx['transaction_date'][:4])

            if tx_type in ('buy', 'deposit'):
                new_total = avg_cost_brl * qty + tx_brl
                qty += tx_qty
                avg_cost_brl = new_total / qty if qty > 0 else 0.0

            elif tx_type in ('sell', 'withdrawal'):
                cost_of_sold = avg_cost_brl * tx_qty
                gain = tx_brl - cost_of_sold
                if tx_year == year:
                    realized_in_year += gain
                    year_sells.append({
                        'date': tx['transaction_date'],
                        'quantity': tx_qty,
                        'proceeds_brl': tx_brl,
                        'avg_cost_brl_per_unit': avg_cost_brl,
                        'cost_basis_brl': cost_of_sold,
                        'gain_brl': gain,
                        'notes': tx.get('notes'),
                    })
                qty = max(qty - tx_qty, 0.0)

            elif tx_type == 'dividend':
                if tx_year == year:
                    dividends_in_year += tx_brl
                    year_dividends.append({
                        'date': tx['transaction_date'],
                        'amount_brl': tx_brl,
                        'notes': tx.get('notes'),
                    })

        if year_sells or year_dividends:
            results.append({
                'asset_id': asset_id,
                'asset_name': asset.get('name', ''),
                'symbol': asset.get('symbol'),
                'category': asset.get('category'),
                'account': asset.get('account'),
                'sells': year_sells,
                'dividends': year_dividends,
                'realized_gain_brl': realized_in_year,
                'dividend_income_brl': dividends_in_year,
                'qty_at_year_end': max(qty, 0.0),
                'avg_cost_at_year_end': avg_cost_brl,
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
        ws1.set_column('G:G', 16)

        headers1 = ['Ativo', 'Categoria', 'Ticker', 'Conta',
                    'Total Vendas (BRL)', 'Ganho/Perda (BRL)', 'Dividendos (BRL)']
        for col, h in enumerate(headers1):
            ws1.write(0, col, h, hdr_fmt)
        ws1.set_row(0, 18)

        row = 1
        total_gains = 0.0
        total_divs = 0.0
        for item in gains_data:
            proceeds = sum(s['proceeds_brl'] for s in item['sells'])
            g = item['realized_gain_brl']
            d = item['dividend_income_brl']
            total_gains += g
            total_divs += d
            ws1.write(row, 0, item['asset_name'], cell_fmt)
            ws1.write(row, 1, CATEGORY_LABELS.get(item.get('category', ''), item.get('category', '')), cell_fmt)
            ws1.write(row, 2, item.get('symbol') or '-', cell_fmt)
            ws1.write(row, 3, item.get('account') or '-', cell_fmt)
            ws1.write(row, 4, proceeds, money_fmt)
            ws1.write(row, 5, g, pos_fmt if g >= 0 else neg_fmt)
            ws1.write(row, 6, d, money_fmt)
            row += 1

        ws1.write(row, 3, 'TOTAL', total_lbl_fmt)
        ws1.write(row, 5, total_gains, total_fmt)
        ws1.write(row, 6, total_divs, total_fmt)

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
                'Dividendos (BRL)': asset['dividends_brl'],
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

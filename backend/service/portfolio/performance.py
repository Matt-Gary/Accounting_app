"""
Performance engine: external flows, time-weighted return, XIRR and benchmark
indexing. Pure functions over plain data — no I/O.

Flow convention (`external_flows`, confirmed against the family's real logging
habits): buys and deposits are inflows (+), sells and withdrawals outflows (−),
and income leaves the portfolio net of withholding (−). Because purchases from
broker cash are logged as deposit + buy + withdrawal, and a re-deposited
dividend gets its own deposit row, the per-day sum of these terms is exactly
the new money that crossed the portfolio boundary that day.

Honesty rules carried over from the rest of the package: a figure that cannot
be computed is None with a warning, never an approximation presented as exact.
"""

from datetime import date

from .cost_basis import BUY_TYPES, INCOME_TYPES, SELL_TYPES
from .fx import latest_close_on_or_before, transaction_rate

FLOWS_CONVENTION = 'net_external'  # documented in the API response


def _parse_date(raw) -> date:
    return date.fromisoformat(raw[:10]) if isinstance(raw, str) else raw


def external_flows(rows) -> list:
    """Per-day net external cash flow, BRL, sorted by date."""
    per_date: dict = {}
    for r in rows:
        kind = (r.get('transaction_type') or '').lower()
        brl = float(r.get('brl_amount') or 0)
        if kind in BUY_TYPES:
            amount = brl
        elif kind in SELL_TYPES:
            amount = -brl
        elif kind in INCOME_TYPES:
            # The stored brl_amount is GROSS x rate (tax contract); what
            # actually left the portfolio is the net of withholding.
            rate = transaction_rate(
                r.get('original_currency'), r.get('exchange_rate'))
            withholding = float(r.get('withholding_tax_original') or 0)
            amount = -(brl - withholding * rate)
        else:
            continue
        d = _parse_date(r.get('transaction_date'))
        per_date[d] = per_date.get(d, 0.0) + amount
    return sorted(per_date.items())


def twr(valuations, flows) -> dict:
    """
    Chain-linked time-weighted return over consecutive valuation dates, with
    Modified Dietz weighting for flows inside a subperiod (snapshots are
    visit-driven, so subperiods can be long and flows can land mid-gap).

    Returns ``{'twr_pct', 'series': [{'date','index'}], 'warnings'}``. The
    series is indexed to 100 at the first valuation. A subperiod whose base is
    non-positive makes the chained figure meaningless — the result is then
    None with a warning, not a number that looks precise.
    """
    warnings: list = []
    vals = sorted(valuations)
    if len(vals) < 2:
        return {'twr_pct': None, 'series': [],
                'warnings': ['At least two portfolio valuations are needed '
                             'to compute a time-weighted return.']}

    flows_sorted = sorted(flows)
    growth = 1.0
    series = [{'date': vals[0][0].isoformat(), 'index': 100.0}]

    for (d0, v0), (d1, v1) in zip(vals, vals[1:]):
        period_days = (d1 - d0).days or 1
        period_flows = [(d, f) for d, f in flows_sorted if d0 < d <= d1]
        total_flow = sum(f for _, f in period_flows)
        weighted = sum(
            f * ((d1 - d).days / period_days) for d, f in period_flows)
        base = v0 + weighted
        if base <= 0:
            return {'twr_pct': None, 'series': series,
                    'warnings': warnings + [
                        f'Subperiod {d0.isoformat()}..{d1.isoformat()} has a '
                        f'non-positive base — TWR cannot be computed.']}
        growth *= 1 + (v1 - v0 - total_flow) / base
        series.append({'date': d1.isoformat(), 'index': 100.0 * growth})

    return {'twr_pct': (growth - 1) * 100, 'series': series,
            'warnings': warnings}


def xirr(cashflows) -> float | None:
    """
    Annualized money-weighted return (fraction, e.g. 0.12 = 12%/year).

    Newton's method with a bisection fallback on [-0.999, 10]. None when the
    flows are all one sign or no root is bracketed/converged — never an
    unconverged approximation.
    """
    flows = sorted(cashflows)
    if not flows:
        return None
    amounts = [f for _, f in flows]
    if all(f >= 0 for f in amounts) or all(f <= 0 for f in amounts):
        return None

    t0 = flows[0][0]
    scale = max(abs(f) for f in amounts)

    def npv(rate: float) -> float:
        return sum(
            f / (1 + rate) ** ((d - t0).days / 365.0) for d, f in flows)

    rate = 0.1
    for _ in range(60):
        f0 = npv(rate)
        if abs(f0) < 1e-7 * scale:
            return rate
        h = 1e-6
        derivative = (npv(rate + h) - f0) / h
        if derivative == 0:
            break
        step = rate - f0 / derivative
        if step <= -0.999:
            step = (rate - 0.999) / 2
        if abs(step - rate) < 1e-10:
            rate = step
            break
        rate = step
    if -0.999 < rate < 10 and abs(npv(rate)) < 1e-7 * scale:
        return rate

    lo, hi = -0.999, 10.0
    f_lo, f_hi = npv(lo), npv(hi)
    if f_lo * f_hi > 0:
        return None
    for _ in range(200):
        mid = (lo + hi) / 2
        f_mid = npv(mid)
        if abs(f_mid) < 1e-7 * scale:
            return mid
        if f_lo * f_mid < 0:
            hi = mid
        else:
            lo, f_lo = mid, f_mid
    return (lo + hi) / 2


def index_series(closes: dict, dates: list) -> list:
    """
    Benchmark closes rebased to 100 at the first resolvable date, with
    non-trading days carrying the previous close. Dates before the first
    close have no index (None) rather than a back-filled guess.
    """
    result = []
    base = None
    for d in dates:
        picked = latest_close_on_or_before(closes, d)
        if picked is None:
            result.append(None)
            continue
        close = picked[1]
        if base is None:
            base = close
        result.append(close / base * 100)
    return result

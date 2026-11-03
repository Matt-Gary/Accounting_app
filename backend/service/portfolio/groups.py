"""
Exchange / off-exchange section summaries — the two top-level cards on the
investments screen.

Value sums follow the same exclusion rule as the portfolio totals: an unpriced
position is left out and its group flagged incomplete, never counted as zero.
Ratios computed over a partial total would mislead, so shares are None whenever
any group is incomplete.

USD figures sit beside the BRL ones. Invested USD is accumulated at each
trade's own USD/BRL close, so it is not BRL ÷ today's rate. When any position
lacks a USD figure the group's USD numbers are None: a partial sum would read
as the whole.
"""

from .categories import GROUPS, group_of


def group_summaries(assets) -> dict:
    """Per-group value, invested, P&L and share of the combined total."""
    out = {name: {'value_brl': 0.0, 'invested_brl': 0.0, 'complete': True,
                  'value_usd': 0.0, 'invested_usd': 0.0, 'usd_complete': True}
           for name in GROUPS}

    for a in assets:
        group = group_of(a.get('category'))
        if group is None:
            continue
        entry = out[group]
        entry['invested_brl'] += float(a.get('total_invested_brl') or 0)
        invested_usd = a.get('total_invested_usd')
        if invested_usd is None:
            entry['usd_complete'] = False
        else:
            entry['invested_usd'] += float(invested_usd)
        if a.get('value_available'):
            entry['value_brl'] += float(a.get('current_value_brl') or 0)
            value_usd = a.get('current_value_usd')
            if value_usd is None:
                entry['usd_complete'] = False
            else:
                entry['value_usd'] += float(value_usd)
        else:
            entry['complete'] = False

    total = sum(e['value_brl'] for e in out.values())
    shares_valid = total > 0 and all(e['complete'] for e in out.values())

    for entry in out.values():
        entry['pnl_brl'] = entry['value_brl'] - entry['invested_brl']
        entry['pnl_pct'] = (
            entry['pnl_brl'] / entry['invested_brl'] * 100
            if entry['invested_brl'] > 0 else None)
        entry['share_of_total_pct'] = (
            entry['value_brl'] / total * 100 if shares_valid else None)
        if entry['usd_complete']:
            entry['pnl_usd'] = entry['value_usd'] - entry['invested_usd']
            entry['pnl_pct_usd'] = (
                entry['pnl_usd'] / entry['invested_usd'] * 100
                if entry['invested_usd'] > 0 else None)
        else:
            entry['value_usd'] = entry['invested_usd'] = None
            entry['pnl_usd'] = entry['pnl_pct_usd'] = None

    return out

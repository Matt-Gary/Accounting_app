"""
Exchange / off-exchange section summaries — the two top-level cards on the
investments screen.

Value sums follow the same exclusion rule as the portfolio totals: an unpriced
position is left out and its group flagged incomplete, never counted as zero.
Ratios computed over a partial total would mislead, so shares are None whenever
any group is incomplete.
"""

from .categories import GROUPS, group_of


def group_summaries(assets) -> dict:
    """Per-group value, invested, P&L and share of the combined total."""
    out = {name: {'value_brl': 0.0, 'invested_brl': 0.0, 'complete': True}
           for name in GROUPS}

    for a in assets:
        group = group_of(a.get('category'))
        if group is None:
            continue
        entry = out[group]
        entry['invested_brl'] += float(a.get('total_invested_brl') or 0)
        if a.get('value_available'):
            entry['value_brl'] += float(a.get('current_value_brl') or 0)
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

    return out

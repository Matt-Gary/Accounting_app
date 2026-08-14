"""
Portfolio snapshots — the data behind the equity curve.

Two rules keep the history honest:

* An incomplete valuation is never persisted. A snapshot is a fact; storing a
  partial total would later read as "the portfolio was worth less that day"
  (Rule 4 extended to history).
* Days without a visit are forward-filled for the chart, but every synthetic
  day is flagged, so the UI can render "carried" stretches differently from
  observed ones.
"""

from datetime import date, timedelta


def snapshot_from_summary(summary: dict, snapshot_date: date) -> dict | None:
    """
    Map a portfolio summary onto a snapshot row, or None when the summary is
    incomplete and must not be persisted.

    Breakdowns keep only value and invested — ratios are recomputed at read
    time, never stored, so a formula change cannot strand stale figures.
    """
    if not summary.get('totals_complete'):
        return None

    def slim(breakdown: dict) -> dict:
        return {
            name: {
                'value_brl': float(entry.get('value_brl') or 0),
                'invested_brl': float(entry.get('invested_brl') or 0),
            }
            for name, entry in (breakdown or {}).items()
        }

    return {
        'snapshot_date': snapshot_date.isoformat(),
        'total_value_brl': float(summary.get('total_value_brl') or 0),
        'total_invested_brl': float(summary.get('total_invested_brl') or 0),
        'allocation_base_brl': summary.get('allocation_base_brl'),
        # The day's own USD/BRL close — a USD view of the curve converts each
        # day at its own rate, never the current one. None stays None.
        'usd_brl_rate': summary.get('exchange_rate_usd_brl'),
        'by_group': slim(summary.get('by_group')),
        'by_category': slim(summary.get('by_category')),
        'totals_complete': True,
    }


def fill_gaps(rows: list, end_date: date) -> list:
    """
    One point per calendar day from the first snapshot through `end_date`,
    forward-filling days without a snapshot. Each point carries `synthetic`:
    False for an observed row, True for a carried one.
    """
    by_date = {}
    for r in rows:
        raw = r.get('snapshot_date')
        d = date.fromisoformat(raw[:10]) if isinstance(raw, str) else raw
        by_date[d] = r
    if not by_date:
        return []

    first = min(by_date)
    last = max(max(by_date), end_date)

    points = []
    current = None
    day = first
    while day <= last:
        observed = by_date.get(day)
        if observed is not None:
            current = observed
        value = float(current['total_value_brl'])
        invested = float(current['total_invested_brl'])
        raw_rate = current.get('usd_brl_rate')
        rate = float(raw_rate) if raw_rate else None
        points.append({
            'date': day.isoformat(),
            'total_value_brl': value,
            'total_invested_brl': invested,
            # A carried day converts with the rate of the snapshot it carries;
            # a day without a rate has no USD figure rather than a guessed one.
            'total_value_usd': value / rate if rate else None,
            'total_invested_usd': invested / rate if rate else None,
            'synthetic': observed is None,
        })
        day += timedelta(days=1)
    return points

"""
Snapshot mapping and gap-filling for the equity curve.

A snapshot is only ever a fact: an incomplete valuation is refused rather than
stored (Rule 4 extended to history — a missing price must not become a number
that later looks like the portfolio's value). Gaps between visits are
forward-filled for the chart, with each synthetic day flagged as such.
"""

from datetime import date

import pytest

from service.portfolio.history import fill_gaps, snapshot_from_summary

SUMMARY = {
    'totals_complete': True,
    'total_value_brl': 10000.0,
    'total_invested_brl': 8000.0,
    'allocation_base_brl': 9000.0,
    'exchange_rate_usd_brl': 5.0,
    'by_group': {
        'exchange': {'value_brl': 6000.0, 'invested_brl': 5000.0,
                     'pnl_brl': 1000.0, 'complete': True},
    },
    'by_category': {'stock': {'value_brl': 6000.0, 'invested_brl': 5000.0}},
}


# ── snapshot_from_summary ──────────────────────────────────────────────────

def test_snapshot_maps_the_summary():
    row = snapshot_from_summary(SUMMARY, date(2026, 8, 13))
    assert row['snapshot_date'] == '2026-08-13'
    assert row['total_value_brl'] == pytest.approx(10000.0)
    assert row['total_invested_brl'] == pytest.approx(8000.0)
    assert row['allocation_base_brl'] == pytest.approx(9000.0)
    assert row['totals_complete'] is True


def test_snapshot_records_the_days_usd_rate():
    """The rate is an observation of that day — stored so a USD view never
    converts history at today's rate."""
    row = snapshot_from_summary(SUMMARY, date(2026, 8, 13))
    assert row['usd_brl_rate'] == pytest.approx(5.0)
    no_rate = {**SUMMARY, 'exchange_rate_usd_brl': None}
    assert snapshot_from_summary(no_rate, date(2026, 8, 13))['usd_brl_rate'] \
        is None


def test_snapshot_breakdowns_are_slim():
    """Only value and invested go into JSONB — ratios are recomputed, never
    stored, so a formula change cannot strand stale figures in history."""
    row = snapshot_from_summary(SUMMARY, date(2026, 8, 13))
    assert row['by_group']['exchange'] == {
        'value_brl': 6000.0, 'invested_brl': 5000.0}
    assert row['by_category']['stock'] == {
        'value_brl': 6000.0, 'invested_brl': 5000.0}


def test_incomplete_summary_is_never_persisted():
    incomplete = {**SUMMARY, 'totals_complete': False}
    assert snapshot_from_summary(incomplete, date(2026, 8, 13)) is None


# ── fill_gaps ──────────────────────────────────────────────────────────────

def row(d, value, invested, rate=None):
    return {'snapshot_date': d, 'total_value_brl': value,
            'total_invested_brl': invested, 'usd_brl_rate': rate}


def test_gaps_between_visits_are_forward_filled_and_flagged():
    pts = fill_gaps([row('2026-08-10', 100.0, 90.0),
                     row('2026-08-13', 130.0, 90.0)], date(2026, 8, 13))
    assert [p['date'] for p in pts] == [
        '2026-08-10', '2026-08-11', '2026-08-12', '2026-08-13']
    assert pts[0]['synthetic'] is False
    assert pts[1]['synthetic'] is True
    assert pts[1]['total_value_brl'] == pytest.approx(100.0)
    assert pts[3]['synthetic'] is False
    assert pts[3]['total_value_brl'] == pytest.approx(130.0)


def test_series_extends_to_the_end_date():
    """Days after the last visit carry the last known value, flagged."""
    pts = fill_gaps([row('2026-08-10', 100.0, 90.0)], date(2026, 8, 12))
    assert [p['date'] for p in pts] == [
        '2026-08-10', '2026-08-11', '2026-08-12']
    assert pts[2]['synthetic'] is True
    assert pts[2]['total_value_brl'] == pytest.approx(100.0)


def test_empty_history_yields_an_empty_series():
    assert fill_gaps([], date(2026, 8, 13)) == []


def test_single_point_series():
    pts = fill_gaps([row('2026-08-13', 100.0, 90.0)], date(2026, 8, 13))
    assert len(pts) == 1
    assert pts[0]['synthetic'] is False


def test_unsorted_rows_are_handled():
    pts = fill_gaps([row('2026-08-13', 130.0, 90.0),
                     row('2026-08-11', 100.0, 90.0)], date(2026, 8, 13))
    assert [p['date'] for p in pts] == [
        '2026-08-11', '2026-08-12', '2026-08-13']


def test_postgrest_numeric_strings_are_coerced():
    """NUMERIC columns arrive as strings through PostgREST."""
    pts = fill_gaps([row('2026-08-13', '100.5', '90.25', '5.5')],
                    date(2026, 8, 13))
    assert pts[0]['total_value_brl'] == pytest.approx(100.5)
    assert pts[0]['total_invested_brl'] == pytest.approx(90.25)
    assert pts[0]['total_value_usd'] == pytest.approx(100.5 / 5.5)


# ── USD view (each day converted at its own rate) ──────────────────────────

def test_usd_figures_use_each_days_own_rate():
    pts = fill_gaps([row('2026-08-10', 100.0, 90.0, 5.0),
                     row('2026-08-11', 100.0, 90.0, 4.0)], date(2026, 8, 11))
    assert pts[0]['total_value_usd'] == pytest.approx(20.0)
    assert pts[1]['total_value_usd'] == pytest.approx(25.0)
    assert pts[1]['total_invested_usd'] == pytest.approx(22.5)


def test_missing_rate_leaves_usd_none_not_guessed():
    pts = fill_gaps([row('2026-08-13', 100.0, 90.0)], date(2026, 8, 13))
    assert pts[0]['total_value_usd'] is None
    assert pts[0]['total_invested_usd'] is None


def test_carried_days_carry_their_source_rate():
    """A synthetic day converts with the rate of the snapshot it carries."""
    pts = fill_gaps([row('2026-08-10', 100.0, 90.0, 5.0)], date(2026, 8, 11))
    assert pts[1]['synthetic'] is True
    assert pts[1]['total_value_usd'] == pytest.approx(20.0)

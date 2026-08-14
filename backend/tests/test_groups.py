"""
Exchange / off-exchange section summaries — the two top-level cards on the
investments screen. Value sums follow the same exclusion rule as the portfolio
totals (unpriced positions are left out and flagged, never counted as zero).
"""

import pytest

from service.portfolio.groups import group_summaries


def asset(category, value, invested, available=True):
    return {'category': category, 'current_value_brl': value,
            'total_invested_brl': invested, 'value_available': available}


def test_group_sums_match_their_categories():
    assets = [asset('stock', 6000, 5000), asset('etf', 2000, 1500),
              asset('crypto', 3000, 1000), asset('cash_bank', 1000, 1000)]
    groups = group_summaries(assets)
    assert groups['exchange']['value_brl'] == pytest.approx(8000.0)
    assert groups['exchange']['invested_brl'] == pytest.approx(6500.0)
    assert groups['off_exchange']['value_brl'] == pytest.approx(4000.0)
    assert groups['off_exchange']['invested_brl'] == pytest.approx(2000.0)


def test_group_pnl_amount_and_percent():
    groups = group_summaries([asset('stock', 6000, 5000)])
    assert groups['exchange']['pnl_brl'] == pytest.approx(1000.0)
    assert groups['exchange']['pnl_pct'] == pytest.approx(20.0)


def test_shares_of_total_sum_to_one_hundred():
    groups = group_summaries([asset('stock', 7500, 1), asset('crypto', 2500, 1)])
    assert groups['exchange']['share_of_total_pct'] == pytest.approx(75.0)
    assert groups['off_exchange']['share_of_total_pct'] == pytest.approx(25.0)


def test_unpriced_position_marks_its_group_incomplete_and_blocks_shares():
    """A share computed on a partial total would mislead — None, not a guess."""
    assets = [asset('stock', 5000, 4000),
              asset('crypto', None, 1000, available=False)]
    groups = group_summaries(assets)
    assert groups['off_exchange']['complete'] is False
    assert groups['exchange']['complete'] is True
    assert groups['exchange']['share_of_total_pct'] is None
    assert groups['off_exchange']['share_of_total_pct'] is None


def test_empty_portfolio_has_zeroed_groups_without_ratios():
    groups = group_summaries([])
    assert set(groups) == {'exchange', 'off_exchange'}
    assert groups['exchange']['value_brl'] == 0.0
    assert groups['exchange']['pnl_pct'] is None
    assert groups['exchange']['share_of_total_pct'] is None


def test_unknown_category_is_ignored():
    groups = group_summaries([asset('mystery', 999, 999)])
    assert groups['exchange']['value_brl'] == 0.0
    assert groups['off_exchange']['value_brl'] == 0.0

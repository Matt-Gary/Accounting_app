"""
Concentration tests.

The base is stocks + ETFs + broker cash. Everything else is a reserve and gets
no share figure at all — None, never zero.
"""

import pytest

from service.portfolio.allocation import (
    ALLOCATION_CATEGORIES,
    allocation_base,
    annotate,
    concentration_breaches,
    group_breaches,
    group_totals,
    is_complete,
    position_share,
)


def asset(category, value, available=True, name='x'):
    return {
        'name': name,
        'category': category,
        'current_value_brl': value,
        'value_available': available,
    }


# ── What counts toward the base ────────────────────────────────────────────

def test_base_is_deployed_investment_capital():
    assert ALLOCATION_CATEGORIES == {
        'stock', 'etf', 'crypto', 'cash_equivalent', 'cash_broker'}


def test_reserves_are_excluded_from_the_base():
    assets = [
        asset('stock', 6000),
        asset('etf', 2000),
        asset('cash_broker', 2000),
        asset('crypto', 9000),       # deployed capital, counts
        asset('bond', 50000),        # not active
        asset('cash_home', 30000),   # reserve
        asset('cash_bank', 40000),   # reserve
    ]
    assert allocation_base(assets) == pytest.approx(19000.0)


def test_shares_sum_to_one_hundred():
    assets = [asset('stock', 6000), asset('etf', 2000),
              asset('cash_broker', 2000), asset('cash_bank', 99999)]
    annotate(assets)
    shares = [a['portfolio_pct'] for a in assets if a['portfolio_pct'] is not None]
    assert sum(shares) == pytest.approx(100.0)
    assert len(shares) == 3


def test_reserve_gets_none_not_zero():
    """None means 'no share applies'. Zero would read as a worthless holding."""
    assets = [asset('stock', 1000), asset('cash_bank', 5000)]
    annotate(assets)
    assert assets[0]['portfolio_pct'] == pytest.approx(100.0)
    assert assets[1]['portfolio_pct'] is None
    assert assets[1]['in_allocation_base'] is False


def test_a_big_reserve_does_not_dilute_the_active_portfolio():
    """
    The whole point of the narrow base: R$1m in the bank must not make a
    concentrated broker position look diversified.
    """
    assets = [asset('stock', 8000), asset('cash_broker', 2000),
              asset('cash_bank', 1000000)]
    annotate(assets)
    assert assets[0]['portfolio_pct'] == pytest.approx(80.0)


# ── Unpriced positions ─────────────────────────────────────────────────────

def test_unpriced_position_is_excluded_from_the_base():
    """
    Counting an unpriced holding as zero would silently inflate every other
    position's share, which is the failure mode Rule 4 exists to prevent.
    """
    assets = [asset('stock', 5000), asset('stock', None, available=False)]
    assert allocation_base(assets) == pytest.approx(5000.0)
    annotate(assets)
    assert assets[0]['portfolio_pct'] == pytest.approx(100.0)
    assert assets[1]['portfolio_pct'] is None


def test_incomplete_is_flagged():
    assets = [asset('stock', 5000), asset('stock', None, available=False)]
    assert is_complete(assets) is False


def test_complete_when_everything_in_base_is_priced():
    assets = [asset('stock', 5000), asset('cash_bank', None, available=False)]
    # The unpriced one is a reserve, so the base itself is still whole.
    assert is_complete(assets) is True


# ── Degenerate inputs ──────────────────────────────────────────────────────

def test_empty_portfolio_yields_no_shares():
    assets = []
    base, complete = annotate(assets)
    assert base == 0
    assert complete is True


def test_zero_base_gives_none_not_a_division_error():
    assets = [asset('stock', 0)]
    annotate(assets)
    assert assets[0]['portfolio_pct'] is None


def test_single_position_is_one_hundred_percent():
    assets = [asset('stock', 1234.56)]
    annotate(assets)
    assert assets[0]['portfolio_pct'] == pytest.approx(100.0)


def test_share_is_currency_independent():
    """
    A ratio needs no per-currency variant. Scaling every value by a rate leaves
    every share unchanged, so one figure serves both toggle states.
    """
    brl = [asset('stock', 6000), asset('cash_broker', 4000)]
    usd = [asset('stock', 6000 / 5.4), asset('cash_broker', 4000 / 5.4)]
    annotate(brl)
    annotate(usd)
    assert brl[0]['portfolio_pct'] == pytest.approx(usd[0]['portfolio_pct'])


def test_position_share_direct_call():
    assets = [asset('stock', 2500), asset('stock', 7500)]
    base = allocation_base(assets)
    assert position_share(assets[0], base) == pytest.approx(25.0)


# ── Threshold breaches (P1.2 groundwork) ───────────────────────────────────

def test_breaches_returned_largest_first():
    assets = [asset('stock', 5000, name='big'),
              asset('stock', 3000, name='mid'),
              asset('stock', 2000, name='small')]
    annotate(assets)
    over = concentration_breaches(assets, max_position_pct=25)
    assert [a['name'] for a in over] == ['big', 'mid']


def test_no_breaches_when_evenly_spread():
    assets = [asset('stock', 2500) for _ in range(4)]
    annotate(assets)
    assert concentration_breaches(assets, max_position_pct=25) == []


def test_a_reserve_never_appears_as_a_breach():
    """
    A huge bank balance is not a concentrated position. The lone stock is
    correctly flagged — it really is the entire active portfolio — but the
    reserve itself is never a candidate.
    """
    assets = [asset('cash_bank', 1000000, name='savings'),
              asset('stock', 100, name='tiny')]
    annotate(assets)
    over = concentration_breaches(assets, max_position_pct=20)
    assert [a['name'] for a in over] == ['tiny']
    assert all(a['category'] != 'cash_bank' for a in over)


# ── Group totals (currency / sector / country) ─────────────────────────────

def test_group_totals_aggregate_only_the_allocation_base():
    assets = [
        dict(asset('stock', 6000), native_currency='USD'),
        dict(asset('crypto', 2000), native_currency='USD'),
        dict(asset('etf', 2000), native_currency='BRL'),
        dict(asset('cash_bank', 99999), native_currency='BRL'),  # reserve
    ]
    groups = group_totals(assets, 'native_currency')
    assert set(groups) == {'USD', 'BRL'}
    assert groups['USD']['value_brl'] == pytest.approx(8000.0)
    assert groups['USD']['pct'] == pytest.approx(80.0)
    assert groups['BRL']['value_brl'] == pytest.approx(2000.0)
    assert groups['BRL']['pct'] == pytest.approx(20.0)


def test_group_totals_missing_label_goes_to_unknown():
    """No sector recorded is 'unknown', never merged into a real group."""
    assets = [dict(asset('stock', 7500), sector='tech'),
              asset('stock', 2500)]
    groups = group_totals(assets, 'sector')
    assert groups['unknown']['value_brl'] == pytest.approx(2500.0)
    assert groups['tech']['value_brl'] == pytest.approx(7500.0)


def test_group_totals_exclude_unpriced_positions():
    assets = [dict(asset('stock', 5000), sector='tech'),
              dict(asset('stock', None, available=False), sector='tech')]
    groups = group_totals(assets, 'sector')
    assert groups['tech']['value_brl'] == pytest.approx(5000.0)


def test_group_pct_is_none_when_the_base_is_incomplete():
    """A share computed on a partial base would mislead — None, not a guess."""
    assets = [dict(asset('stock', 5000), sector='tech'),
              dict(asset('etf', None, available=False), sector='fin')]
    groups = group_totals(assets, 'sector')
    assert groups['tech']['value_brl'] == pytest.approx(5000.0)
    assert groups['tech']['pct'] is None


def test_group_breaches_returned_largest_first():
    groups = {'tech': {'value_brl': 5000.0, 'pct': 50.0},
              'fin': {'value_brl': 3000.0, 'pct': 30.0},
              'util': {'value_brl': 2000.0, 'pct': 20.0}}
    over = group_breaches(groups, max_pct=25)
    assert [g['group'] for g in over] == ['tech', 'fin']
    assert over[0]['pct'] == pytest.approx(50.0)


def test_unknown_bucket_never_breaches():
    """Missing data is not evidence of concentration."""
    groups = {'unknown': {'value_brl': 9000.0, 'pct': 90.0},
              'tech': {'value_brl': 1000.0, 'pct': 10.0}}
    assert group_breaches(groups, max_pct=25) == []


def test_group_without_a_share_never_breaches():
    groups = {'tech': {'value_brl': 5000.0, 'pct': None}}
    assert group_breaches(groups, max_pct=25) == []

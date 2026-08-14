"""
Category invariants.

These exist because the lists drifted once already: `etf` was added to the
database CHECK constraint but not to CATEGORY_ORDER, which would have raised
KeyError building `category_totals` on the first ETF, and not to
PRICED_CATEGORIES, which would have valued it at cost instead of its quote.
"""

import pytest

from service.portfolio.categories import (
    ALLOCATION_CATEGORIES,
    CASH_CATEGORIES,
    CATEGORY_LABELS,
    CATEGORY_ORDER,
    GROUPS,
    PRICED_CATEGORIES,
    group_of,
)

# Must match the CHECK constraint in migrations/portfolio_analytics_stage_a.sql.
DB_CATEGORIES = {
    'stock', 'etf', 'crypto', 'bond',
    'cash_equivalent', 'cash_broker', 'cash_home', 'cash_bank',
}


def test_display_order_covers_every_database_category():
    """`category_totals` is keyed by CATEGORY_ORDER and indexed with []."""
    assert set(CATEGORY_ORDER) == DB_CATEGORIES


def test_display_order_has_no_duplicates():
    assert len(CATEGORY_ORDER) == len(set(CATEGORY_ORDER))


@pytest.mark.parametrize('group,name', [
    (PRICED_CATEGORIES, 'PRICED_CATEGORIES'),
    (CASH_CATEGORIES, 'CASH_CATEGORIES'),
    (ALLOCATION_CATEGORIES, 'ALLOCATION_CATEGORIES'),
])
def test_every_group_is_a_subset_of_the_display_order(group, name):
    missing = group - set(CATEGORY_ORDER)
    assert not missing, f'{name} has {sorted(missing)} outside CATEGORY_ORDER'


def test_every_category_has_a_report_label():
    missing = set(CATEGORY_ORDER) - set(CATEGORY_LABELS)
    assert not missing, f'no Excel label for {sorted(missing)}'


def test_priced_and_cash_are_mutually_exclusive():
    """
    A category is valued either from a quote or as units at 1.0, never both —
    the valuation branch picks priced first, so an overlap would be silently
    unreachable.
    """
    assert not (PRICED_CATEGORIES & CASH_CATEGORIES)


def test_etf_is_priced_and_ordered():
    """The exact gap that shipped in Stage A."""
    assert 'etf' in CATEGORY_ORDER
    assert 'etf' in PRICED_CATEGORIES


def test_cash_equivalent_is_priced_not_flat_cash():
    """
    A treasury floating-rate ETF has a ticker and a market price, so it is
    valued from its quote — not as units at 1.0 like a bank balance.
    """
    assert 'cash_equivalent' in PRICED_CATEGORIES
    assert 'cash_equivalent' not in CASH_CATEGORIES


def test_cash_equivalent_counts_as_active_broker_capital():
    """Dry powder parked in a treasury ETF is still buying power at the broker."""
    assert 'cash_equivalent' in ALLOCATION_CATEGORIES


def test_reserves_are_outside_the_allocation_base():
    for reserve in ('cash_home', 'cash_bank', 'bond'):
        assert reserve not in ALLOCATION_CATEGORIES


# ── Exchange / off-exchange split (the top-level UI sections) ──────────────

def test_groups_cover_every_category_exactly_once():
    """A category in no group would vanish from the screen; in two, it would
    be double-counted in the section totals."""
    covered = [c for members in GROUPS.values() for c in members]
    assert sorted(covered) == sorted(DB_CATEGORIES)


def test_stocks_and_etfs_trade_on_the_exchange():
    assert group_of('stock') == 'exchange'
    assert group_of('etf') == 'exchange'


def test_crypto_is_off_exchange():
    """Deployed capital (it IS in the allocation base), but a different venue."""
    assert group_of('crypto') == 'off_exchange'


def test_unknown_category_has_no_group():
    assert group_of('yacht') is None


def test_crypto_is_priced_and_counts_as_allocated_capital():
    """
    Crypto is deployed investment capital, not a reserve: it gets a portfolio
    share and falls under the concentration thresholds like any broker position.
    """
    assert 'crypto' in PRICED_CATEGORIES
    assert 'crypto' in ALLOCATION_CATEGORIES

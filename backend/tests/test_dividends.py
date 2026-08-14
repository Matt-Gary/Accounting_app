"""
Trailing dividend income and yield on cost.

The window is (as_of − 12 months, as_of]: an event dated exactly twelve months
ago has rolled out of the trailing year. Income figures come from the replay
engine, so they are net of withholding by construction.
"""

from datetime import date

import pytest

from service.portfolio import cost_basis as cb
from service.portfolio.dividends import trailing_income_brl, yield_on_cost_pct

AS_OF = date(2026, 8, 13)


def income_row(d, amount, currency='BRL', rate=None, tx_type='dividend',
               withholding=0.0):
    return {'transaction_date': d, 'transaction_type': tx_type, 'quantity': 0,
            'original_amount': amount, 'fees_original': 0,
            'withholding_tax_original': withholding,
            'original_currency': currency, 'exchange_rate': rate,
            'id': d, 'created_at': d}


def trail_of(rows):
    _, trail = cb.replay([cb.from_row(r) for r in rows])
    return trail


def test_income_inside_the_window_is_summed():
    trail = trail_of([income_row('2026-01-10', 100.0),
                      income_row('2025-12-01', 50.0)])
    assert trailing_income_brl(trail, AS_OF) == pytest.approx(150.0)


def test_income_exactly_twelve_months_ago_has_rolled_out():
    trail = trail_of([income_row('2025-08-13', 100.0)])
    assert trailing_income_brl(trail, AS_OF) == 0.0


def test_income_one_day_inside_the_window_counts():
    trail = trail_of([income_row('2025-08-14', 100.0)])
    assert trailing_income_brl(trail, AS_OF) == pytest.approx(100.0)


def test_income_on_the_as_of_day_counts():
    trail = trail_of([income_row('2026-08-13', 100.0)])
    assert trailing_income_brl(trail, AS_OF) == pytest.approx(100.0)


def test_coupon_counts_like_a_dividend():
    trail = trail_of([income_row('2026-05-01', 80.0, tx_type='coupon')])
    assert trailing_income_brl(trail, AS_OF) == pytest.approx(80.0)


def test_income_is_net_of_withholding():
    trail = trail_of([income_row('2026-05-01', 100.0, currency='USD',
                                 rate=5.0, withholding=30.0)])
    assert trailing_income_brl(trail, AS_OF) == pytest.approx(350.0)


def test_buys_never_count_as_income():
    rows = [{'transaction_date': '2026-05-01', 'transaction_type': 'buy',
             'quantity': 10, 'original_amount': 1000.0, 'fees_original': 0,
             'withholding_tax_original': 0, 'original_currency': 'BRL',
             'exchange_rate': None, 'id': 'b1', 'created_at': 'c1'}]
    assert trailing_income_brl(trail_of(rows), AS_OF) == 0.0


def test_future_dated_income_is_ignored():
    trail = trail_of([income_row('2026-09-01', 100.0)])
    assert trailing_income_brl(trail, AS_OF) == 0.0


# ── Yield on cost ──────────────────────────────────────────────────────────

def test_yield_on_cost():
    assert yield_on_cost_pct(500.0, 10000.0) == pytest.approx(5.0)


@pytest.mark.parametrize('invested', [0.0, -1.0, None])
def test_yield_on_cost_is_none_without_invested_capital(invested):
    """None, not zero — a closed position has no yield, not a 0% yield."""
    assert yield_on_cost_pct(500.0, invested) is None

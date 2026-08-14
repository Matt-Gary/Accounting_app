"""
FX tests — Rule 4: a missing rate is never silently replaced by a default.
"""

from datetime import date

import pytest

from service.portfolio.fx import (
    MissingRateError,
    RateTable,
    latest_close_on_or_before,
    transaction_rate,
)

FULL = RateTable(usd_brl=5.40, eur_usd=1.08, usd_pln=4.05, as_of=1_700_000_000)


# ── Transaction rates (tax path: absent means raise) ───────────────────────

def test_brl_needs_no_rate():
    assert transaction_rate('BRL', None) == 1.0


def test_currency_is_case_insensitive():
    assert transaction_rate('brl', None) == 1.0


def test_explicit_rate_is_used():
    assert transaction_rate('USD', 5.25) == 5.25


@pytest.mark.parametrize('bad', [None, 0, -1.0])
def test_unusable_rate_raises(bad):
    with pytest.raises(MissingRateError):
        transaction_rate('USD', bad)


# ── Live rates (valuation path: absent means None, never a guess) ──────────

def test_conversion_for_each_supported_currency():
    assert FULL.rate_to_brl('BRL') == 1.0
    assert FULL.rate_to_brl('USD') == pytest.approx(5.40)
    assert FULL.rate_to_brl('EUR') == pytest.approx(1.08 * 5.40)
    assert FULL.rate_to_brl('PLN') == pytest.approx(5.40 / 4.05)


def test_to_brl_multiplies():
    assert FULL.to_brl(100.0, 'USD') == pytest.approx(540.0)


def test_missing_usd_brl_blocks_every_non_brl_currency():
    """Every non-BRL path routes through USD/BRL, so losing it loses all."""
    t = RateTable(usd_brl=None, eur_usd=1.08, usd_pln=4.05)
    assert t.rate_to_brl('BRL') == 1.0          # still fine, no conversion
    for c in ('USD', 'EUR', 'PLN'):
        assert t.rate_to_brl(c) is None
        assert t.to_brl(100.0, c) is None
        assert t.missing_for(c) is not None


def test_missing_cross_rate_blocks_only_that_currency():
    t = RateTable(usd_brl=5.40, eur_usd=None, usd_pln=4.05)
    assert t.rate_to_brl('USD') == pytest.approx(5.40)
    assert t.rate_to_brl('PLN') is not None
    assert t.rate_to_brl('EUR') is None
    assert 'EUR/USD' in t.missing_for('EUR')


def test_zero_pln_rate_does_not_divide_by_zero():
    t = RateTable(usd_brl=5.40, eur_usd=1.08, usd_pln=0)
    assert t.rate_to_brl('PLN') is None


def test_unknown_currency_is_unconvertible_not_one_to_one():
    """
    The old code returned the value unchanged for unrecognised currencies,
    silently treating them as BRL. That is the failure mode Rule 4 forbids.
    """
    assert FULL.rate_to_brl('JPY') is None
    assert FULL.to_brl(1000.0, 'JPY') is None
    assert FULL.missing_for('JPY') == 'Unsupported currency JPY'


def test_no_missing_reason_when_convertible():
    assert FULL.missing_for('USD') is None


def test_as_of_is_carried_for_staleness_reporting():
    assert FULL.as_of == 1_700_000_000
    assert RateTable().as_of is None


# ── Historical closes (form prefill: the rate on the trade date) ───────────

CLOSES = {
    date(2026, 8, 10): 5.41,   # Monday
    date(2026, 8, 11): 5.43,
    date(2026, 8, 14): 5.45,   # Friday
}


def test_exact_trading_day_returns_that_close():
    assert latest_close_on_or_before(CLOSES, date(2026, 8, 11)) == \
        (date(2026, 8, 11), 5.43)


def test_weekend_falls_back_to_the_last_close():
    """A Sunday trade date gets Friday's close, labelled with Friday's date."""
    assert latest_close_on_or_before(CLOSES, date(2026, 8, 16)) == \
        (date(2026, 8, 14), 5.45)


def test_gap_inside_the_series_falls_back_not_forward():
    assert latest_close_on_or_before(CLOSES, date(2026, 8, 12)) == \
        (date(2026, 8, 11), 5.43)


def test_date_before_the_series_returns_none():
    assert latest_close_on_or_before(CLOSES, date(2026, 8, 9)) is None


def test_empty_series_returns_none():
    assert latest_close_on_or_before({}, date(2026, 8, 12)) is None

"""
Performance engine: external flows, TWR, XIRR and benchmark indexing.

Flow convention (confirmed against the family's real logging habits): buys and
deposits are inflows (+), sells and withdrawals outflows (−), income leaves the
portfolio net of withholding (−) — a dividend re-deposited into a cash asset
then nets out to zero through its matching deposit row.
"""

from datetime import date

import pytest

from service.portfolio.performance import (
    TWR_MIN_DAYS,
    XIRR_MIN_DAYS,
    availability,
    convert_pairs,
    external_flows,
    index_series,
    twr,
    xirr,
)


def tx(d, kind, brl, currency='BRL', rate=None, withholding=0.0):
    return {'transaction_date': d, 'transaction_type': kind,
            'brl_amount': brl, 'original_currency': currency,
            'exchange_rate': rate, 'withholding_tax_original': withholding}


# ── external_flows ─────────────────────────────────────────────────────────

def test_buys_and_deposits_are_inflows():
    flows = external_flows([tx('2026-01-10', 'buy', 1000.0),
                            tx('2026-01-11', 'deposit', 500.0)])
    assert flows == [(date(2026, 1, 10), 1000.0), (date(2026, 1, 11), 500.0)]


def test_sells_and_withdrawals_are_outflows():
    flows = external_flows([tx('2026-01-10', 'sell', 400.0),
                            tx('2026-01-11', 'withdrawal', 100.0)])
    assert flows == [(date(2026, 1, 10), -400.0), (date(2026, 1, 11), -100.0)]


def test_same_day_flows_are_aggregated():
    """The user's deposit + buy + withdrawal pattern nets to the new money."""
    flows = external_flows([tx('2026-01-10', 'deposit', 1000.0),
                            tx('2026-01-10', 'buy', 1000.0),
                            tx('2026-01-10', 'withdrawal', 1000.0)])
    assert flows == [(date(2026, 1, 10), pytest.approx(1000.0))]


def test_income_leaves_the_portfolio_net_of_withholding():
    # brl_amount stores GROSS x rate; the flow is the net that actually left.
    flows = external_flows([tx('2026-01-10', 'dividend', 500.0,
                               currency='USD', rate=5.0, withholding=30.0)])
    assert flows == [(date(2026, 1, 10), pytest.approx(-350.0))]


def test_coupon_flows_like_a_dividend():
    flows = external_flows([tx('2026-01-10', 'coupon', 100.0)])
    assert flows == [(date(2026, 1, 10), pytest.approx(-100.0))]


def test_empty_ledger_has_no_flows():
    assert external_flows([]) == []


# ── TWR (Modified Dietz per subperiod, chain-linked) ───────────────────────

def val(d, v):
    return (date.fromisoformat(d), v)


def test_no_flows_is_the_plain_return():
    result = twr([val('2026-01-01', 100.0), val('2026-02-01', 110.0)], [])
    assert result['twr_pct'] == pytest.approx(10.0)
    assert [p['index'] for p in result['series']] == [
        pytest.approx(100.0), pytest.approx(110.0)]


def test_chain_linking_across_subperiods():
    result = twr([val('2026-01-01', 100.0), val('2026-02-01', 110.0),
                  val('2026-03-01', 121.0)], [])
    assert result['twr_pct'] == pytest.approx(21.0)


def test_a_deposit_is_not_counted_as_performance():
    """Doubling the portfolio by depositing money is 0% return."""
    result = twr([val('2026-01-01', 100.0), val('2026-01-31', 200.0)],
                 [(date(2026, 1, 31), 100.0)])
    assert result['twr_pct'] == pytest.approx(0.0)


def test_mid_period_flow_uses_modified_dietz_weighting():
    # 30-day period; 100 deposited mid-period (15 days remaining => w=0.5):
    # r = (210 - 100 - 100) / (100 + 50) = 6.6667%
    result = twr([val('2026-01-01', 100.0), val('2026-01-31', 210.0)],
                 [(date(2026, 1, 16), 100.0)])
    assert result['twr_pct'] == pytest.approx(6.6667, rel=1e-3)


def test_single_valuation_yields_none_with_a_warning():
    result = twr([val('2026-01-01', 100.0)], [])
    assert result['twr_pct'] is None
    assert result['series'] == []
    assert result['warnings']


def test_non_positive_base_is_skipped_and_flagged():
    result = twr([val('2026-01-01', 0.0), val('2026-02-01', 100.0)], [])
    assert result['twr_pct'] is None
    assert result['warnings']


# ── XIRR ───────────────────────────────────────────────────────────────────

def test_doubling_in_a_year_is_one_hundred_percent():
    r = xirr([(date(2025, 8, 13), -100.0), (date(2026, 8, 13), 200.0)])
    assert r == pytest.approx(1.0, rel=1e-2)


def test_flat_value_is_zero_return():
    r = xirr([(date(2025, 8, 13), -100.0), (date(2026, 8, 13), 100.0)])
    assert r == pytest.approx(0.0, abs=1e-6)


def test_multiple_flows_match_a_hand_computed_root():
    # NPV(r) = -1000 - 500/(1+r)^(181/365) + 1700/(1+r)^1 = 0  →  r ≈ 0.160
    # (checked by hand: NPV(0.16) ≈ +1.0, NPV(0.161) ≈ 0.0)
    r = xirr([(date(2025, 1, 1), -1000.0), (date(2025, 7, 1), -500.0),
              (date(2026, 1, 1), 1700.0)])
    assert r == pytest.approx(0.160, rel=1e-2)


def test_all_flows_one_sign_has_no_rate():
    assert xirr([(date(2025, 1, 1), -100.0),
                 (date(2026, 1, 1), -100.0)]) is None
    assert xirr([]) is None


def test_deep_loss_still_converges():
    r = xirr([(date(2025, 8, 13), -100.0), (date(2026, 8, 13), 10.0)])
    assert r == pytest.approx(-0.9, rel=1e-2)


# ── Benchmark indexing ─────────────────────────────────────────────────────

def test_index_starts_at_one_hundred_and_tracks_closes():
    closes = {date(2026, 1, 1): 50.0, date(2026, 1, 2): 55.0}
    idx = index_series(closes, [date(2026, 1, 1), date(2026, 1, 2)])
    assert idx == [pytest.approx(100.0), pytest.approx(110.0)]


def test_non_trading_days_carry_the_last_close():
    closes = {date(2026, 1, 2): 50.0}   # Friday
    idx = index_series(closes, [date(2026, 1, 2), date(2026, 1, 4)])
    assert idx == [pytest.approx(100.0), pytest.approx(100.0)]


def test_dates_before_the_first_close_have_no_index():
    closes = {date(2026, 1, 5): 50.0, date(2026, 1, 6): 55.0}
    idx = index_series(closes, [date(2026, 1, 4), date(2026, 1, 5),
                                date(2026, 1, 6)])
    assert idx[0] is None
    assert idx[1] == pytest.approx(100.0)
    assert idx[2] == pytest.approx(110.0)


def test_empty_inputs_yield_empty_or_none():
    assert index_series({}, []) == []
    assert index_series({}, [date(2026, 1, 1)]) == [None]
# ── convert_pairs ──────────────────────────────────────────────────────────

def test_converts_each_day_at_its_own_rate():
    """A BRL series becomes USD at the rate of the day it happened, never a
    single rate applied to the whole window."""
    rates = {date(2026, 1, 10): 5.0, date(2026, 1, 12): 4.0}
    pairs = [(date(2026, 1, 10), 1000.0), (date(2026, 1, 12), 1000.0)]

    converted, missing = convert_pairs(pairs, rates)

    assert converted == [(date(2026, 1, 10), 200.0), (date(2026, 1, 12), 250.0)]
    assert missing == []


def test_day_without_a_close_uses_the_last_close_before_it():
    """Markets skip weekends; Sunday is valued at Friday's close, like the
    benchmark series."""
    rates = {date(2026, 1, 9): 5.0}  # Friday
    pairs = [(date(2026, 1, 11), 1000.0)]  # Sunday

    converted, missing = convert_pairs(pairs, rates)

    assert converted == [(date(2026, 1, 11), 200.0)]
    assert missing == []


def test_date_before_the_first_close_is_refused_not_guessed():
    """No rate on or before the date means the figure cannot be computed. It is
    reported as missing rather than converted at some other day's rate."""
    rates = {date(2026, 1, 10): 5.0}
    pairs = [(date(2026, 1, 5), 1000.0), (date(2026, 1, 10), 1000.0)]

    converted, missing = convert_pairs(pairs, rates)

    assert converted == [(date(2026, 1, 10), 200.0)]
    assert missing == [date(2026, 1, 5)]


def test_no_rates_at_all_refuses_every_date():
    converted, missing = convert_pairs([(date(2026, 1, 10), 1000.0)], {})

    assert converted == []
    assert missing == [date(2026, 1, 10)]


def test_a_zero_rate_is_not_a_rate():
    """A zero or negative close would divide the portfolio into nonsense; it is
    treated as absent, in line with the FX module's refusal to guess."""
    converted, missing = convert_pairs([(date(2026, 1, 10), 1000.0)],
                                       {date(2026, 1, 10): 0.0})

    assert converted == []
    assert missing == [date(2026, 1, 10)]
# ── availability ───────────────────────────────────────────────────────────

def test_fresh_history_owes_the_full_wait_for_both_figures():
    avail = availability(0)

    assert avail['twr_days_remaining'] == TWR_MIN_DAYS
    assert avail['xirr_days_remaining'] == XIRR_MIN_DAYS


def test_a_figure_becomes_available_the_day_its_threshold_is_reached():
    """None means available — the caller shows a number instead of a countdown."""
    avail = availability(TWR_MIN_DAYS)

    assert avail['twr_days_remaining'] is None
    assert avail['xirr_days_remaining'] == XIRR_MIN_DAYS - TWR_MIN_DAYS


def test_the_day_before_a_threshold_still_owes_one_day():
    assert availability(TWR_MIN_DAYS - 1)['twr_days_remaining'] == 1


def test_long_history_owes_nothing():
    avail = availability(XIRR_MIN_DAYS + 500)

    assert avail['twr_days_remaining'] is None
    assert avail['xirr_days_remaining'] is None


def test_twr_unlocks_before_xirr():
    """A two-week return is reportable; annualizing it is not."""
    assert TWR_MIN_DAYS < XIRR_MIN_DAYS

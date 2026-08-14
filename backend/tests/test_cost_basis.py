"""
Cost basis engine tests — custo médio ponderado.

The five cases the specification requires are marked REQUIRED. Everything here
runs against pure functions: no database, no network, no fixtures.
"""

from datetime import date

import pytest

from service.portfolio.cost_basis import (
    OversellError,
    Position,
    Transaction,
    WeightedAverage,
    replay,
)
from service.portfolio.fx import MissingRateError

APPROX = 1e-9


def buy(day, qty, amount, rate, fee=0.0, currency='USD', seq=''):
    return Transaction(
        transaction_date=date(2024, 1, day) if isinstance(day, int) else day,
        transaction_type='buy', quantity=qty, original_amount=amount,
        fees_original=fee, original_currency=currency, exchange_rate=rate,
        id=seq or f'buy-{day}-{qty}', created_at=seq,
    )


def sell(day, qty, amount, rate, fee=0.0, currency='USD', seq=''):
    return Transaction(
        transaction_date=date(2024, 1, day) if isinstance(day, int) else day,
        transaction_type='sell', quantity=qty, original_amount=amount,
        fees_original=fee, original_currency=currency, exchange_rate=rate,
        id=seq or f'sell-{day}-{qty}', created_at=seq,
    )


# ── REQUIRED 1: a later purchase must not alter an earlier sale ─────────────

def test_later_purchase_does_not_change_earlier_sale():
    first_two = [
        buy(10, 10, 1000.0, 5.00),     # avg_orig 100, avg_brl 500
        sell(15, 5, 600.0, 5.20),      # gain_orig 100, gain_brl 620
    ]
    full = first_two + [
        buy(20, 10, 2000.0, 6.00),
        sell(25, 5, 750.0, 5.50),
    ]

    _, trail_short = replay(first_two)
    _, trail_full = replay(full)

    sale_short = trail_short[1]
    sale_full = trail_full[1]

    # The first sale's realized result is identical either way.
    assert sale_short.realized_orig == pytest.approx(100.0, abs=APPROX)
    assert sale_short.realized_brl == pytest.approx(620.0, abs=APPROX)
    assert sale_full.realized_orig == pytest.approx(sale_short.realized_orig, abs=APPROX)
    assert sale_full.realized_brl == pytest.approx(sale_short.realized_brl, abs=APPROX)

    # And the average it was priced at is untouched by the later buy.
    assert sale_full.avg_brl_before == pytest.approx(500.0, abs=APPROX)


def test_average_recomputed_only_on_buy():
    state, trail = replay([
        buy(10, 10, 1000.0, 5.00),
        sell(15, 5, 600.0, 5.20),
        buy(20, 10, 2000.0, 6.00),
    ])
    # Sale leaves both averages exactly where they were.
    assert trail[1].avg_orig_before == trail[1].avg_orig_after
    assert trail[1].avg_brl_before == trail[1].avg_brl_after

    # Buy after the sale: (100*5 + 2000)/15 and (500*5 + 12000)/15
    assert state.avg_orig == pytest.approx(2500.0 / 15.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(14500.0 / 15.0, abs=APPROX)


# ── REQUIRED 2: partial sale, then buying more ─────────────────────────────

def test_partial_sale_then_rebuy():
    state, trail = replay([
        buy(10, 10, 1000.0, 5.00),     # avg_orig 100, avg_brl 500
        sell(15, 4, 480.0, 5.00),      # 6 left, averages unchanged
        buy(20, 4, 600.0, 5.00),       # avg_orig (100*6+600)/10 = 120
    ])
    after_sale = trail[1]
    assert after_sale.qty_after == pytest.approx(6.0, abs=APPROX)
    assert after_sale.avg_orig_after == pytest.approx(100.0, abs=APPROX)

    # Remaining basis == previous basis - cost of the units sold.
    assert after_sale.cost_of_sold_orig == pytest.approx(400.0, abs=APPROX)
    assert 6 * after_sale.avg_orig_after == pytest.approx(1000.0 - 400.0, abs=APPROX)

    assert state.quantity == pytest.approx(10.0, abs=APPROX)
    assert state.avg_orig == pytest.approx(120.0, abs=APPROX)


# ── REQUIRED 3: the two averages are genuinely independent ─────────────────

def test_brl_average_is_not_orig_average_times_current_rate():
    state, _ = replay([
        buy(10, 10, 1000.0, 5.00),     # 10 units at $100, R$5.00
        buy(20, 10, 1000.0, 6.00),     # 10 units at $100, R$6.00
    ])
    # Same price in USD both times, so avg_orig is exactly 100.
    assert state.avg_orig == pytest.approx(100.0, abs=APPROX)
    # BRL average blends the two purchase-day rates: (5000 + 6000) / 20.
    assert state.avg_brl == pytest.approx(550.0, abs=APPROX)

    # The whole point: today's rate must NOT reproduce the BRL average.
    todays_rate = 7.0
    assert state.avg_brl != pytest.approx(state.avg_orig * todays_rate, abs=1e-6)


# ── REQUIRED 4: fully closed position is internally consistent ─────────────

def test_full_exit_is_consistent():
    txs = [
        buy(5, 10, 1000.0, 5.00, fee=10.0),
        buy(10, 10, 1200.0, 5.50, fee=12.0),
        sell(20, 20, 2600.0, 6.00, fee=26.0),
    ]
    state, trail = replay(txs)

    assert state.quantity == pytest.approx(0.0, abs=APPROX)

    total_cost_orig = (1000.0 + 10.0) + (1200.0 + 12.0)
    total_proceeds_orig = 2600.0 - 26.0
    assert state.realized_orig == pytest.approx(
        total_proceeds_orig - total_cost_orig, abs=1e-6)

    total_cost_brl = (1010.0 * 5.00) + (1212.0 * 5.50)
    total_proceeds_brl = 2574.0 * 6.00
    assert state.realized_brl == pytest.approx(
        total_proceeds_brl - total_cost_brl, abs=1e-6)

    # Realized total equals the sum of the per-sale audit rows.
    assert state.realized_brl == pytest.approx(
        sum(s.realized_brl for s in trail), abs=1e-6)


# ── REQUIRED 5: a broker transfer must not reset the average ───────────────

def test_broker_transfer_preserves_average_history():
    """
    The engine has no notion of custodian, so a change of broker cannot reset
    anything. This test pins that invariant: transactions recorded after a
    transfer continue from the existing average rather than starting fresh.
    """
    before, _ = replay([
        buy(5, 10, 1000.0, 5.00),
        buy(10, 10, 1400.0, 5.00),
    ])
    assert before.avg_orig == pytest.approx(120.0, abs=APPROX)

    after, trail = replay([
        buy(5, 10, 1000.0, 5.00),
        buy(10, 10, 1400.0, 5.00),
        # ... custody moves here; the ledger simply continues ...
        buy(20, 10, 1600.0, 5.00),
    ])
    # Continues from 120, does not restart at 160.
    assert trail[2].avg_orig_before == pytest.approx(120.0, abs=APPROX)
    assert after.avg_orig == pytest.approx(4000.0 / 30.0, abs=APPROX)
    assert after.avg_orig != pytest.approx(160.0, abs=1e-6)


# ── Fees: RFB treatment ────────────────────────────────────────────────────

def test_fee_raises_basis_on_buy_before_conversion():
    state, trail = replay([buy(10, 2, 200.0, 5.00, fee=1.0)])
    # (200 + 1) x 5 = 1005, not (200 - 1) x 5 = 995.
    assert trail[0].cost_orig == pytest.approx(201.0, abs=APPROX)
    assert trail[0].cost_brl == pytest.approx(1005.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(502.5, abs=APPROX)


def test_fee_reduces_proceeds_on_sell():
    _, trail = replay([
        buy(10, 2, 200.0, 5.00),
        sell(20, 2, 200.0, 5.00, fee=1.0),
    ])
    assert trail[1].proceeds_orig == pytest.approx(199.0, abs=APPROX)
    assert trail[1].proceeds_brl == pytest.approx(995.0, abs=APPROX)


def test_zero_fee_is_unchanged():
    state, _ = replay([buy(10, 2, 200.0, 5.00)])
    assert state.avg_brl == pytest.approx(500.0, abs=APPROX)


# ── Deterministic ordering ─────────────────────────────────────────────────

def test_same_day_transactions_ordered_by_created_at():
    """
    Both rows share a date. Supplied sell-first; correct ordering must still
    place the buy first, otherwise this oversells and raises.
    """
    txs = [
        sell(10, 5, 600.0, 5.20, seq='2024-01-10T10:00:00'),
        buy(10, 10, 1000.0, 5.00, seq='2024-01-10T09:00:00'),
    ]
    state, trail = replay(txs)
    assert trail[0].transaction_type == 'buy'
    assert state.quantity == pytest.approx(5.0, abs=APPROX)


def test_same_day_different_currencies_is_deterministic():
    """
    Three transactions on one date in two currencies, with a sale in the middle
    so the ordering genuinely changes the answer: if the EUR buy were applied
    before the sale it would blend into the average the sale is priced against.
    Shuffling the input must not move the realized figure.
    """
    txs = [
        buy(10, 10, 1000.0, 5.00, currency='USD', seq='2024-01-10T09:00:00'),
        sell(10, 5, 550.0, 5.00, currency='USD', seq='2024-01-10T10:00:00'),
        buy(10, 10, 900.0, 6.00, currency='EUR', seq='2024-01-10T11:00:00'),
    ]
    expected_gain_brl = 550.0 * 5.00 - 500.0 * 5     # proceeds - cost at avg 500

    for ordering in ([0, 1, 2], [2, 1, 0], [1, 2, 0], [2, 0, 1]):
        state, trail = replay([txs[i] for i in ordering])
        sale = next(s for s in trail if s.transaction_type == 'sell')
        assert sale.avg_brl_before == pytest.approx(500.0, abs=APPROX)
        assert sale.realized_brl == pytest.approx(expected_gain_brl, abs=1e-9)
        assert state.quantity == pytest.approx(15.0, abs=APPROX)


# ── Guard rails ────────────────────────────────────────────────────────────

def test_oversell_raises_rather_than_going_negative():
    with pytest.raises(OversellError):
        replay([buy(10, 5, 500.0, 5.00), sell(20, 10, 1200.0, 5.00)])


def test_sell_with_no_holding_raises():
    with pytest.raises(OversellError):
        replay([sell(10, 1, 100.0, 5.00)])


def test_missing_exchange_rate_raises_never_substitutes():
    tx = Transaction(
        transaction_date=date(2024, 1, 10), transaction_type='buy',
        quantity=1, original_amount=100.0,
        original_currency='USD', exchange_rate=None,
    )
    with pytest.raises(MissingRateError):
        replay([tx])


def test_non_positive_exchange_rate_raises():
    with pytest.raises(MissingRateError):
        replay([buy(10, 1, 100.0, 0.0)])


def test_brl_transaction_needs_no_rate():
    state, _ = replay([
        Transaction(
            transaction_date=date(2024, 1, 10), transaction_type='buy',
            quantity=10, original_amount=1000.0,
            original_currency='BRL', exchange_rate=None,
        )
    ])
    assert state.avg_brl == pytest.approx(100.0, abs=APPROX)
    assert state.avg_orig == pytest.approx(100.0, abs=APPROX)


# ── Income ─────────────────────────────────────────────────────────────────

def test_dividend_does_not_move_quantity_or_basis():
    state, trail = replay([
        buy(10, 10, 1000.0, 5.00),
        Transaction(
            transaction_date=date(2024, 2, 1), transaction_type='dividend',
            original_amount=50.0, withholding_tax_original=7.5,
            original_currency='USD', exchange_rate=5.40,
        ),
    ])
    assert state.quantity == pytest.approx(10.0, abs=APPROX)
    assert state.avg_orig == pytest.approx(100.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(500.0, abs=APPROX)
    # Net of withholding, converted at that day's rate.
    assert state.income_orig == pytest.approx(42.5, abs=APPROX)
    assert state.income_brl == pytest.approx(42.5 * 5.40, abs=1e-9)
    assert state.withholding_brl == pytest.approx(7.5 * 5.40, abs=1e-9)
    assert trail[1].qty_before == trail[1].qty_after


# ── Acceptance fixture from the brief ──────────────────────────────────────

def test_acceptance_three_msft_buys_then_partial_sale():
    txs = [
        buy(date(2024, 1, 12), 10, 3800.00, 4.90),
        buy(date(2024, 3, 4), 5, 2000.00, 5.10),
        buy(date(2024, 6, 20), 10, 4200.00, 5.35),
        sell(date(2024, 9, 10), 12, 5400.00, 5.60),
    ]
    state, trail = replay(txs)

    cost_orig = 3800.0 + 2000.0 + 4200.0          # 10000 over 25 units
    cost_brl = 3800 * 4.90 + 2000 * 5.10 + 4200 * 5.35
    avg_orig = cost_orig / 25.0
    avg_brl = cost_brl / 25.0

    sale = trail[3]
    assert sale.avg_orig_before == pytest.approx(avg_orig, abs=1e-9)
    assert sale.avg_brl_before == pytest.approx(avg_brl, abs=1e-9)

    # Realized gain, separately in USD and BRL.
    assert sale.realized_orig == pytest.approx(5400.0 - avg_orig * 12, abs=1e-9)
    assert sale.realized_brl == pytest.approx(
        5400.0 * 5.60 - avg_brl * 12, abs=1e-9)

    # 13 units remain, priced at the untouched averages.
    assert state.quantity == pytest.approx(13.0, abs=APPROX)
    assert state.avg_orig == pytest.approx(avg_orig, abs=1e-9)
    assert state.avg_brl == pytest.approx(avg_brl, abs=1e-9)

    # Audit trail covers every transaction, in order.
    assert len(trail) == 4
    assert [s.transaction_date for s in trail] == sorted(
        s.transaction_date for s in trail)


def test_method_is_pluggable():
    assert WeightedAverage().name == 'weighted_average'
    state, _ = replay([buy(10, 10, 1000.0, 5.00)], method=WeightedAverage())
    assert state.avg_orig == pytest.approx(100.0, abs=APPROX)


def test_empty_ledger_is_a_zero_position():
    state, trail = replay([])
    assert state == Position()
    assert trail == []

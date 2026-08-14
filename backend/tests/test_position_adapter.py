"""
Contract between the cost-basis engine and the portfolio response.

`get_portfolio_summary` indexes the position dict with `[]`, so a key the
adapter forgets to emit takes down the whole endpoint rather than degrading one
field. This pins the set of keys it must return.
"""

import pytest

from service.investment_service import _compute_position

# Every key `get_portfolio_summary` reads off the position dict.
REQUIRED_KEYS = {
    'quantity',
    'avg_cost_brl',
    'total_invested_brl',
    'realized_gains_brl',
    'realized_gains_original',
    'dividends_brl',
    'dividends_original',
    'fees_brl_total',
    'fees_orig_total',
    'avg_cost_original',
    'total_invested_original',
    'audit_trail',
}


def rows(*txs):
    return list(txs)


def buy_row(**over):
    row = {
        'id': 'tx-1',
        'created_at': '2024-01-01T00:00:00',
        'transaction_date': '2024-01-01',
        'transaction_type': 'buy',
        'quantity': 10,
        'original_amount': 1000.0,
        'original_currency': 'USD',
        'exchange_rate': 5.0,
        'fees_original': 0.0,
    }
    row.update(over)
    return row


def test_adapter_emits_every_key_the_response_reads():
    pos = _compute_position(rows(buy_row()))
    missing = REQUIRED_KEYS - set(pos)
    assert not missing, f'position dict is missing {sorted(missing)}'


def test_adapter_emits_keys_for_an_empty_ledger():
    pos = _compute_position([])
    missing = REQUIRED_KEYS - set(pos)
    assert not missing, f'position dict is missing {sorted(missing)}'


def test_both_averages_are_populated_independently():
    pos = _compute_position(rows(buy_row()))
    assert pos['avg_cost_original'] == pytest.approx(100.0)
    assert pos['avg_cost_brl'] == pytest.approx(500.0)
    assert pos['total_invested_original'] == pytest.approx(1000.0)
    assert pos['total_invested_brl'] == pytest.approx(5000.0)


def test_fee_totals_are_tracked_in_both_units():
    pos = _compute_position(rows(buy_row(fees_original=2.0)))
    assert pos['fees_orig_total'] == pytest.approx(2.0)
    assert pos['fees_brl_total'] == pytest.approx(10.0)


def test_audit_trail_has_one_step_per_transaction():
    pos = _compute_position(rows(
        buy_row(),
        buy_row(id='tx-2', created_at='2024-02-01T00:00:00',
                transaction_date='2024-02-01'),
    ))
    assert len(pos['audit_trail']) == 2


def test_totals_agree_with_the_trail():
    """The trail and the totals come from one walk and must never disagree."""
    pos = _compute_position(rows(
        buy_row(),
        buy_row(id='tx-2', created_at='2024-02-01T00:00:00',
                transaction_date='2024-02-01', transaction_type='sell',
                quantity=4, original_amount=600.0, exchange_rate=6.0),
    ))
    trail_realized = sum(s.realized_brl for s in pos['audit_trail'])
    assert pos['realized_gains_brl'] == pytest.approx(trail_realized)

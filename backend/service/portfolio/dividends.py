"""
Dividend metrics: trailing income and yield on cost.

Income figures are taken from the replay engine's audit trail, so they are net
of withholding by construction, and the date used is the booking date the user
entered (`transaction_date`) — not the ex-date, which this ledger does not know.
"""

from datetime import date

from dateutil.relativedelta import relativedelta

from .cost_basis import INCOME_TYPES


def trailing_income_brl(trail, as_of: date, months: int = 12) -> float:
    """
    Net income (dividends + coupons) booked in the window (as_of − months, as_of].

    The lower bound is exclusive: an event dated exactly twelve months ago has
    rolled out of the trailing year. Future-dated events never count.
    """
    cutoff = as_of - relativedelta(months=months)
    return sum(
        step.income_brl for step in trail
        if step.transaction_type in INCOME_TYPES
        and cutoff < step.transaction_date <= as_of
    )


def yield_on_cost_pct(income_brl: float, invested_brl) -> float | None:
    """
    Trailing income as a percentage of invested capital.

    None, not zero, when there is no invested capital — a closed position has
    no yield rather than a 0% yield.
    """
    if not invested_brl or invested_brl <= 0:
        return None
    return income_brl / invested_brl * 100

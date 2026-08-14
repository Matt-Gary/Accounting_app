"""
Cost basis engine — custo médio ponderado (Receita Federal).

The ledger is the only source of truth. Every aggregate here is derived by
chronological replay and is never persisted as the sole record of itself.

Two running averages are maintained side by side and are never derived from one
another:

* ``avg_orig`` — in the instrument's own currency, drives performance.
* ``avg_brl``  — accumulated at the exchange rate of *each individual purchase
  day*, drives tax.

Computing ``avg_brl`` as ``avg_orig * current_rate`` is the single most common
way this calculation goes wrong; it would silently re-price historical purchases
at today's rate.
"""

from dataclasses import dataclass, replace
from datetime import date
from typing import Protocol

from .fx import transaction_rate

BUY_TYPES = ('buy', 'deposit')
SELL_TYPES = ('sell', 'withdrawal')
INCOME_TYPES = ('dividend', 'coupon')

# Quantities are compared with a tolerance so that floating-point dust from a
# sequence of fractional trades does not read as an oversell.
QTY_EPSILON = 1e-9


class OversellError(ValueError):
    """A sale would drive the position negative."""


def net_amount_original(transaction_type: str, original_amount: float,
                        fees_original: float) -> float:
    """
    Apply the RFB fee treatment in the transaction's own currency.

    Buys: the fee is part of the acquisition cost, so it is added.
    Sells: the fee comes out of what you receive, so it is deducted.
    Income: fees do not apply — the GROSS amount is returned deliberately.
    The stored `brl_amount` of a dividend/coupon is therefore gross×rate (the
    tax report needs gross plus the withholding separately, for the foreign
    tax credit), while the replay engine computes `income_brl` NET of
    withholding. Presentation layers must show net and label it as such.

    This is the single definition of the rule — both the replay engine and the
    write path that derives `brl_amount` call it, so the stored column and the
    computed position can never disagree about the formula.
    """
    kind = (transaction_type or '').lower()
    amount = float(original_amount or 0)
    fee = float(fees_original or 0)
    if kind in BUY_TYPES:
        return amount + fee
    if kind in SELL_TYPES:
        return amount - fee
    return amount


def effective_quantity(transaction_type: str, quantity, original_amount) -> float:
    """
    Quantity to replay for this transaction.

    Cash deposits and withdrawals carry no share count — the amount *is* the
    quantity. Modelling cash as N units priced at 1.0 puts it on the same
    footing as a security, so ``invested = avg x qty`` holds everywhere and
    foreign-currency cash picks up FX movement like any other foreign asset.

    Gross amount is used, not net: on a withdrawal the fee then shows up as a
    small realized loss, which is what actually happened.
    """
    qty = float(quantity or 0)
    if qty > 0:
        return qty
    if (transaction_type or '').lower() in ('deposit', 'withdrawal'):
        return abs(float(original_amount or 0))
    return qty


def brl_amount_for(transaction_type: str, original_amount: float,
                   fees_original: float, original_currency: str,
                   exchange_rate) -> tuple[float, float]:
    """
    Derive the authoritative BRL figure for one transaction.

    Returns ``(brl_amount, rate)``. Raises MissingRateError when a non-BRL
    transaction carries no usable rate — this feeds tax output, so there is no
    fallback.
    """
    rate = transaction_rate(original_currency, exchange_rate)
    net = net_amount_original(transaction_type, original_amount, fees_original)
    return net * rate, rate


@dataclass(frozen=True)
class Transaction:
    """One ledger row, normalised. Amounts are in `original_currency`."""
    transaction_date: date
    transaction_type: str
    quantity: float = 0.0
    original_amount: float = 0.0
    fees_original: float = 0.0
    withholding_tax_original: float = 0.0
    original_currency: str = 'BRL'
    exchange_rate: float | None = None
    id: str = ''
    created_at: str = ''

    @property
    def sort_key(self) -> tuple:
        """
        Deterministic replay order.

        Sorting by date alone leaves same-day transactions in undefined order,
        and when they carry different FX rates the order changes the answer.
        """
        return (self.transaction_date, self.created_at or '', self.id or '')


@dataclass(frozen=True)
class Position:
    """Immutable state after replaying some prefix of the ledger."""
    quantity: float = 0.0
    avg_orig: float = 0.0
    avg_brl: float = 0.0
    realized_orig: float = 0.0
    realized_brl: float = 0.0
    income_orig: float = 0.0          # dividends + coupons, gross
    income_brl: float = 0.0
    withholding_brl: float = 0.0
    fees_brl_total: float = 0.0       # every fee paid, for the cost report
    fees_orig_total: float = 0.0

    @property
    def invested_orig(self) -> float:
        return self.avg_orig * self.quantity

    @property
    def invested_brl(self) -> float:
        return self.avg_brl * self.quantity


@dataclass(frozen=True)
class AuditStep:
    """
    One replay step. Carries before/after on both averages so every number on
    screen can be traced back to the transaction that produced it.
    """
    transaction_date: date
    transaction_type: str
    transaction_id: str
    quantity_delta: float
    qty_before: float
    qty_after: float
    avg_orig_before: float
    avg_orig_after: float
    avg_brl_before: float
    avg_brl_after: float
    exchange_rate: float
    original_currency: str
    # Populated for buys
    cost_orig: float = 0.0
    cost_brl: float = 0.0
    # Populated for sells
    proceeds_orig: float = 0.0
    proceeds_brl: float = 0.0
    cost_of_sold_orig: float = 0.0
    cost_of_sold_brl: float = 0.0
    realized_orig: float = 0.0
    realized_brl: float = 0.0
    # Populated for dividends / coupons
    income_orig: float = 0.0
    income_brl: float = 0.0
    note: str = ''


class CostBasisMethod(Protocol):
    """
    Strategy interface. Only WeightedAverage is implemented — FIFO is incorrect
    for a Brazilian resident — but the seam exists so a change of residency is a
    new class rather than a rewrite of the engine.
    """
    name: str

    def apply(self, state: Position, tx: Transaction) -> tuple[Position, AuditStep]:
        ...


class WeightedAverage:
    """Custo médio ponderado, the method Receita Federal requires."""

    name = 'weighted_average'

    def apply(self, state: Position, tx: Transaction) -> tuple[Position, AuditStep]:
        rate = transaction_rate(tx.original_currency, tx.exchange_rate)
        kind = (tx.transaction_type or '').lower()

        if kind in BUY_TYPES:
            return self._buy(state, tx, rate)
        if kind in SELL_TYPES:
            return self._sell(state, tx, rate)
        if kind in INCOME_TYPES:
            return self._income(state, tx, rate)
        raise ValueError(f'Unknown transaction_type: {tx.transaction_type!r}')

    # ── buy / deposit ────────────────────────────────────────────────────────

    def _buy(self, s: Position, tx: Transaction, rate: float):
        qty = effective_quantity(
            tx.transaction_type, tx.quantity, tx.original_amount)
        # RFB: fees are part of the acquisition cost, added BEFORE conversion.
        cost_orig = net_amount_original(
            tx.transaction_type, tx.original_amount, tx.fees_original)
        cost_brl = cost_orig * rate

        new_qty = s.quantity + qty
        if new_qty > QTY_EPSILON:
            avg_orig = (s.avg_orig * s.quantity + cost_orig) / new_qty
            avg_brl = (s.avg_brl * s.quantity + cost_brl) / new_qty
        else:
            # Genuinely zero-value, zero-quantity row: nothing to average.
            avg_orig, avg_brl = s.avg_orig, s.avg_brl

        new_state = replace(
            s,
            quantity=new_qty,
            avg_orig=avg_orig,
            avg_brl=avg_brl,
            fees_brl_total=s.fees_brl_total + float(tx.fees_original or 0) * rate,
            fees_orig_total=s.fees_orig_total + float(tx.fees_original or 0),
        )
        step = AuditStep(
            transaction_date=tx.transaction_date,
            transaction_type=tx.transaction_type,
            transaction_id=tx.id,
            quantity_delta=qty,
            qty_before=s.quantity, qty_after=new_qty,
            avg_orig_before=s.avg_orig, avg_orig_after=avg_orig,
            avg_brl_before=s.avg_brl, avg_brl_after=avg_brl,
            exchange_rate=rate, original_currency=tx.original_currency,
            cost_orig=cost_orig, cost_brl=cost_brl,
        )
        return new_state, step

    # ── sell / withdrawal ────────────────────────────────────────────────────

    def _sell(self, s: Position, tx: Transaction, rate: float):
        qty = effective_quantity(
            tx.transaction_type, tx.quantity, tx.original_amount)
        if qty - s.quantity > QTY_EPSILON:
            raise OversellError(
                f'Sale of {qty} exceeds the holding of {s.quantity} on '
                f'{tx.transaction_date}. The ledger is inconsistent; refusing '
                f'to produce a negative position.'
            )

        # Fees reduce the proceeds, mirroring how they raise the cost on a buy.
        proceeds_orig = net_amount_original(
            tx.transaction_type, tx.original_amount, tx.fees_original)
        proceeds_brl = proceeds_orig * rate

        # The average AT THIS INSTANT. Because the replay is chronological and
        # the result is locked in here, a later purchase cannot alter this sale.
        cost_sold_orig = s.avg_orig * qty
        cost_sold_brl = s.avg_brl * qty

        gain_orig = proceeds_orig - cost_sold_orig
        gain_brl = proceeds_brl - cost_sold_brl

        new_qty = max(s.quantity - qty, 0.0)
        new_state = replace(
            s,
            quantity=new_qty,
            # A sale never moves the averages.
            realized_orig=s.realized_orig + gain_orig,
            realized_brl=s.realized_brl + gain_brl,
            fees_brl_total=s.fees_brl_total + float(tx.fees_original or 0) * rate,
            fees_orig_total=s.fees_orig_total + float(tx.fees_original or 0),
        )
        step = AuditStep(
            transaction_date=tx.transaction_date,
            transaction_type=tx.transaction_type,
            transaction_id=tx.id,
            quantity_delta=-qty,
            qty_before=s.quantity, qty_after=new_qty,
            avg_orig_before=s.avg_orig, avg_orig_after=s.avg_orig,
            avg_brl_before=s.avg_brl, avg_brl_after=s.avg_brl,
            exchange_rate=rate, original_currency=tx.original_currency,
            proceeds_orig=proceeds_orig, proceeds_brl=proceeds_brl,
            cost_of_sold_orig=cost_sold_orig, cost_of_sold_brl=cost_sold_brl,
            realized_orig=gain_orig, realized_brl=gain_brl,
        )
        return new_state, step

    # ── dividend / coupon ────────────────────────────────────────────────────

    def _income(self, s: Position, tx: Transaction, rate: float):
        gross_orig = float(tx.original_amount)
        withholding_orig = float(tx.withholding_tax_original or 0)
        net_orig = gross_orig - withholding_orig

        new_state = replace(
            s,
            income_orig=s.income_orig + net_orig,
            income_brl=s.income_brl + net_orig * rate,
            withholding_brl=s.withholding_brl + withholding_orig * rate,
        )
        step = AuditStep(
            transaction_date=tx.transaction_date,
            transaction_type=tx.transaction_type,
            transaction_id=tx.id,
            quantity_delta=0.0,
            qty_before=s.quantity, qty_after=s.quantity,
            avg_orig_before=s.avg_orig, avg_orig_after=s.avg_orig,
            avg_brl_before=s.avg_brl, avg_brl_after=s.avg_brl,
            exchange_rate=rate, original_currency=tx.original_currency,
            income_orig=net_orig, income_brl=net_orig * rate,
            note='income does not affect quantity or cost basis',
        )
        return new_state, step


DEFAULT_METHOD = WeightedAverage()


def replay(transactions, method: CostBasisMethod | None = None):
    """
    Replay a single asset's ledger chronologically.

    Returns ``(Position, [AuditStep])``. The audit trail is always produced —
    it is the same walk that computes the position, so it can never disagree
    with the totals.
    """
    engine = method or DEFAULT_METHOD
    state = Position()
    trail: list[AuditStep] = []

    for tx in sorted(transactions, key=lambda t: t.sort_key):
        state, step = engine.apply(state, tx)
        trail.append(step)

    return state, trail


def from_row(row: dict) -> Transaction:
    """Build a Transaction from a PostgREST row."""
    raw_date = row.get('transaction_date')
    parsed = (
        date.fromisoformat(raw_date[:10]) if isinstance(raw_date, str) else raw_date
    )
    return Transaction(
        transaction_date=parsed,
        transaction_type=row.get('transaction_type', ''),
        quantity=float(row.get('quantity') or 0),
        original_amount=float(row.get('original_amount') or 0),
        fees_original=float(row.get('fees_original') or 0),
        withholding_tax_original=float(row.get('withholding_tax_original') or 0),
        original_currency=row.get('original_currency') or 'BRL',
        exchange_rate=row.get('exchange_rate'),
        id=str(row.get('id') or ''),
        created_at=str(row.get('created_at') or ''),
    )

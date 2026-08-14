"""
Currency conversion.

Rule 4: a missing rate is never silently replaced by a default. There is no code
path in this module that turns an absent rate into a number.

Two distinct situations, deliberately handled differently:

* **Transaction rate** — the rate frozen on the day of a trade, used for tax.
  Absent means the figure cannot be computed at all, so it raises.
* **Live rate** — today's rate, used to value open positions. Absent means that
  one asset cannot be valued; it returns None so the caller can mark it "no
  data" without failing the whole portfolio.
"""

from dataclasses import dataclass
from datetime import date

BRL = 'BRL'
SUPPORTED = ('BRL', 'USD', 'EUR', 'PLN')


def latest_close_on_or_before(closes: dict[date, float],
                              target: date) -> tuple[date, float] | None:
    """
    Pick the close that applies to `target` from a day-keyed series.

    Markets skip weekends and holidays, so a trade dated Sunday uses Friday's
    close — returned together with its own date so the caller can label the
    figure honestly. No close on or before `target` means None, never a guess
    (Rule 4 extends to historical rates).
    """
    eligible = [d for d in closes if d <= target]
    if not eligible:
        return None
    best = max(eligible)
    return best, closes[best]


class MissingRateError(ValueError):
    """Raised when a rate required for a tax figure is absent or unusable."""


def transaction_rate(original_currency: str, exchange_rate) -> float:
    """
    Resolve the exchange rate frozen at transaction time.

    BRL transactions are 1.0 by definition. Anything else must carry an explicit
    positive rate — this feeds tax output, so guessing is not an option.
    """
    currency = (original_currency or BRL).upper()
    if currency == BRL:
        return 1.0
    if exchange_rate is None:
        raise MissingRateError(
            f'Transaction in {currency} has no exchange_rate. The rate on the '
            f'trade date is required to compute the BRL cost basis.'
        )
    rate = float(exchange_rate)
    if rate <= 0:
        raise MissingRateError(
            f'Transaction in {currency} has a non-positive exchange_rate '
            f'({rate}).'
        )
    return rate


@dataclass(frozen=True)
class RateTable:
    """
    Live rates for valuing open positions. Any field may be None, meaning the
    provider did not return it — never that a default was applied.

    `as_of` is a unix timestamp of when the rates were fetched, so callers can
    surface staleness (Rule 6).
    """
    usd_brl: float | None = None
    eur_usd: float | None = None
    usd_pln: float | None = None
    as_of: float | None = None

    def rate_to_brl(self, currency: str) -> float | None:
        """Units of BRL per one unit of `currency`, or None if underivable."""
        c = (currency or BRL).upper()
        if c == BRL:
            return 1.0
        if self.usd_brl is None:
            return None           # every non-BRL path routes through USD/BRL
        if c == 'USD':
            return self.usd_brl
        if c == 'EUR':
            return None if self.eur_usd is None else self.eur_usd * self.usd_brl
        if c == 'PLN':
            if not self.usd_pln:  # None or zero — division would be undefined
                return None
            return self.usd_brl / self.usd_pln
        return None               # unknown currency: unconvertible, not 1:1

    def to_brl(self, value: float, currency: str) -> float | None:
        """Convert `value` into BRL, or None when the rate is unavailable."""
        rate = self.rate_to_brl(currency)
        return None if rate is None else value * rate

    def missing_for(self, currency: str) -> str | None:
        """Human-readable reason a currency cannot be converted, else None."""
        c = (currency or BRL).upper()
        if self.rate_to_brl(c) is not None:
            return None
        if c not in SUPPORTED:
            return f'Unsupported currency {c}'
        if self.usd_brl is None:
            return 'USD/BRL rate unavailable'
        if c == 'EUR':
            return 'EUR/USD rate unavailable'
        if c == 'PLN':
            return 'USD/PLN rate unavailable'
        return f'{c} rate unavailable'

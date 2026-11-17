/// Installment planning: which date each installment gets, and how much.
///
/// Pure on purpose (no Flutter, no network) so the billing-month rule can be
/// unit-tested. It mirrors `get_billing_period()` in the backend's
/// `billing_service.py`; if that rule changes, this one must change with it.
library;

/// Closing day used when a credit card has none of its own. Same default as
/// the backend.
const int defaultClosingDay = 23;

class InstallmentEntry {
  /// 1-based position in the series.
  final int number;
  final DateTime date;
  final double amount;

  const InstallmentEntry({
    required this.number,
    required this.date,
    required this.amount,
  });
}

class InstallmentPlan {
  final List<InstallmentEntry> entries;

  /// First day of the month whose bill carries installment 1.
  final DateTime firstBillMonth;

  const InstallmentPlan({required this.entries, required this.firstBillMonth});
}

/// First day of the month an expense is billed in.
///
/// Cash/Pix: the calendar month. Credit card: a purchase on or after the
/// closing day lands on the next month's bill.
DateTime billingMonth(
  DateTime spentAt, {
  required bool isCreditCard,
  required int closingDay,
}) {
  if (isCreditCard && spentAt.day >= closingDay) {
    return DateTime(spentAt.year, spentAt.month + 1, 1);
  }
  return DateTime(spentAt.year, spentAt.month, 1);
}

/// A date that is unambiguously billed in [billMonth].
///
/// Day 1 sits before every closing day except a closing day of 1 itself — a
/// card that closes on the 1st bills the whole month into the next one, so
/// the date has to sit a month earlier.
DateTime _dateBilledIn(
  DateTime billMonth, {
  required bool isCreditCard,
  required int closingDay,
}) {
  if (isCreditCard && closingDay <= 1) {
    return DateTime(billMonth.year, billMonth.month - 1, 1);
  }
  return DateTime(billMonth.year, billMonth.month, 1);
}

/// Splits [total] into [count] installments on consecutive bills.
///
/// Installment 1 keeps the real purchase date and lands on whatever bill the
/// closing-day rule gives it; installments 2..N are dated so each falls on the
/// following bill, one per month. The earlier version dated installment 2 on
/// the 1st of the calendar month after the purchase — for a purchase on or
/// after the closing day that was the SAME bill as installment 1, so one
/// month carried two installments and the series ended a month early.
///
/// [deferFirst] pushes the whole series one bill later (the shop charges the
/// first installment on the next statement).
///
/// Amounts are computed in cents; the last installment absorbs the rounding
/// remainder so the series always sums to [total].
InstallmentPlan planInstallments({
  required double total,
  required int count,
  required DateTime spentAt,
  required bool isCreditCard,
  int closingDay = defaultClosingDay,
  bool deferFirst = false,
}) {
  assert(count >= 1, 'count must be at least 1');

  final naturalBill = billingMonth(spentAt,
      isCreditCard: isCreditCard, closingDay: closingDay);
  final firstBill = deferFirst
      ? DateTime(naturalBill.year, naturalBill.month + 1, 1)
      : naturalBill;

  final totalCents = (total * 100).round();
  final eachCents = totalCents ~/ count;
  final lastCents = totalCents - eachCents * (count - 1);

  final entries = <InstallmentEntry>[];
  for (var i = 0; i < count; i++) {
    final DateTime date;
    if (i == 0 && !deferFirst) {
      date = spentAt;
    } else {
      date = _dateBilledIn(
        DateTime(firstBill.year, firstBill.month + i, 1),
        isCreditCard: isCreditCard,
        closingDay: closingDay,
      );
    }
    entries.add(InstallmentEntry(
      number: i + 1,
      date: date,
      amount: (i == count - 1 ? lastCents : eachCents) / 100,
    ));
  }
  return InstallmentPlan(entries: entries, firstBillMonth: firstBill);
}

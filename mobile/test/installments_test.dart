import 'package:flutter_test/flutter_test.dart';
import 'package:suas_financas/utils/installments.dart';

/// The bill each entry lands on, by the same rule the backend applies.
List<DateTime> billsOf(InstallmentPlan plan,
        {required bool isCreditCard, required int closingDay}) =>
    plan.entries
        .map((e) => billingMonth(e.date,
            isCreditCard: isCreditCard, closingDay: closingDay))
        .toList();

void main() {
  group('billingMonth', () {
    test('credit card before the closing day stays in the month', () {
      expect(
        billingMonth(DateTime(2026, 1, 22), isCreditCard: true, closingDay: 23),
        DateTime(2026, 1, 1),
      );
    });

    test('credit card on the closing day moves to the next month', () {
      expect(
        billingMonth(DateTime(2026, 1, 23), isCreditCard: true, closingDay: 23),
        DateTime(2026, 2, 1),
      );
    });

    test('December rolls into January of the next year', () {
      expect(
        billingMonth(DateTime(2026, 12, 28),
            isCreditCard: true, closingDay: 23),
        DateTime(2027, 1, 1),
      );
    });

    test('cash never shifts', () {
      expect(
        billingMonth(DateTime(2026, 1, 30),
            isCreditCard: false, closingDay: 23),
        DateTime(2026, 1, 1),
      );
    });
  });

  group('planInstallments', () {
    test('purchase after the closing day: one installment per bill', () {
      // The regression: installment 1 (Jan 25) and installment 2 (Feb 1) both
      // landed on the February bill.
      final plan = planInstallments(
        total: 300,
        count: 3,
        spentAt: DateTime(2026, 1, 25),
        isCreditCard: true,
        closingDay: 23,
      );
      expect(plan.firstBillMonth, DateTime(2026, 2, 1));
      expect(plan.entries.first.date, DateTime(2026, 1, 25));
      expect(
        billsOf(plan, isCreditCard: true, closingDay: 23),
        [DateTime(2026, 2, 1), DateTime(2026, 3, 1), DateTime(2026, 4, 1)],
      );
    });

    test('purchase before the closing day starts on the same month', () {
      final plan = planInstallments(
        total: 300,
        count: 3,
        spentAt: DateTime(2026, 1, 10),
        isCreditCard: true,
        closingDay: 23,
      );
      expect(
        billsOf(plan, isCreditCard: true, closingDay: 23),
        [DateTime(2026, 1, 1), DateTime(2026, 2, 1), DateTime(2026, 3, 1)],
      );
    });

    test('deferFirst pushes the whole series one bill later', () {
      final plan = planInstallments(
        total: 300,
        count: 3,
        spentAt: DateTime(2026, 1, 25),
        isCreditCard: true,
        closingDay: 23,
        deferFirst: true,
      );
      expect(plan.firstBillMonth, DateTime(2026, 3, 1));
      expect(
        billsOf(plan, isCreditCard: true, closingDay: 23),
        [DateTime(2026, 3, 1), DateTime(2026, 4, 1), DateTime(2026, 5, 1)],
      );
    });

    test('cash: purchase date first, then the 1st of each next month', () {
      final plan = planInstallments(
        total: 90,
        count: 3,
        spentAt: DateTime(2026, 11, 28),
        isCreditCard: false,
      );
      expect(plan.entries.map((e) => e.date).toList(),
          [DateTime(2026, 11, 28), DateTime(2026, 12, 1), DateTime(2027, 1, 1)]);
    });

    test('a card closing on the 1st still gets one installment per bill', () {
      final plan = planInstallments(
        total: 300,
        count: 3,
        spentAt: DateTime(2026, 1, 15),
        isCreditCard: true,
        closingDay: 1,
      );
      expect(
        billsOf(plan, isCreditCard: true, closingDay: 1),
        [DateTime(2026, 2, 1), DateTime(2026, 3, 1), DateTime(2026, 4, 1)],
      );
    });

    test('amounts sum to the total; the last one absorbs the remainder', () {
      final plan = planInstallments(
        total: 100,
        count: 3,
        spentAt: DateTime(2026, 1, 10),
        isCreditCard: true,
      );
      expect(plan.entries.map((e) => e.amount).toList(), [33.33, 33.33, 33.34]);
      final cents = plan.entries
          .fold<int>(0, (sum, e) => sum + (e.amount * 100).round());
      expect(cents, 10000);
    });

    test('a single installment is just the expense', () {
      final plan = planInstallments(
        total: 49.9,
        count: 1,
        spentAt: DateTime(2026, 1, 25),
        isCreditCard: true,
      );
      expect(plan.entries, hasLength(1));
      expect(plan.entries.single.amount, 49.9);
      expect(plan.entries.single.date, DateTime(2026, 1, 25));
    });
  });
}

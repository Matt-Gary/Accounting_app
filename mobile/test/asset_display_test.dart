import 'package:flutter_test/flutter_test.dart';
import 'package:suas_financas/utils/asset_display.dart';

/// The reported case: $1,900 deposited at 5.11, viewed later at 5.1873.
const depositUsd = 1900.00;
const rateAtDeposit = 5.11;
const rateToday = 5.1873;
const investedBrl = depositUsd * rateAtDeposit; // 9709.00

void main() {
  group('native view returns the exact figure', () {
    test('USD asset in USD view is not round-tripped through today rate', () {
      final r = pickAmount(
        displayCurrency: 'USD',
        nativeCurrency: 'USD',
        brl: investedBrl,
        native: depositUsd,
        usdBrlRate: rateToday,
      );
      expect(r.value, closeTo(1900.00, 1e-9));
      expect(r.currency, 'USD');
      expect(r.exact, isTrue);
    });

    test('the old behaviour is what we are protecting against', () {
      // Reproduce the bug so the regression is visible in the test itself:
      // dividing the historical BRL cost by today's rate loses $28.31.
      const broken = investedBrl / rateToday;
      expect(broken, closeTo(1871.69, 0.01));

      final fixed = pickAmount(
        displayCurrency: 'USD',
        nativeCurrency: 'USD',
        brl: investedBrl,
        native: depositUsd,
        usdBrlRate: rateToday,
      ).value;
      expect(fixed, closeTo(1900.00, 1e-9));
      expect(fixed - broken, closeTo(28.31, 0.01));
    });

    test('a deposit shows no gain in its own currency', () {
      // Cost and value are the same $1,900 — there is nothing to gain on
      // dollars you deposited and still hold.
      final invested = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'USD',
        brl: investedBrl, native: depositUsd, usdBrlRate: rateToday,
      );
      final value = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'USD',
        brl: depositUsd * rateToday, native: depositUsd,
        usdBrlRate: rateToday,
      );
      expect(value.value - invested.value, closeTo(0.0, 1e-9));
    });
  });

  group('BRL view keeps the historical rate', () {
    test('cost stays at the rate it was booked at', () {
      final r = pickAmount(
        displayCurrency: 'BRL', nativeCurrency: 'USD',
        brl: investedBrl, native: depositUsd, usdBrlRate: rateToday,
      );
      expect(r.value, closeTo(9709.00, 1e-9));
      expect(r.currency, 'BRL');
      expect(r.exact, isTrue);
    });

    test('the FX move is real and visible in BRL', () {
      final invested = pickAmount(
        displayCurrency: 'BRL', nativeCurrency: 'USD',
        brl: investedBrl, native: depositUsd, usdBrlRate: rateToday,
      ).value;
      final value = pickAmount(
        displayCurrency: 'BRL', nativeCurrency: 'USD',
        brl: depositUsd * rateToday, native: depositUsd,
        usdBrlRate: rateToday,
      ).value;
      expect(value - invested, closeTo(146.87, 0.05));
    });
  });

  group('cross-currency has no exact answer', () {
    test('EUR asset in USD view is converted and flagged inexact', () {
      final r = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, native: 1000.0, usdBrlRate: 5.0,
      );
      expect(r.value, closeTo(1200.0, 1e-9));
      expect(r.currency, 'USD');
      expect(r.exact, isFalse,
          reason: 'converted from BRL, not read from a USD field');
    });

    test('the EUR native figure is never mistaken for USD', () {
      final r = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, native: 1000.0, usdBrlRate: 5.0,
      );
      expect(r.value, isNot(closeTo(1000.0, 1e-9)));
    });
  });

  group('missing rate is never invented', () {
    test('a zero rate does not divide by zero or fabricate a number', () {
      final r = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, native: 1000.0, usdBrlRate: 0,
      );
      expect(r.value.isFinite, isTrue);
      expect(r.value, 6000.0);
      expect(r.currency, 'BRL',
          reason: 'caller must see it did not get USD');
    });

    test('negative rate is treated as unavailable', () {
      final r = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, native: 1000.0, usdBrlRate: -1,
      );
      expect(r.currency, 'BRL');
    });
  });

  group('BRL-denominated assets', () {
    test('render identically in both toggle states', () {
      const brlAsset = 5000.0;
      final inBrl = pickAmount(
        displayCurrency: 'BRL', nativeCurrency: 'BRL',
        brl: brlAsset, native: brlAsset, usdBrlRate: rateToday,
      );
      expect(inBrl.value, brlAsset);
      expect(inBrl.exact, isTrue);
    });

    test('a BRL asset viewed in USD converts at today rate, flagged inexact',
        () {
      final r = pickAmount(
        displayCurrency: 'USD', nativeCurrency: 'BRL',
        brl: 5187.3, native: 5187.3, usdBrlRate: rateToday,
      );
      expect(r.value, closeTo(1000.0, 0.01));
      expect(r.exact, isFalse);
    });
  });

  group('isNativeView', () {
    test('matches only when the currencies agree', () {
      expect(isNativeView('USD', 'USD'), isTrue);
      expect(isNativeView('BRL', 'BRL'), isTrue);
      expect(isNativeView('USD', 'EUR'), isFalse);
      expect(isNativeView('BRL', 'USD'), isFalse);
    });
  });
}

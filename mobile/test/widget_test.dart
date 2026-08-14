// This file was the stock Flutter scaffold with its body deleted — comments
// only, no main(). A test file without main() fails to compile, and the
// compiler crash cascaded onto every other test file in the suite, so
// `flutter test` could not run at all. Replaced with real tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:suas_financas/utils/money_format.dart';

void main() {
  group('formatMoney', () {
    test('shows full numbers, never abbreviated', () {
      // 4800 must not render as "4.8K" — an abbreviation hides the digits
      // needed to reconcile against a broker statement.
      expect(formatMoney(4800, 'BRL', 'en'), 'R\$ 4,800.00');
      expect(formatMoney(1234567.89, 'BRL', 'en'), 'R\$ 1,234,567.89');
    });

    test('groups thousands per locale', () {
      expect(formatMoney(4800, 'BRL', 'pt_BR'), 'R\$ 4.800,00');
      expect(formatMoney(4800, 'BRL', 'en'), 'R\$ 4,800.00');
    });

    test('uses the right symbol per currency', () {
      expect(formatMoney(100, 'USD', 'en'), '\$ 100.00');
      expect(formatMoney(100, 'EUR', 'en'), '€ 100.00');
      expect(formatMoney(100, 'PLN', 'en'), 'zł 100.00');
      expect(formatMoney(100, 'BRL', 'en'), 'R\$ 100.00');
    });

    test('an unknown currency falls back to its code, not a wrong symbol', () {
      expect(formatMoney(100, 'JPY', 'en'), 'JPY 100.00');
    });

    test('negatives put the sign before the symbol', () {
      expect(formatMoney(-250.5, 'BRL', 'en'), '-R\$ 250.50');
    });

    test('always two decimals', () {
      expect(formatMoney(5, 'USD', 'en'), '\$ 5.00');
      expect(formatMoney(5.1, 'USD', 'en'), '\$ 5.10');
      expect(formatMoney(0, 'USD', 'en'), '\$ 0.00');
    });
  });

  group('formatQuantity', () {
    test('whole share counts carry no decimals', () {
      expect(formatQuantity(10, 'en'), '10');
      expect(formatQuantity(1900, 'en'), '1,900');
    });

    test('fractional quantities keep their precision', () {
      expect(formatQuantity(0.5, 'en'), '0.5');
      expect(formatQuantity(1.23456, 'en'), '1.23456');
    });

    test('does not pad a fractional quantity to a fixed width', () {
      expect(formatQuantity(2.5, 'en'), '2.5');
    });
  });

  group('currencySymbol', () {
    test('known codes map to symbols', () {
      expect(currencySymbol('BRL'), 'R\$');
      expect(currencySymbol('USD'), '\$');
    });

    test('unknown code returns itself', () {
      expect(currencySymbol('XYZ'), 'XYZ');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:suas_financas/utils/money_format.dart';

void main() {
  group('parseAmount', () {
    test('plain decimals in either convention', () {
      expect(parseAmount('1234.56'), 1234.56);
      expect(parseAmount('1234,56'), 1234.56);
      expect(parseAmount('12,5'), 12.5);
      expect(parseAmount('50'), 50);
    });

    test('grouped amounts: the later separator is the decimal mark', () {
      // "1.234,56" used to become "1.234.56" and throw a FormatException.
      expect(parseAmount('1.234,56'), 1234.56);
      expect(parseAmount('1,234.56'), 1234.56);
    });

    test('a repeated separator can only be grouping', () {
      expect(parseAmount('1.234.567'), 1234567);
      expect(parseAmount('1,234,567'), 1234567);
    });

    test('whitespace is ignored', () {
      expect(parseAmount(' 1 234,56 '), 1234.56);
    });

    test('not a number is null, never zero', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('12,3,4.5.6'), isNull);
    });
  });
}

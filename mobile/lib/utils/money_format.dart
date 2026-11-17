import 'package:easy_localization/easy_localization.dart';

const _symbols = {
  'BRL': 'R\$',
  'USD': '\$',
  'EUR': '€',
  'PLN': 'zł',
};

String currencySymbol(String code) => _symbols[code] ?? code;

/// Currency of the expense/earning side of the app. There is no per-family
/// currency setting yet; keeping the code in one place means adding one later
/// is a change here, not a hunt for 'R$' literals across the screens.
const String expenseCurrency = 'BRL';

/// Parses an amount typed in either convention: "1234.56", "1234,56",
/// "1.234,56", "1,234.56". Returns null when it is not a number.
///
/// When both separators appear, the later one is the decimal mark. A lone
/// separator is read as the decimal mark ("12,5" and "12.5" are both 12.5);
/// a repeated one can only be grouping ("1.234.567").
double? parseAmount(String input) {
  var s = input.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;

  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    s = lastComma > lastDot
        ? s.replaceAll('.', '').replaceAll(',', '.')
        : s.replaceAll(',', '');
  } else if (lastComma >= 0) {
    s = ','.allMatches(s).length == 1
        ? s.replaceAll(',', '.')
        : s.replaceAll(',', '');
  } else if ('.'.allMatches(s).length > 1) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

/// Form validator for a money field: required, a number, greater than zero.
String? validateAmount(String? value) {
  if (value == null || value.trim().isEmpty) return 'common.required'.tr();
  final parsed = parseAmount(value);
  if (parsed == null || parsed <= 0) return 'common.invalid_amount'.tr();
  return null;
}

/// Money, in full, with locale-aware thousands separators.
///
/// Deliberately no K/M abbreviation: "R$ 4,8K" hides the digits you need when
/// reconciling a position against a broker statement, and rounds away up to
/// R$99 in the process.
String formatMoney(double value, String currencyCode, String locale) {
  final sign = value < 0 ? '-' : '';
  final digits = NumberFormat('#,##0.00', locale).format(value.abs());
  return '$sign${currencySymbol(currencyCode)} $digits';
}

/// Share counts: no forced decimals on whole units, up to 6 places for
/// fractional ones (crypto, fractional shares).
String formatQuantity(double value, String locale) {
  final pattern = value == value.roundToDouble() ? '#,##0' : '#,##0.######';
  return NumberFormat(pattern, locale).format(value);
}

/// A per-unit price. Same grouping as money so a five-figure crypto quote stays
/// readable, but without forcing a currency symbol on the caller.
String formatPrice(double value, String currencyCode, String locale) =>
    formatMoney(value, currencyCode, locale);

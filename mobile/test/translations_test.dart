// Guards the project rule that every user-facing string is an i18n key present
// in BOTH locales. The failure this prevents is silent: a key added to en.json
// only renders in pt-BR as its own dotted path ("investments.performance.
// days_left") — valid Dart, valid JSON, visible nonsense on the screen.
//
// It also compares {placeholders}, because a translation that drops one shows
// a literal "{days}" to the user instead of the number.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _flatten(Map<String, dynamic> node, [String prefix = '']) {
  final out = <String, String>{};
  node.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = '$value';
    }
  });
  return out;
}

Map<String, String> _load(String path) => _flatten(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final en = _load('assets/translations/en.json');
  final ptBr = _load('assets/translations/pt-BR.json');

  test('every English key exists in pt-BR', () {
    expect(en.keys.toSet().difference(ptBr.keys.toSet()), isEmpty);
  });

  test('every pt-BR key exists in English', () {
    expect(ptBr.keys.toSet().difference(en.keys.toSet()), isEmpty);
  });

  test('a key carries the same placeholders in both locales', () {
    final mismatched = [
      for (final key in en.keys)
        if (ptBr.containsKey(key) &&
            !setEquals(_placeholders(en[key]!), _placeholders(ptBr[key]!)))
          key
    ];
    expect(mismatched, isEmpty);
  });

  test('the performance countdown key takes a day count', () {
    // The tile substitutes the backend's remaining-days figure into this key;
    // a translation without {days} would render a sentence with no number.
    for (final locale in [en, ptBr]) {
      expect(locale['investments.performance.days_left'], isNotNull);
      expect(_placeholders(locale['investments.performance.days_left']!),
          {'days'});
    }
  });

  test('the chart titles name the display currency', () {
    for (final locale in [en, ptBr]) {
      expect(_placeholders(locale['investments.performance.title']!),
          {'currency'});
      expect(
          _placeholders(locale['investments.equity.title']!), {'currency'});
    }
  });
}

bool setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

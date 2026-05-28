import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final isEn = context.locale.languageCode == 'en';
    return TextButton(
      onPressed: () => context.setLocale(
        isEn ? const Locale('pt', 'BR') : const Locale('en'),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ??
            Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(40, 36),
      ),
      child: Text(
        isEn ? 'PT' : 'EN',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

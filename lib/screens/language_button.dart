import 'package:flutter/material.dart';

import '../l10n.dart';

/// زر تبديل اللغة (عربي ⇄ English): يُستخدم في شاشتي الترحيب وتسجيل الدخول.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => AppLang.code.value = AppLang.isEn ? 'ar' : 'en',
      icon: const Icon(Icons.language_rounded, size: 18),
      label: Text(AppLang.isEn ? 'العربية' : 'English'),
    );
  }
}

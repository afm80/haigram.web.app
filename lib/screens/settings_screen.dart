import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_service.dart';
import '../theme.dart';
import '../route_state.dart';

/// صفحة الإعدادات: المظهر وتسجيل الخروج.
/// لاحقاً: الخصوصية وحذف الحساب.
class SettingsScreen extends StatelessWidget {
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const SettingsScreen({super.key, required this.onThemeModeChanged});

  Future<void> _setDark(BuildContext context, bool dark) async {
    try {
      await onThemeModeChanged(dark ? ThemeMode.dark : ThemeMode.light);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // نغلق صفحة الإعدادات أولاً حتى لا تبقى فوق شاشة تسجيل الدخول.
    Navigator.of(context).pop();
    try {
      await FirebaseAuth.instance.signOut();
      UserService.me = null;
      RouteStore.clear();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تسجيل الخروج: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الإعدادات',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SectionLabel('المظهر'),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SwitchListTile(
                secondary: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                ),
                title: const Text('الوضع الداكن'),
                subtitle: Text(
                  isDark ? 'المظهر الحالي: داكن' : 'المظهر الحالي: فاتح',
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
                value: isDark,
                activeColor: AppColors.brandRed,
                onChanged: (value) => _setDark(context, value),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('الحساب'),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: AppColors.brandRed),
                title: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: AppColors.brandRed),
                ),
                onTap: () => _confirmSignOut(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.appColors.textDim,
        ),
      ),
    );
  }
}

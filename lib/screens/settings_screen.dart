import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import '../route_state.dart';

/// صفحة الإعدادات: المظهر والخصوصية وتسجيل الخروج.
/// لاحقاً: حذف الحساب.
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
            const _SectionLabel('الخصوصية'),
            const _PrivacySection(),
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


/// إعدادات الخصوصية: حساب خاص + إخفاء تبويب الإعجابات عن الآخرين.
class _PrivacySection extends StatefulWidget {
  const _PrivacySection();

  @override
  State<_PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<_PrivacySection> {
  late final Stream<AppUser?> _profile = UserService.profileStream(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  );

  Future<void> _update(
      {bool? isPrivate, bool? hideLikes, bool? profileVisits}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await UserService.updatePrivacy(
          isPrivate: isPrivate,
          hideLikes: hideLikes,
          profileVisits: profileVisits);
      if (isPrivate == false) {
        // الحساب أصبح عاماً: تُقبل الطلبات المعلّقة تلقائياً.
        await PostService.approveAllFollowRequests();
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر حفظ الإعداد: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return StreamBuilder<AppUser?>(
      stream: _profile,
      builder: (context, snapshot) {
        final user = snapshot.data ?? UserService.me;
        final enabled = user != null;
        TextStyle dim() => TextStyle(color: colors.textDim, fontSize: 12);
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: const Text('حساب خاص'),
                subtitle: Text(
                  'منشوراتك ومقاطعك تظهر لمتابعيك فقط، ومن يريد متابعتك يرسل طلباً تقبله أنت',
                  style: dim(),
                ),
                value: user?.isPrivate ?? false,
                activeColor: AppColors.brandRed,
                onChanged:
                    enabled ? (value) => _update(isPrivate: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              SwitchListTile(
                secondary: const Icon(Icons.favorite_border_rounded),
                title: const Text('إخفاء الإعجابات'),
                subtitle: Text(
                  'لا يرى الآخرون تبويب الإعجابات في ملفك',
                  style: dim(),
                ),
                value: user?.hideLikes ?? false,
                activeColor: AppColors.brandRed,
                onChanged:
                    enabled ? (value) => _update(hideLikes: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('زيارات الملف الشخصي'),
                subtitle: Text(
                  'تعرف من زار ملفك خلال 30 يوماً، ويرى الآخرون زياراتك لهم. تعمل عندما يفعّلها الطرفان',
                  style: dim(),
                ),
                value: user?.profileVisits ?? true,
                activeColor: AppColors.brandRed,
                onChanged:
                    enabled ? (value) => _update(profileVisits: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              ListTile(
                leading: const Icon(Icons.bookmark_border_rounded),
                title: const Text('المحفوظات'),
                subtitle: Text('خاصة بك دائماً ولا يراها أحد', style: dim()),
              ),
            ],
          ),
        );
      },
    );
  }
}

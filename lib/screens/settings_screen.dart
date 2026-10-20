import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import '../route_state.dart';
import 'profile_screen.dart' show SavedPostsScreen;
import 'social_screens.dart' show ProfileVisitsScreen, BlockedUsersScreen;

/// صفحة الإعدادات: المظهر والخصوصية وتسجيل الخروج.
class SettingsScreen extends StatelessWidget {
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const SettingsScreen({super.key, required this.onThemeModeChanged});

  Future<void> _setDark(BuildContext context, bool dark) async {
    try {
      await onThemeModeChanged(dark ? ThemeMode.dark : ThemeMode.light);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error))),
        );
      }
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('تسجيل الخروج؟')),
        content: Text(tr('هل تريد تسجيل الخروج من حسابك؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr('تسجيل الخروج')),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // نغلق صفحة الإعدادات أولاً حتى لا تبقى فوق شاشة تسجيل الدخول.
    Navigator.of(context).pop();
    try {
      if (!kIsWeb) {
        try {
          await GoogleSignIn().signOut();
        } catch (_) {}
      }
      await SocialService.unregisterPushNotifications();
      await FirebaseAuth.instance.signOut();
      UserService.me = null;
      RouteStore.clear();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(friendlyError(error,
                fallback: tr('تعذر تسجيل الخروج')))),
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('حذف الحساب؟')),
        content: Text(tr(
            'سيتم حذف حسابك وكل منشوراتك وقصصك وتعليقاتك ومحادثاتك نهائياً، ولا يمكن التراجع عن ذلك.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr('حذف الحساب')),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // نافذة انتظار لا تُغلق باللمس حتى ينتهي الحذف.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );

    var deleted = false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('not signed in');
      final token = await user.getIdToken(true);
      const projectId = String.fromEnvironment('FB_PROJECT_ID');
      final response = await http.post(
        Uri.parse(
            'https://us-central1-$projectId.cloudfunctions.net/deleteMyAccount'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': {}}),
      );
      if (response.statusCode != 200) {
        String message = tr('تعذر حذف الحساب');
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          final serverMessage = body['error']?['message'];
          if (serverMessage is String && serverMessage.isNotEmpty) {
            message = serverMessage;
          }
        } catch (_) {}
        throw Exception(message);
      }
      deleted = true;
    } catch (error) {
      navigator.pop(); // يغلق نافذة الانتظار
      final text = error.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(text.isEmpty ? tr('تعذر حذف الحساب') : text)),
      );
      return;
    }

    if (deleted) {
      navigator.pop(); // يغلق نافذة الانتظار
      navigator.pop(); // يغلق صفحة الإعدادات
      try {
        if (!kIsWeb) {
          try {
            await GoogleSignIn().signOut();
          } catch (_) {}
        }
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      UserService.me = null;
      RouteStore.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('الإعدادات'),
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
                title: Text(tr('الوضع الداكن')),
                subtitle: Text(
                  isDark
                      ? tr('المظهر الحالي: داكن')
                      : tr('المظهر الحالي: فاتح'),
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
                value: isDark,
                activeColor: Colors.red,
                onChanged: (value) => _setDark(context, value),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('اللغة'),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (final lang in const [
                    ['ar', 'العربية'],
                    ['en', 'English'],
                  ])
                    ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: Text(lang[1]),
                      trailing: AppLang.code.value == lang[0]
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.brandPurple)
                          : null,
                      onTap: () => AppLang.code.value = lang[0],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                ],
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
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: colors.text),
                    title: Text(
                      tr('تسجيل الخروج'),
                      style: TextStyle(color: colors.text),
                    ),
                    onTap: () => _confirmSignOut(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  Divider(height: 1, color: colors.text.withOpacity(0.08)),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded,
                        color: Colors.red),
                    title: Text(
                      tr('حذف الحساب'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: () => _confirmDeleteAccount(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],
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
        tr(text),
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
      if (isPrivate != null) {
        // يزامن حقل الخصوصية على منشوراتي وقصصي (تعتمد عليه قواعد Firestore).
        await PostService.syncAuthorPrivacy(isPrivate);
      }
      if (isPrivate == false) {
        // الحساب أصبح عاماً: تُقبل الطلبات المعلّقة تلقائياً.
        await PostService.approveAllFollowRequests();
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(friendlyError(error,
                fallback: tr('تعذر حفظ الإعداد')))),
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
                title: Text(tr('حساب خاص')),
                subtitle: Text(
                  tr('منشوراتك ومقاطعك تظهر لمتابعيك فقط، ومن يريد متابعتك يرسل طلباً تقبله أنت'),
                  style: dim(),
                ),
                value: user?.isPrivate ?? false,
                activeColor: Colors.red,
                onChanged:
                    enabled ? (value) => _update(isPrivate: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              SwitchListTile(
                secondary: const Icon(Icons.favorite_border_rounded),
                title: Text(tr('إخفاء الإعجابات')),
                subtitle: Text(
                  tr('لا يرى الآخرون تبويب الإعجابات في ملفك'),
                  style: dim(),
                ),
                value: user?.hideLikes ?? false,
                activeColor: Colors.red,
                onChanged:
                    enabled ? (value) => _update(hideLikes: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: Text(tr('زيارات الملف الشخصي')),
                subtitle: Text(
                  tr('تعرف من زار ملفك خلال 30 يوماً، ويرى الآخرون زياراتك لهم. تعمل عندما يفعّلها الطرفان'),
                  style: dim(),
                ),
                value: user?.profileVisits ?? true,
                activeColor: Colors.red,
                onChanged:
                    enabled ? (value) => _update(profileVisits: value) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              ListTile(
                leading: const Icon(Icons.people_outline_rounded),
                title: Text(tr('من زار ملفي')),
                subtitle: Text(
                    tr('قائمة من زاروا ملفك الشخصي خلال آخر 30 يوماً'),
                    style: dim()),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.of(context).push(appRoute<void>(
                    'profileVisits',
                    const {},
                    (_) => const ProfileVisitsScreen())),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text(tr('قائمة الحظر')),
                subtitle: Text(
                    tr('الحسابات التي حظرتها، ومنها يمكنك إلغاء الحظر'),
                    style: dim()),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.of(context).push(appRoute<void>(
                    'blockedUsers',
                    const {},
                    (_) => const BlockedUsersScreen())),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.08)),
              ListTile(
                leading: const Icon(Icons.bookmark_border_rounded),
                title: Text(tr('المحفوظات')),
                subtitle: Text(
                    tr('المنشورات التي حفظتها بزر العلامة 🔖 تجدها هنا. خاصة بك دائماً ولا يراها أحد'),
                    style: dim()),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.of(context).push(appRoute<void>(
                    'savedPosts', const {}, (_) => const SavedPostsScreen())),
              ),
            ],
          ),
        );
      },
    );
  }
}

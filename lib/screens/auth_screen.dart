import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_service.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  bool _register = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e.code));
    } catch (e) {
      setState(() => _error = 'حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(String code) {
    switch (code) {
      case 'invalid-email':
        return 'البريد الإلكتروني غير صحيح';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'البريد أو كلمة المرور غير صحيحة';
      case 'email-already-in-use':
        return 'هذا البريد مستخدم مسبقاً';
      case 'weak-password':
        return 'كلمة المرور ضعيفة (6 أحرف على الأقل)';
      case 'popup-closed-by-user':
        return 'تم إغلاق نافذة تسجيل الدخول';
      default:
        return 'تعذر تسجيل الدخول ($code)';
    }
  }

  Future<void> _emailAuth() => _run(() async {
        final auth = FirebaseAuth.instance;
        if (_register) {
          final username = UserService.normalize(_username.text);
          final err = UserService.validate(username);
          if (err != null) {
            setState(() => _error = err);
            return;
          }
          if (!await UserService.isAvailable(username)) {
            setState(() => _error = 'اسم المستخدم محجوز، اختر اسماً آخر');
            return;
          }
          UserService.pendingUsername = username;
          final cred = await auth.createUserWithEmailAndPassword(
              email: _email.text.trim(), password: _pass.text);
          final name = _name.text.trim();
          await cred.user?.updateDisplayName(name.isNotEmpty ? name : username);
          // يُنشأ ملف المستخدم باسمه المختار (وإن حُجز في الأثناء يُولَّد اسم بديل ويمكن تعديله لاحقاً).
          await UserService.ensureProfile(preferredUsername: username);
        } else {
          await auth.signInWithEmailAndPassword(
              email: _email.text.trim(), password: _pass.text);
        }
      });

  Future<void> _google() => _run(() async {
        // على الويب يعمل popup مباشرة عبر Firebase Auth دون إعداد إضافي.
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      });

  @override
  Widget build(BuildContext context) {
    final currentTheme = Theme.of(context);
    final controlColor = currentTheme.brightness == Brightness.dark
        ? Colors.white
        : AppPalette.light.text;
    final authTheme = currentTheme.copyWith(
      colorScheme: currentTheme.colorScheme.copyWith(primary: controlColor),
      inputDecorationTheme: currentTheme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: controlColor, width: 1.2),
        ),
      ),
    );

    return Theme(
      data: authTheme,
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
                      decoration: BoxDecoration(
                        color: context.appColors.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                            color: context.appColors.text.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                              color: context.appColors.shadow,
                              blurRadius: 36,
                              offset: Offset(0, 18)),
                        ],
                      ),
                      child: Column(
                        children: [
                          const LamhaLogo(size: 76, monochrome: true),
                          const SizedBox(height: 16),
                          const Text('Haigram',
                              style: TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 28),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: Column(
                              children: [
                                if (_register) ...[
                                  TextField(
                                    controller: _name,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                        hintText: 'الاسم',
                                        prefixIcon:
                                            Icon(Icons.person_outline_rounded)),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _username,
                                    textDirection: TextDirection.ltr,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                        hintText: 'اسم المستخدم',
                                        prefixText: '@',
                                        prefixIcon: Icon(
                                            Icons.alternate_email_rounded)),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                      hintText: 'البريد الإلكتروني',
                                      prefixIcon:
                                          Icon(Icons.mail_outline_rounded)),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _pass,
                                  obscureText: _obscurePassword,
                                  autofillHints: _register
                                      ? const [AutofillHints.newPassword]
                                      : const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    hintText: 'كلمة المرور',
                                    prefixIcon:
                                        const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'إظهار كلمة المرور'
                                          : 'إخفاء كلمة المرور',
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                      icon: Icon(_obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                    ),
                                  ),
                                  onSubmitted: (_) => _emailAuth(),
                                ),
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: AppColors.accent2.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14)),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppColors.accent2, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(_error!,
                                          style: const TextStyle(
                                              color: AppColors.accent2))),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy ? null : _emailAuth,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1C1B22),
                              side: BorderSide(
                                  color: context.appColors.textDim
                                      .withOpacity(0.25)),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Text(
                                      _register ? 'إنشاء حساب' : 'تسجيل الدخول',
                                      key: ValueKey(_register),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _google,
                            icon: const Icon(Icons.g_mobiledata, size: 32),
                            label: const Text('المتابعة بحساب Google'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1C1B22),
                              side: const BorderSide(color: Color(0xFFD5D3DB)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _register = !_register),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                _register
                                    ? 'لديك حساب؟ سجّل الدخول'
                                    : 'ليس لديك حساب؟ أنشئ حساباً',
                                key: ValueKey('register-$_register'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

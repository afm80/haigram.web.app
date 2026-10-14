import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
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
  bool _rememberMe = true;
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
      debugPrint('Auth error: $e');
      setState(() => _error = 'تعذر تسجيل الدخول: $e');
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
      case 'account-exists-with-different-credential':
        return 'هذا البريد مسجّل بطريقة دخول أخرى';
      case 'network-request-failed':
        return 'تحقق من اتصال الإنترنت';
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
          if (kIsWeb) {
            await auth.setPersistence(
                _rememberMe ? Persistence.LOCAL : Persistence.SESSION);
          }
          await auth.signInWithEmailAndPassword(
              email: _email.text.trim(), password: _pass.text);
        }
      });

  Future<void> _google() => _run(() async {
        final auth = FirebaseAuth.instance;
        if (kIsWeb) {
          // على الويب يعمل popup مباشرة عبر Firebase Auth.
          await auth.setPersistence(
              _rememberMe ? Persistence.LOCAL : Persistence.SESSION);
          await auth.signInWithPopup(GoogleAuthProvider());
          return;
        }
        // على أندرويد: نافذة اختيار حساب Google الأصلية ثم تبادل الرمز مع Firebase.
        final googleSignIn = GoogleSignIn(
          scopes: const ['email'],
          serverClientId: DefaultFirebaseOptions.googleServerClientId.isEmpty
              ? null
              : DefaultFirebaseOptions.googleServerClientId,
        );
        // نخرج من الجلسة السابقة ليظهر اختيار الحساب في كل مرة.
        await googleSignIn.signOut();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) return; // ألغى المستخدم العملية
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await auth.signInWithCredential(credential);
      });

  @override
  Widget build(BuildContext context) {
    final currentTheme = Theme.of(context);
    final controlColor = context.appColors.text;
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
                          const LamhaLogo(size: 76),
                          const SizedBox(height: 16),
                          const HaigramWordmark(
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
                          if (!_register && kIsWeb) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: AppColors.accent,
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(
                                          () => _rememberMe = value ?? false),
                                ),
                                GestureDetector(
                                  onTap: _busy
                                      ? null
                                      : () => setState(
                                          () => _rememberMe = !_rememberMe),
                                  child: const Text('تذكرني على هذا الجهاز'),
                                ),
                              ],
                            ),
                          ],
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
                                  Expanded(child: Text(_error!)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy ? null : _emailAuth,
                            style: FilledButton.styleFrom(
                              backgroundColor: context.appColors.surfaceHigh,
                              foregroundColor: context.appColors.text,
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
                              backgroundColor: context.appColors.surfaceHigh,
                              foregroundColor: context.appColors.text,
                              side: BorderSide(
                                  color: context.appColors.textDim
                                      .withOpacity(0.25)),
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

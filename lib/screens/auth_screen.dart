import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../l10n.dart';
import '../net_error.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'language_button.dart';

class AuthScreen extends StatefulWidget {
  /// عند فتحها فوق التصفح (زائر ضغط على تفاعل): يظهر زر إغلاق ✕،
  /// وتُغلق تلقائياً بعد نجاح تسجيل الدخول.
  final bool closable;
  const AuthScreen({super.key, this.closable = false});

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
  String? _info;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    if (widget.closable) {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
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
      _info = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _msg(e.code));
    } catch (e) {
      debugPrint('Auth error: $e');
      if (mounted) {
        // نُلحق رمز الخطأ التقني لتسهيل معرفة السبب (مثل sign_in_failed أو ApiException: 10).
        final detail = e is PlatformException
            ? '${e.code}: ${e.message ?? ''}'
            : e.runtimeType.toString();
        setState(() => _error = isOfflineError(e)
            ? tr('لا يوجد اتصال بالإنترنت')
            : '${tr('تعذر تسجيل الدخول')} ($detail)');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(String code) {
    switch (code) {
      case 'invalid-email':
        return tr('البريد الإلكتروني غير صحيح');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return tr('البريد أو كلمة المرور غير صحيحة');
      case 'email-already-in-use':
        return tr('هذا البريد مستخدم مسبقاً');
      case 'weak-password':
        return tr('كلمة المرور ضعيفة (6 أحرف على الأقل)');
      case 'popup-closed-by-user':
        return tr('تم إغلاق نافذة تسجيل الدخول');
      case 'account-exists-with-different-credential':
        return tr('هذا البريد مسجّل بطريقة دخول أخرى');
      case 'network-request-failed':
        return tr('لا يوجد اتصال بالإنترنت');
      case 'too-many-requests':
        return tr('محاولات كثيرة، حاول مرة أخرى بعد قليل');
      case 'missing-email':
        return tr('اكتب بريدك الإلكتروني أولاً');
      default:
        return '${tr('تعذر تسجيل الدخول')} ($code)';
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
            if (!mounted) return;
            setState(() => _error = tr('اسم المستخدم محجوز، اختر اسماً آخر'));
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

  /// إرسال رابط إعادة تعيين كلمة المرور إلى البريد.
  Future<void> _forgotPassword() => _run(() async {
        final email = _email.text.trim();
        if (email.isEmpty) {
          setState(() =>
              _error = tr('اكتب بريدك الإلكتروني أولاً ثم اضغط «نسيت كلمة المرور»'));
          return;
        }
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          setState(() => _error = tr('البريد الإلكتروني غير صحيح'));
          return;
        }
        final auth = FirebaseAuth.instance;
        await auth.setLanguageCode(AppLang.isEn ? 'en' : 'ar'); // لغة رسالة البريد
        try {
          await auth.sendPasswordResetEmail(email: email);
        } on FirebaseAuthException catch (e) {
          // لا نكشف هل البريد مسجّل أم لا.
          if (e.code != 'user-not-found') rethrow;
        }
        if (!mounted) return;
        setState(() => _info =
            tr('إن كان هذا البريد مسجّلاً لدينا فقد أرسلنا إليه رابط إعادة تعيين كلمة المرور. تحقق من صندوق الوارد ومن البريد غير الهام (Spam).'));
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
                          const HaigramLogo(size: 76),
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
                                    decoration: InputDecoration(
                                        hintText: tr('الاسم'),
                                        prefixIcon: const Icon(
                                            Icons.person_outline_rounded)),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _username,
                                    textDirection: TextDirection.ltr,
                                    autocorrect: false,
                                    decoration: InputDecoration(
                                        hintText: tr('اسم المستخدم'),
                                        prefixText: '@',
                                        prefixIcon: const Icon(
                                            Icons.alternate_email_rounded)),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: InputDecoration(
                                      hintText: tr('البريد الإلكتروني'),
                                      prefixIcon: const Icon(
                                          Icons.mail_outline_rounded)),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _pass,
                                  obscureText: _obscurePassword,
                                  autofillHints: _register
                                      ? const [AutofillHints.newPassword]
                                      : const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    hintText: tr('كلمة المرور'),
                                    prefixIcon:
                                        const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? tr('إظهار كلمة المرور')
                                          : tr('إخفاء كلمة المرور'),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                      icon: Icon(_obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                    ),
                                  ),
                                  onSubmitted: (_) => _emailAuth(),
                                ),
                                if (!_register)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      onPressed: _busy ? null : _forgotPassword,
                                      child: Text(tr('نسيت كلمة المرور؟')),
                                    ),
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
                                  child: Text(tr('تذكرني على هذا الجهاز')),
                                ),
                              ],
                            ),
                          ],
                          if (_info != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF31C75A)
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14)),
                              child: Row(
                                children: [
                                  const Icon(Icons.mark_email_read_outlined,
                                      color: Color(0xFF31C75A), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_info!)),
                                ],
                              ),
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
                                      _register
                                          ? tr('إنشاء حساب')
                                          : tr('تسجيل الدخول'),
                                      key: ValueKey(_register),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _google,
                            icon: const Icon(Icons.g_mobiledata, size: 32),
                            label: Text(tr('المتابعة بحساب Google')),
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
                                    ? tr('لديك حساب؟ سجّل الدخول')
                                    : tr('ليس لديك حساب؟ أنشئ حساباً'),
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
            const PositionedDirectional(
              top: 0,
              end: 0,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: LanguageButton(),
                ),
              ),
            ),
            if (widget.closable)
              PositionedDirectional(
                top: 0,
                start: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      tooltip: tr('إغلاق'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  bool _register = false;
  bool _busy = false;
  String? _error;

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
          final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
          final name = _name.text.trim();
          if (name.isNotEmpty) await cred.user?.updateDisplayName(name);
        } else {
          await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
        }
      });

  Future<void> _google() => _run(() async {
        // على الويب يعمل popup مباشرة عبر Firebase Auth دون إعداد إضافي.
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const LamhaLogo(size: 84),
                  const SizedBox(height: 16),
                  const Text('لمحة', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('شاهد، شارك، ولمّع', style: TextStyle(color: AppColors.textDim)),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextField(controller: _name, decoration: const InputDecoration(hintText: 'اسم المستخدم')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'البريد الإلكتروني'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'كلمة المرور'),
                    onSubmitted: (_) => _emailAuth(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.accent2)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _emailAuth,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'إنشاء حساب' : 'تسجيل الدخول'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.g_mobiledata, size: 32),
                    label: const Text('المتابعة بحساب Google'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(_register ? 'لديك حساب؟ سجّل الدخول' : 'ليس لديك حساب؟ أنشئ حساباً'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

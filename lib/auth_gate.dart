import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';

/// هل المستخدم مسجّل دخوله؟
bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;

/// يُستدعى قبل أي تفاعل (إعجاب، تعليق، متابعة، حفظ...).
/// إن كان الزائر غير مسجّل: يفتح صفحة الدخول فوق الصفحة الحالية ويرجع true
/// (أي: أوقف التنفيذ). وإن كان مسجّلاً يرجع false فيُكمل الفعل.
///
///   if (needsLogin(context)) return;
bool needsLogin(BuildContext context) {
  if (isLoggedIn) return false;
  Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const AuthScreen(closable: true),
    ),
  );
  return true;
}

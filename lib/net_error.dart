import 'dart:async' show TimeoutException;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'theme.dart';

/// هل سبب الخطأ انقطاع الإنترنت أو ضعف الاتصال؟
/// (Firestore: unavailable / client is offline، Auth: network-request-failed، أخطاء الشبكة العامة)
bool isOfflineError(Object? error) {
  if (error == null) return false;
  if (error is TimeoutException) return true;
  if (error is FirebaseException) {
    const codes = {'unavailable', 'network-request-failed', 'deadline-exceeded'};
    if (codes.contains(error.code)) return true;
  }
  final text = error.toString().toLowerCase();
  const hints = [
    'client is offline',
    'cloud_firestore/unavailable',
    'network-request-failed',
    'network error',
    'socketexception',
    'failed host lookup',
    'xmlhttprequest error',
    'failed to fetch',
    'clientexception',
    'connection closed',
    'connection refused',
    'connection reset',
    'err_internet_disconnected',
  ];
  return hints.any(text.contains);
}

/// نص قصير ومفهوم يُعرض في الإشعارات السفلية بدل الخطأ التقني.
/// عند انقطاع الإنترنت تظهر رسالة الاتصال، وإلا يُعرض [fallback].
String friendlyError(Object? error, {String? fallback}) {
  if (isOfflineError(error)) return tr('لا يوجد اتصال بالإنترنت');
  if (error is StateError) return error.message;
  return fallback ?? tr('حدث خطأ غير متوقع، حاول مرة أخرى');
}

/// حالة خطأ جاهزة داخل الصفحات: لا تُظهر أي نص تقني للمستخدم.
/// - انقطاع الإنترنت: أيقونة وشرح ودعوة للتحقق من الشبكة.
/// - غير ذلك: [title] مع رسالة عامة.
/// زر «إعادة المحاولة» يظهر فقط إذا مُرّرت [onRetry].
class ErrorState extends StatelessWidget {
  final Object? error;
  final String? title;
  final VoidCallback? onRetry;

  const ErrorState({super.key, this.error, this.title, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final offline = isOfflineError(error);
    return EmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline
          ? tr('لا يوجد اتصال بالإنترنت')
          : (title ?? tr('حدث خطأ غير متوقع')),
      message: offline
          ? tr('تحقق من اتصالك بالشبكة ثم حاول مرة أخرى.')
          : tr('حاول مرة أخرى بعد قليل.'),
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(tr('إعادة المحاولة')),
            ),
    );
  }
}

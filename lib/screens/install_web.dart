// تثبيت التطبيق (PWA) على الويب: يتواصل مع الدوال المعرّفة في web/index.html.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';

String _read() {
  try {
    final r = js_util.callMethod<Object?>(html.window, 'haigramInstallState', []);
    return r is String ? r : 'none';
  } catch (_) {
    return 'none';
  }
}

final ValueNotifier<String> _state = () {
  final n = ValueNotifier<String>(_read());
  html.window.addEventListener('haigram-install-state', (_) {
    n.value = _read();
  });
  return n;
}();

/// 'standalone' | 'prompt' | 'ios' | 'none'
ValueListenable<String> get installState => _state;

/// يفتح نافذة التثبيت الرسمية (أندرويد/كروم). يرجع true عند القبول.
Future<bool> promptInstall() async {
  try {
    final Object promise =
        js_util.callMethod<Object>(html.window, 'haigramInstall', []);
    final r = await js_util.promiseToFuture<Object?>(promise);
    return r == true;
  } catch (_) {
    return false;
  }
}

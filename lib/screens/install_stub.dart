// تثبيت التطبيق (PWA): نسخة أندرويد/آيفون الأصلية — لا حاجة للتثبيت.
import 'package:flutter/foundation.dart';

/// 'standalone' | 'prompt' | 'ios' | 'none'
final ValueListenable<String> installState = ValueNotifier<String>('none');

Future<bool> promptInstall() async => false;

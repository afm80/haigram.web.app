import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// تُقرأ القيم وقت البناء من --dart-define (تأتي من GitHub Secrets)،
/// فلا توجد مفاتيح مكتوبة داخل الكود.
class DefaultFirebaseOptions {
  /// إعدادات تطبيق الويب.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FB_API_KEY'),
    appId: String.fromEnvironment('FB_APP_ID'),
    messagingSenderId: String.fromEnvironment('FB_SENDER_ID'),
    projectId: String.fromEnvironment('FB_PROJECT_ID'),
    authDomain: String.fromEnvironment('FB_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('FB_STORAGE_BUCKET'),
  );

  static const String _androidApiKey =
      String.fromEnvironment('FB_ANDROID_API_KEY');

  /// إعدادات تطبيق أندرويد (appId مختلف عن الويب: 1:...:android:...).
  /// إن لم يُمرَّر FB_ANDROID_API_KEY يُستخدم مفتاح الويب.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _androidApiKey != ''
        ? _androidApiKey
        : String.fromEnvironment('FB_API_KEY'),
    appId: String.fromEnvironment('FB_ANDROID_APP_ID'),
    messagingSenderId: String.fromEnvironment('FB_SENDER_ID'),
    projectId: String.fromEnvironment('FB_PROJECT_ID'),
    storageBucket: String.fromEnvironment('FB_STORAGE_BUCKET'),
  );

  /// Web client ID (من Firebase > Authentication > Google). يلزم لتسجيل
  /// الدخول بـ Google على أندرويد للحصول على idToken.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static FirebaseOptions get currentPlatform => kIsWeb ? web : android;
}

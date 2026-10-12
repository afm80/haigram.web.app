import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// تُقرأ القيم وقت البناء من --dart-define (تأتي من GitHub Secrets)،
/// فلا توجد مفاتيح مكتوبة داخل الكود.
class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FB_API_KEY'),
    appId: String.fromEnvironment('FB_APP_ID'),
    messagingSenderId: String.fromEnvironment('FB_SENDER_ID'),
    projectId: String.fromEnvironment('FB_PROJECT_ID'),
    authDomain: String.fromEnvironment('FB_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('FB_STORAGE_BUCKET'),
  );
}

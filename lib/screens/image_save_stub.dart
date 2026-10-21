import 'package:share_plus/share_plus.dart';

/// غير الويب: مشاركة رابط الصورة (يمكن حفظها من قائمة المشاركة).
Future<bool> saveImageFromUrl(String url) async {
  try {
    await Share.share(url);
    return true;
  } catch (_) {
    return false;
  }
}

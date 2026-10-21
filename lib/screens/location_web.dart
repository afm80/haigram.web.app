// الموقع الحالي على الويب عبر واجهة المتصفح (بلا حزم إضافية).
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ChatLocation {
  final double lat;
  final double lng;
  const ChatLocation(this.lat, this.lng);
}

/// يعيد null إن رفض المستخدم الصلاحية أو تعذّر تحديد الموقع.
Future<ChatLocation?> currentChatLocation() async {
  try {
    final position =
        await html.window.navigator.geolocation.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 12),
      maximumAge: const Duration(minutes: 1),
    );
    final coords = position.coords;
    if (coords == null) return null;
    final lat = coords.latitude;
    final lng = coords.longitude;
    if (lat == null || lng == null) return null;
    return ChatLocation(lat.toDouble(), lng.toDouble());
  } catch (_) {
    return null;
  }
}

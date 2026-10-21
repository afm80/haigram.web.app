// الموقع الحالي لتطبيق أندرويد/آيفون: غير مدعوم هنا (الويب فقط).
class ChatLocation {
  final double lat;
  final double lng;
  const ChatLocation(this.lat, this.lng);
}

/// يعيد null إن لم يتوفر الموقع (أو رُفضت الصلاحية).
Future<ChatLocation?> currentChatLocation() async => null;

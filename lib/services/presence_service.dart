import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// حالة «متصل الآن» الحقيقية.
///
/// - يرسل التطبيق نبضة كل دقيقة (انظر home_shell) ويضع online=false فور
///   الخروج أو إخفاء التطبيق.
/// - تُعدّ الحالة «متصل» فقط إذا كانت آخر نبضة حديثة (أقل من [_staleAfter])،
///   ويُحسب عمرها بساعة الخادم لا بساعة الجهاز، حتى لا تفسدها ساعة خاطئة.
/// - كل من يستمع لنفس المستخدم يحصل فوراً على الحالة الحالية.
class PresenceService {
  static final _db = FirebaseFirestore.instance;
  static final _streams = <String, Stream<bool>>{};

  /// بعد هذه المدة دون نبضة نعتبر المستخدم غير متصل (إغلاق مفاجئ، انقطاع شبكة).
  static const _staleAfter = Duration(seconds: 90);

  // فرق ساعة الخادم عن ساعة هذا الجهاز.
  static Duration _serverOffset = Duration.zero;
  static DateTime? _offsetMeasuredAt;

  static DocumentReference<Map<String, dynamic>> _presence(String uid) =>
      _db.collection('presence').doc(uid);

  static Future<void> setOnline(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = _presence(uid);
    await ref.set(
      {'online': online, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await _measureServerOffset(ref);
  }

  static Future<void> _measureServerOffset(
      DocumentReference<Map<String, dynamic>> ref) async {
    final last = _offsetMeasuredAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    try {
      final snap = await ref.get(const GetOptions(source: Source.server));
      final ts = snap.data()?['updatedAt'];
      if (ts is Timestamp) {
        _serverOffset = ts.toDate().difference(DateTime.now());
        _offsetMeasuredAt = DateTime.now();
      }
    } catch (_) {
      // نكتفي بالقيمة السابقة.
    }
  }

  static Stream<bool> isOnline(String uid) =>
      _streams.putIfAbsent(uid, () => _onlineStream(uid));

  static Stream<bool> _onlineStream(String uid) {
    late final StreamController<bool> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
    Timer? expiry;
    bool? last;

    void emit(bool value) {
      last = value;
      controller.add(value);
    }

    controller = StreamController<bool>.broadcast(
      onListen: () {
        subscription = _presence(uid).snapshots().listen(
          (snapshot) {
            // نتجاهل النسخة المحلية المؤقتة قبل أن يثبّت الخادم وقته.
            if (snapshot.metadata.hasPendingWrites) return;
            expiry?.cancel();
            final data = snapshot.data();
            final updatedAt = data?['updatedAt'];
            if (data?['online'] != true || updatedAt is! Timestamp) {
              emit(false);
              return;
            }
            final serverNow = DateTime.now().add(_serverOffset);
            final age = serverNow.difference(updatedAt.toDate());
            final remaining = _staleAfter - age;
            if (remaining <= Duration.zero) {
              emit(false);
              return;
            }
            emit(true);
            expiry = Timer(remaining, () => emit(false));
          },
          onError: controller.addError,
        );
      },
      onCancel: () {
        if (!controller.hasListener) {
          expiry?.cancel();
          subscription?.cancel();
          last = null;
        }
      },
    );

    // كل مستمع جديد يتلقى الحالة الحالية فوراً (لا ينتظر النبضة التالية).
    return Stream<bool>.multi((listener) {
      final current = last;
      if (current != null) listener.add(current);
      final sub = controller.stream.listen(
        listener.add,
        onError: listener.addError,
      );
      listener.onCancel = sub.cancel;
    });
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  static final _db = FirebaseFirestore.instance;
  static final _streams = <String, Stream<bool>>{};

  static DocumentReference<Map<String, dynamic>> _presence(String uid) =>
      _db.collection('presence').doc(uid);

  static Future<void> setOnline(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _presence(uid).set(
      {'online': online, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  static Stream<bool> isOnline(String uid) =>
      _streams.putIfAbsent(uid, () => _onlineStream(uid));

  static Stream<bool> _onlineStream(String uid) {
    late final StreamController<bool> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
    Timer? expiry;
    controller = StreamController<bool>.broadcast(
      onListen: () {
        subscription = _presence(uid).snapshots().listen(
          (snapshot) {
            expiry?.cancel();
            final data = snapshot.data();
            final updatedAt = data?['updatedAt'];
            if (data?['online'] != true || updatedAt is! Timestamp) {
              controller.add(false);
              return;
            }
            final age = DateTime.now().difference(updatedAt.toDate());
            final remaining = const Duration(minutes: 2) - age;
            if (remaining <= Duration.zero) {
              controller.add(false);
              return;
            }
            controller.add(true);
            expiry = Timer(remaining, () => controller.add(false));
          },
          onError: controller.addError,
        );
      },
      onCancel: () {
        if (!controller.hasListener) {
          expiry?.cancel();
          subscription?.cancel();
        }
      },
    );
    return controller.stream;
  }
}

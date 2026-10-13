import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Conversation {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastSenderUid;
  final String lastMessageId;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastSenderUid,
    required this.lastMessageId,
    required this.updatedAt,
  });

  String otherParticipant(String uid) =>
      participants.firstWhere((participant) => participant != uid);

  factory Conversation.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final updatedAt = data['updatedAt'];
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] as List),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastSenderUid: data['lastSenderUid'] as String? ?? '',
      lastMessageId: data['lastMessageId'] as String? ?? '',
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final DateTime createdAt;
  final List<String> deliveredTo;
  final List<String> readBy;
  final String kind;
  final Uint8List? imageBytes;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
    required this.deliveredTo,
    required this.readBy,
    required this.kind,
    required this.imageBytes,
  });

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return ChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String,
      text: data['text'] as String,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      deliveredTo: List<String>.from(data['deliveredTo'] as List? ?? const []),
      readBy: List<String>.from(data['readBy'] as List? ?? const []),
      kind: data['kind'] as String? ?? 'text',
      imageBytes: (data['image'] as Blob?)?.bytes,
    );
  }
}

class ChatBlockState {
  final bool blockedByMe;
  final bool blockedByThem;

  const ChatBlockState({
    required this.blockedByMe,
    required this.blockedByThem,
  });

  bool get blocked => blockedByMe || blockedByThem;
}

class SocialNotification {
  final String id;
  final String type;
  final String actorUid;
  final String actorUsername;
  final String? postId;
  final String? commentText;
  final DateTime createdAt;
  final bool read;

  const SocialNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorUsername,
    required this.postId,
    required this.commentText,
    required this.createdAt,
    required this.read,
  });

  factory SocialNotification.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return SocialNotification(
      id: doc.id,
      type: data['type'] as String,
      actorUid: data['actorUid'] as String,
      actorUsername: data['actorUsername'] as String? ?? 'مستخدم',
      postId: data['postId'] as String?,
      commentText: data['commentText'] as String?,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      read: data['read'] as bool? ?? false,
    );
  }
}

class SocialService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;
  static String get currentUid => _uid;

  static CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  static CollectionReference<Map<String, dynamic>> _notifications(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  static DocumentReference<Map<String, dynamic>> _blockRef(
          String ownerUid, String otherUid) =>
      _db
          .collection('userBlocks')
          .doc(ownerUid)
          .collection('blocked')
          .doc(otherUid);

  static Stream<ChatBlockState> blockState(String otherUid) {
    late final StreamController<ChatBlockState> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? mineSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? theirsSub;
    bool? blockedByMe;
    bool? blockedByThem;

    void emitIfReady() {
      if (blockedByMe != null && blockedByThem != null) {
        controller.add(ChatBlockState(
          blockedByMe: blockedByMe!,
          blockedByThem: blockedByThem!,
        ));
      }
    }

    controller = StreamController<ChatBlockState>(
      onListen: () {
        mineSub = _blockRef(_uid, otherUid).snapshots().listen(
          (snapshot) {
            blockedByMe = snapshot.exists;
            emitIfReady();
          },
          onError: controller.addError,
        );
        theirsSub = _blockRef(otherUid, _uid).snapshots().listen(
          (snapshot) {
            blockedByThem = snapshot.exists;
            emitIfReady();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await mineSub?.cancel();
        await theirsSub?.cancel();
      },
    );
    return controller.stream;
  }

  static Future<bool> isBlockedEither(String otherUid) async {
    final snapshots = await Future.wait([
      _blockRef(_uid, otherUid).get(),
      _blockRef(otherUid, _uid).get(),
    ]);
    return snapshots.any((snapshot) => snapshot.exists);
  }

  static Future<void> setBlocked(String otherUid, bool blocked) async {
    if (otherUid.isEmpty || otherUid == _uid) {
      throw ArgumentError.value(otherUid, 'otherUid', 'مستخدم غير صالح');
    }
    final reference = _blockRef(_uid, otherUid);
    if (blocked) {
      // الحظر يلغي متابعتي له أيضاً.
      final batch = _db.batch()
        ..set(reference, {'createdAt': FieldValue.serverTimestamp()})
        ..delete(_db
            .collection('users')
            .doc(_uid)
            .collection('following')
            .doc(otherUid))
        ..delete(_db
            .collection('users')
            .doc(otherUid)
            .collection('followers')
            .doc(_uid));
      await batch.commit();
    } else {
      await reference.delete();
    }
  }

  /// أسباب الإبلاغ المتاحة (المفتاح يُخزَّن، والنص يُعرض).
  static const reportReasons = <String, String>{
    'spam': 'محتوى مزعج أو احتيالي',
    'abuse': 'تحرّش أو إساءة',
    'inappropriate': 'محتوى غير لائق',
    'impersonation': 'انتحال شخصية',
    'other': 'سبب آخر',
  };

  /// يرسل بلاغاً عن مستخدم إلى مجموعة reports (يقرؤها المشرف من لوحة Firebase).
  static Future<void> reportUser(String targetUid, String reason,
      {String details = ''}) async {
    if (targetUid.isEmpty ||
        targetUid == _uid ||
        !reportReasons.containsKey(reason)) {
      throw ArgumentError('بلاغ غير صالح');
    }
    await _db.collection('reports').add({
      'type': 'user',
      'targetUid': targetUid,
      'reporterUid': _uid,
      'reason': reason,
      'details': details.trim().length > 300
          ? details.trim().substring(0, 300)
          : details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<Conversation>> conversations() => _chats
          .where('participants', arrayContains: _uid)
          .snapshots()
          .map((snapshot) {
        final items = snapshot.docs.map(Conversation.fromDoc).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        for (final conversation in items) {
          if (conversation.lastSenderUid != _uid &&
              conversation.lastMessageId.isNotEmpty) {
            unawaited(_markDelivered(
              conversation.id,
              conversation.lastMessageId,
            ));
          }
        }
        return items;
      });

  static Stream<List<ChatMessage>> messages(String conversationId) => _chats
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(100)
          .snapshots()
          .map((snapshot) {
        final messages = snapshot.docs.map(ChatMessage.fromDoc).toList();
        unawaited(_markMessagesRead(snapshot.docs));
        return messages;
      });

  static Future<void> _markDelivered(
      String conversationId, String messageId) async {
    final reference =
        _chats.doc(conversationId).collection('messages').doc(messageId);
    final snapshot = await reference.get();
    final data = snapshot.data();
    if (data == null || data['senderUid'] == _uid) return;
    final deliveredTo = List<String>.from(data['deliveredTo'] as List? ?? []);
    if (deliveredTo.contains(_uid)) return;
    await reference.update({
      'deliveredTo': FieldValue.arrayUnion([_uid]),
    });
  }

  static Future<void> _markMessagesRead(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents) async {
    final batch = _db.batch();
    var hasUpdates = false;
    for (final document in documents) {
      final data = document.data();
      if (data['senderUid'] == _uid) continue;
      final deliveredTo =
          List<String>.from(data['deliveredTo'] as List? ?? const []);
      final readBy = List<String>.from(data['readBy'] as List? ?? const []);
      if (readBy.contains(_uid) && deliveredTo.contains(_uid)) continue;
      batch.update(document.reference, {
        'deliveredTo': FieldValue.arrayUnion([_uid]),
        'readBy': FieldValue.arrayUnion([_uid]),
      });
      hasUpdates = true;
    }
    if (hasUpdates) await batch.commit();
  }

  static Future<bool> areMutualFriends(String otherUid) async {
    if (otherUid.isEmpty || otherUid == _uid) return false;
    final snapshots = await Future.wait([
      _db
          .collection('users')
          .doc(_uid)
          .collection('following')
          .doc(otherUid)
          .get(),
      _db
          .collection('users')
          .doc(otherUid)
          .collection('following')
          .doc(_uid)
          .get(),
      _blockRef(_uid, otherUid).get(),
      _blockRef(otherUid, _uid).get(),
    ]);
    return snapshots[0].exists &&
        snapshots[1].exists &&
        !snapshots[2].exists &&
        !snapshots[3].exists;
  }

  static Future<String> startConversation(String otherUid) async {
    if (otherUid.isEmpty || otherUid == _uid) {
      throw ArgumentError.value(otherUid, 'otherUid', 'مستخدم غير صالح');
    }
    if (await isBlockedEither(otherUid)) {
      throw StateError('لا يمكن بدء محادثة مع مستخدم محظور');
    }
    final participants = [_uid, otherUid]..sort();
    final conversationId =
        '${participants[0].length}_${participants[0]}${participants[1].length}_${participants[1]}';
    final reference = _chats.doc(conversationId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        final stored =
            List<String>.from(snapshot.data()!['participants'] as List);
        if (stored.toSet().difference(participants.toSet()).isNotEmpty ||
            participants.toSet().difference(stored.toSet()).isNotEmpty) {
          throw StateError('المحادثة لا تخص هذين المستخدمين');
        }
        return;
      }
      transaction.set(reference, {
        'participants': participants,
        'lastMessage': '',
        'lastSenderUid': '',
        'lastMessageId': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return conversationId;
  }

  static Future<void> sendMessage(String conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw ArgumentError('يجب أن تكون الرسالة بين حرف واحد و2000 حرف');
    }
    await _sendChatMessage(conversationId, text: trimmed, kind: 'text');
  }

  static Future<void> sendSticker(String conversationId, String sticker) async {
    if (sticker.isEmpty || sticker.length > 24) {
      throw ArgumentError.value(sticker, 'sticker', 'ملصق غير صالح');
    }
    await _sendChatMessage(conversationId, text: sticker, kind: 'sticker');
  }

  static Future<void> sendImage(
      String conversationId, Uint8List imageBytes) async {
    if (imageBytes.isEmpty || imageBytes.length > 700 * 1024) {
      throw ArgumentError('حجم الصورة يجب ألا يتجاوز 700 كيلوبايت');
    }
    await _sendChatMessage(
      conversationId,
      text: '📷 صورة',
      kind: 'image',
      imageBytes: imageBytes,
    );
  }

  static Future<void> deleteMessage(
      String conversationId, String messageId) async {
    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc(messageId);
    final snapshots = await Future.wait([chat.get(), message.get()]);
    final chatSnapshot = snapshots[0];
    final messageSnapshot = snapshots[1];
    if (!chatSnapshot.exists || !messageSnapshot.exists) {
      throw StateError('الرسالة غير موجودة');
    }
    if (messageSnapshot.data()?['senderUid'] != _uid) {
      throw StateError('يمكنك حذف رسائلك فقط');
    }

    final batch = _db.batch();
    if (chatSnapshot.data()?['lastMessageId'] == messageId) {
      final recentMessages = await chat
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(2)
          .get();
      final previousMessages = recentMessages.docs
          .where((document) => document.id != messageId);
      final previous =
          previousMessages.isEmpty ? null : previousMessages.first;
      batch.update(chat, {
        'lastMessage': previous?.data()['text'] ?? '',
        'lastSenderUid': previous?.data()['senderUid'] ?? '',
        'lastMessageId': previous?.id ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.delete(message);
    await batch.commit();
  }

  static Future<void> _sendChatMessage(
    String conversationId, {
    required String text,
    required String kind,
    Uint8List? imageBytes,
  }) async {
    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc();
    final conversation = await chat.get();
    if (!conversation.exists) {
      throw StateError('المحادثة غير موجودة');
    }
    final participants =
        List<String>.from(conversation.data()!['participants'] as List);
    if (!participants.contains(_uid)) {
      throw StateError('لا تملك صلاحية إرسال رسالة في هذه المحادثة');
    }
    final otherUid =
        participants.firstWhere((participant) => participant != _uid);
    if (await isBlockedEither(otherUid)) {
      throw StateError('لا يمكن إرسال الرسائل بعد الحظر');
    }

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(chat);
      if (!snapshot.exists ||
          !List<String>.from(snapshot.data()!['participants'] as List)
              .contains(_uid)) {
        throw StateError('لا تملك صلاحية إرسال رسالة في هذه المحادثة');
      }
      final messageData = <String, dynamic>{
        'senderUid': _uid,
        'text': text,
        'kind': kind,
        'deliveredTo': [_uid],
        'readBy': [_uid],
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (imageBytes != null) messageData['image'] = Blob(imageBytes);
      transaction.update(chat, {
        'lastMessage': text,
        'lastSenderUid': _uid,
        'lastMessageId': message.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(message, messageData);
    });
  }

  static Future<List<String>> mutualFriendIds() async {
    final following =
        _db.collection('users').doc(_uid).collection('following').get();
    final followers =
        _db.collection('users').doc(_uid).collection('followers').get();
    final results = await Future.wait([following, followers]);
    final followingIds = results[0].docs.map((doc) => doc.id).toSet();
    final followerIds = results[1].docs.map((doc) => doc.id).toSet();
    final friends = followingIds.intersection(followerIds).toList()..sort();
    return friends;
  }

  static Stream<List<SocialNotification>> notifications() =>
      _notifications(_uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map((snapshot) =>
              snapshot.docs.map(SocialNotification.fromDoc).toList());

  static Stream<int> unreadNotificationCount() => _notifications(_uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((snapshot) => snapshot.size);

  static Future<void> markNotificationRead(String notificationId) =>
      _notifications(_uid).doc(notificationId).update({'read': true});

  /// يعلّم الإشعارات كمقروءة؛ مع [type] يقتصر على نوع واحد (follow/like/comment).
  static Future<void> markAllNotificationsRead({String? type}) async {
    final notifications = _notifications(_uid);
    while (true) {
      var query = notifications.where('read', isEqualTo: false);
      if (type != null) query = query.where('type', isEqualTo: type);
      final snapshot = await query.limit(450).get();
      if (snapshot.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
      if (snapshot.docs.length < 450) return;
    }
  }

  static void addFollowNotification({
    required WriteBatch batch,
    required String recipientUid,
    required String actorUid,
    required String actorUsername,
  }) {
    if (recipientUid == actorUid) return;
    batch.set(_notifications(recipientUid).doc('follow_$actorUid'), {
      'type': 'follow',
      'actorUid': actorUid,
      'actorUsername': actorUsername,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static void addLikeNotification({
    required WriteBatch batch,
    required String recipientUid,
    required String actorUid,
    required String actorUsername,
    required String postId,
  }) {
    if (recipientUid == actorUid) return;
    batch.set(_notifications(recipientUid).doc('like_${postId}_$actorUid'), {
      'type': 'like',
      'actorUid': actorUid,
      'actorUsername': actorUsername,
      'postId': postId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static void addCommentNotification({
    required WriteBatch batch,
    required String recipientUid,
    required String actorUid,
    required String actorUsername,
    required String postId,
    required String commentId,
    required String commentText,
  }) {
    if (recipientUid == actorUid) return;
    batch.set(_notifications(recipientUid).doc('comment_$commentId'), {
      'type': 'comment',
      'actorUid': actorUid,
      'actorUsername': actorUsername,
      'postId': postId,
      'commentId': commentId,
      'commentText': commentText,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

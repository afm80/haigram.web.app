import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Conversation {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastSenderUid;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastSenderUid,
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

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return ChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String,
      text: data['text'] as String,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
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

  static Stream<List<Conversation>> conversations() => _chats
      .where('participants', arrayContains: _uid)
      .snapshots()
      .map((snapshot) {
        final items = snapshot.docs.map(Conversation.fromDoc).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return items;
      });

  static Stream<List<ChatMessage>> messages(String conversationId) => _chats
      .doc(conversationId)
      .collection('messages')
      .orderBy('createdAt')
      .limitToLast(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(ChatMessage.fromDoc).toList());

  static Future<String> startConversation(String otherUid) async {
    if (otherUid.isEmpty || otherUid == _uid) {
      throw ArgumentError.value(otherUid, 'otherUid', 'مستخدم غير صالح');
    }
    final participants = [_uid, otherUid]..sort();
    final conversationId =
        '${participants[0].length}_${participants[0]}${participants[1].length}_${participants[1]}';
    final reference = _chats.doc(conversationId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        final stored = List<String>.from(
            snapshot.data()!['participants'] as List);
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

    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(chat);
      if (!snapshot.exists ||
          !List<String>.from(snapshot.data()!['participants'] as List)
              .contains(_uid)) {
        throw StateError('لا تملك صلاحية إرسال رسالة في هذه المحادثة');
      }
      transaction.update(chat, {
        'lastMessage': trimmed,
        'lastSenderUid': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(message, {
        'senderUid': _uid,
        'text': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<List<String>> mutualFriendIds() async {
    final following = _db
        .collection('users')
        .doc(_uid)
        .collection('following')
        .get();
    final followers = _db
        .collection('users')
        .doc(_uid)
        .collection('followers')
        .get();
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

  static Future<void> markAllNotificationsRead() async {
    final notifications = _notifications(_uid);
    while (true) {
      final snapshot = await notifications
          .where('read', isEqualTo: false)
          .limit(450)
          .get();
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

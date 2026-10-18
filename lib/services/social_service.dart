import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n.dart';
import 'post_service.dart';

/// وقت من حقل Firestore. الكتابة المعلّقة (serverTimestamp لم يؤكدها الخادم
/// بعد) تأتي null: نعتبرها «الآن» بدل 1970 حتى لا تقفز المحادثة في القائمة
/// ولا يظهر وقت الرسالة «قبل 20000 يوم».
DateTime _readTs(Object? value, {bool pending = false}) {
  if (value is Timestamp) return value.toDate();
  return pending ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0);
}

/// خريطة {uid: وقت} مثل readAt / deliveredAt / clearedAt.
Map<String, DateTime> _tsMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, DateTime>{};
  raw.forEach((key, value) {
    if (key is String && value is Timestamp) out[key] = value.toDate();
  });
  return out;
}

class Conversation {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastSenderUid;
  final String lastMessageId;
  final DateTime updatedAt;

  /// آخر وقت قرأ/استلم/مسح فيه كل طرف (مفتاحها uid).
  final Map<String, DateTime> readAt;
  final Map<String, DateTime> deliveredAt;
  final Map<String, DateTime> clearedAt;

  const Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastSenderUid,
    required this.lastMessageId,
    required this.updatedAt,
    this.readAt = const {},
    this.deliveredAt = const {},
    this.clearedAt = const {},
  });

  String otherParticipant(String uid) =>
      participants.firstWhere((participant) => participant != uid);

  /// آخر رسالة من الطرف الآخر ولم أفتح المحادثة بعدها.
  bool unreadFor(String uid) {
    if (lastMessageId.isEmpty || lastSenderUid.isEmpty || lastSenderUid == uid) {
      return false;
    }
    final read = readAt[uid];
    return read == null || updatedAt.isAfter(read);
  }

  /// تظهر في صندوقي: فيها رسالة ولم أمسحها لديّ بعد آخر نشاط.
  bool visibleFor(String uid) {
    if (lastMessageId.isEmpty) return false;
    final cleared = clearedAt[uid];
    return cleared == null || updatedAt.isAfter(cleared);
  }

  /// null إن كان المستند تالفاً (بدل أن يكسر قائمة المحادثات كلها).
  static Conversation? tryFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] as List);
      if (participants.length != 2 || participants[0] == participants[1]) {
        return null;
      }
      return Conversation(
        id: doc.id,
        participants: participants,
        lastMessage: data['lastMessage'] as String? ?? '',
        lastSenderUid: data['lastSenderUid'] as String? ?? '',
        lastMessageId: data['lastMessageId'] as String? ?? '',
        updatedAt: _readTs(data['updatedAt'],
            pending: doc.metadata.hasPendingWrites),
        readAt: _tsMap(data['readAt']),
        deliveredAt: _tsMap(data['deliveredAt']),
        clearedAt: _tsMap(data['clearedAt']),
      );
    } catch (_) {
      return null;
    }
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

  /// رابط الصورة عند استعمال Cloudinary/Storage (وضع التجربة يستعمل [imageBytes]).
  final String? imageUrl;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
    required this.deliveredTo,
    required this.readBy,
    required this.kind,
    required this.imageBytes,
    this.imageUrl,
  });

  /// null إن كانت الرسالة تالفة (حقل ناقص أو بنوع خاطئ): تُتجاهل هي وحدها
  /// بدل أن يفشل تحميل المحادثة كلها.
  static ChatMessage? tryFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      return ChatMessage(
        id: doc.id,
        senderUid: data['senderUid'] as String,
        text: data['text'] as String,
        createdAt: _readTs(data['createdAt'],
            pending: doc.metadata.hasPendingWrites),
        deliveredTo:
            List<String>.from(data['deliveredTo'] as List? ?? const []),
        readBy: List<String>.from(data['readBy'] as List? ?? const []),
        kind: data['kind'] as String? ?? 'text',
        imageBytes: (data['image'] as Blob?)?.bytes,
        imageUrl: data['imageUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// زيارة لملفي الشخصي.
class ProfileVisit {
  final String uid;
  final DateTime at;
  const ProfileVisit(this.uid, this.at);
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
      actorUsername: data['actorUsername'] as String? ?? tr('مستخدم'),
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
      throw ArgumentError.value(otherUid, 'otherUid', tr('مستخدم غير صالح'));
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
            .doc(_uid))
        ..delete(_db
            .collection('users')
            .doc(otherUid)
            .collection('followRequests')
            .doc(_uid))
        ..delete(_db
            .collection('users')
            .doc(_uid)
            .collection('followRequests')
            .doc(otherUid));
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
      throw ArgumentError(tr('بلاغ غير صالح'));
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

  /// يرسل بلاغاً عن منشور بعينه (نفس مجموعة reports مع type = post).
  static Future<void> reportPost(String postId, String ownerUid, String reason,
      {String details = ''}) async {
    if (postId.isEmpty ||
        ownerUid.isEmpty ||
        ownerUid == _uid ||
        !reportReasons.containsKey(reason)) {
      throw ArgumentError(tr('بلاغ غير صالح'));
    }
    await _db.collection('reports').add({
      'type': 'post',
      'postId': postId,
      'targetUid': ownerUid,
      'reporterUid': _uid,
      'reason': reason,
      'details': details.trim().length > 300
          ? details.trim().substring(0, 300)
          : details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// يرسل بلاغاً عن تعليق بعينه (نفس مجموعة reports مع type = comment).
  static Future<void> reportComment(
      String postId, String commentId, String ownerUid, String reason,
      {String details = ''}) async {
    if (postId.isEmpty ||
        commentId.isEmpty ||
        ownerUid.isEmpty ||
        ownerUid == _uid ||
        !reportReasons.containsKey(reason)) {
      throw ArgumentError(tr('بلاغ غير صالح'));
    }
    await _db.collection('reports').add({
      'type': 'comment',
      'postId': postId,
      'commentId': commentId,
      'targetUid': ownerUid,
      'reporterUid': _uid,
      'reason': reason,
      'details': details.trim().length > 300
          ? details.trim().substring(0, 300)
          : details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// محادثات/رسائل أُرسل لها «تم التسليم» في هذه الجلسة، حتى لا نكتب
  /// المستند نفسه عند كل تحديث لقائمة المحادثات.
  static final Set<String> _deliveredMarked = <String>{};

  static Stream<List<Conversation>> conversations() => _chats
          .where('participants', arrayContains: _uid)
          .snapshots()
          .map((snapshot) {
        final items = snapshot.docs
            .map(Conversation.tryFromDoc)
            .whereType<Conversation>()
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        for (final conversation in items) {
          if (conversation.lastSenderUid != _uid &&
              conversation.lastMessageId.isNotEmpty) {
            final delivered = conversation.deliveredAt[_uid];
            if (delivered != null &&
                !conversation.updatedAt.isAfter(delivered)) {
              continue;
            }
            final key = '${conversation.id}/${conversation.lastMessageId}';
            if (_deliveredMarked.add(key)) {
              // حقل واحد في المحادثة بدل قراءة الرسالة وتعديلها.
              unawaited(_stampChat(
                conversation.id,
                'deliveredAt',
                conversation.updatedAt,
              ).catchError((Object _) {
                _deliveredMarked.remove(key); // تُعاد المحاولة عند التحديث التالي
              }));
            }
          }
        }
        return items;
      });

  /// يكتب وقتي في حقل خريطة بالمحادثة (readAt / deliveredAt). نزيد ميلي ثانية
  /// واحدة لأن الويب يقصّ الميكروثواني، فلا تبقى الرسالة «غير مقروءة» للأبد.
  static Future<void> _stampChat(
      String conversationId, String field, DateTime at) {
    return _chats.doc(conversationId).update({
      '$field.$_uid':
          Timestamp.fromDate(at.add(const Duration(milliseconds: 1))),
    });
  }

  /// مستند المحادثة نفسه (accepted وآخر مرسل...) لمعرفة هل يحق لي الإرسال.
  static Stream<Map<String, dynamic>?> chatStream(String conversationId) =>
      _chats.doc(conversationId).snapshots().map((snapshot) => snapshot.data());

  /// حجم الصفحة الافتراضي لرسائل المحادثة.
  static const messagesPageSize = 100;

  /// رسائل المحادثة مباشرةً. بلا [since]: آخر [limit] رسالة. مع [since]: كل
  /// الرسائل منذ ذلك الوقت (بلا حد) — تُستعمل بعد تحميل صفحات أقدم، فلا تُعاد
  /// قراءة القديم عند كل صفحة. لا يعلّم الرسائل مقروءة: الشاشة هي من تستدعي
  /// [markChatRead] عندما تكون المحادثة ظاهرة فعلاً أمام المستخدم.
  static Stream<List<ChatMessage>> messages(String conversationId,
      {int limit = messagesPageSize, DateTime? since}) {
    final base = _chats
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt');
    final query = since == null
        ? base.limitToLast(limit)
        : base.where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    return query.snapshots().map((snapshot) => snapshot.docs
        .map(ChatMessage.tryFromDoc)
        .whereType<ChatMessage>()
        .toList());
  }

  /// صفحة أقدم من [before] (تصاعدياً). قد تتضمن رسالة الحدّ نفسها، فيدمجها
  /// المستدعي بحسب المعرّف. إن رجع أقل من [limit] فلا يوجد المزيد.
  static Future<List<ChatMessage>> olderMessages(
      String conversationId, DateTime before,
      {int limit = messagesPageSize}) async {
    final snapshot = await _chats
        .doc(conversationId)
        .collection('messages')
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(
                before.add(const Duration(milliseconds: 1))))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map(ChatMessage.tryFromDoc)
        .whereType<ChatMessage>()
        .toList()
        .reversed
        .toList();
  }

  static final Map<String, int> _readStamped = <String, int>{};

  /// يعلّم المحادثة «مقروءة» حتى [upTo] (وقت أحدث رسالة من الطرف الآخر ظهرت
  /// أمامي) بكتابة واحدة، بدل تعديل كل رسالة. يُستدعى فقط والمحادثة ظاهرة.
  static Future<void> markChatRead(String conversationId, DateTime upTo) async {
    final stamp = upTo.millisecondsSinceEpoch;
    if ((_readStamped[conversationId] ?? 0) >= stamp) return;
    _readStamped[conversationId] = stamp;
    try {
      await _stampChat(conversationId, 'readAt', upTo);
    } catch (_) {
      _readStamped.remove(conversationId);
      rethrow;
    }
  }

  /// «حذف المحادثة لديّ»: تختفي من صندوقي وتُخفى رسائلها السابقة عني فقط،
  /// وتعود (برسائلها الجديدة وحدها) إن وصلت رسالة بعد ذلك.
  static Future<void> clearChatForMe(String conversationId) {
    return _chats
        .doc(conversationId)
        .update({'clearedAt.$_uid': FieldValue.serverTimestamp()});
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
      throw ArgumentError.value(otherUid, 'otherUid', tr('مستخدم غير صالح'));
    }
    if (await isBlockedEither(otherUid)) {
      throw StateError(tr('لا يمكن بدء محادثة مع مستخدم محظور'));
    }
    final participants = [_uid, otherUid]..sort();
    final conversationId =
        '${participants[0].length}_${participants[0]}${participants[1].length}_${participants[1]}';
    final reference = _chats.doc(conversationId);

    // ننشئ مباشرة بلا قراءة مسبقة: القواعد لا تسمح بقراءة مستند غير موجود
    // (حتى لا يُكشف هل تراسل مستخدمان). إن كانت موجودة يُرفض الإنشاء، فنتأكد
    // بقراءتها (مسموحة لطرفيها فقط) ونُكمل.
    try {
      await reference.set({
        'participants': participants,
        'lastMessage': '',
        'lastSenderUid': '',
        'lastMessageId': '',
        // رسالة واحدة نصية لغير الأصدقاء حتى يردّ الطرف الآخر (انظر القواعد).
        'accepted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      try {
        await reference.get();
      } on FirebaseException {
        throw StateError(tr('تعذر بدء المحادثة'));
      }
    }
    return conversationId;
  }

  static Future<void> sendMessage(String conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw ArgumentError(tr('يجب أن تكون الرسالة بين حرف واحد و2000 حرف'));
    }
    await _sendChatMessage(conversationId, text: trimmed, kind: 'text');
  }

  static Future<void> sendSticker(String conversationId, String sticker) async {
    if (sticker.isEmpty || sticker.length > 24) {
      throw ArgumentError.value(sticker, 'sticker', tr('ملصق غير صالح'));
    }
    await _sendChatMessage(conversationId, text: sticker, kind: 'sticker');
  }

  static Future<void> sendImage(
      String conversationId, Uint8List imageBytes) async {
    if (imageBytes.isEmpty || imageBytes.length > 700 * 1024) {
      throw ArgumentError(tr('حجم الصورة يجب ألا يتجاوز 700 كيلوبايت'));
    }
    // Cloudinary/Storage إن كانا مفعّلين (رابط فقط في Firestore)، وإلا تُحفظ
    // البايتات داخل المستند كما في وضع التجربة.
    final url = await PostService.uploadChatImage(imageBytes);
    await _sendChatMessage(
      conversationId,
      text: tr('📷 صورة'),
      kind: 'image',
      imageBytes: url == null ? imageBytes : null,
      imageUrl: url,
    );
  }

  // ===== «حذف لديّ فقط»: معرّفات الرسائل المخفية عن المستخدم الحالي =====
  static DocumentReference<Map<String, dynamic>> _hiddenDoc(
          String conversationId) =>
      _chats.doc(conversationId).collection('hiddenMessages').doc(_uid);

  static Stream<Set<String>> hiddenMessageIds(String conversationId) =>
      _hiddenDoc(conversationId).snapshots().map(
            (snapshot) =>
                Set<String>.from((snapshot.data()?['ids'] as List?) ?? const []),
          );

  static Future<void> hideMessageForMe(
      String conversationId, String messageId) async {
    await _hiddenDoc(conversationId).set(
      {
        'ids': FieldValue.arrayUnion([messageId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// «حذف لدى الجميع»: يحذف رسالتي (نصاً أو صورة أو ملصقاً) من المحادثة نهائياً.
  static Future<void> deleteMessage(
      String conversationId, String messageId) async {
    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc(messageId);
    final snapshots = await Future.wait([chat.get(), message.get()]);
    final chatSnapshot = snapshots[0];
    final messageSnapshot = snapshots[1];
    if (!chatSnapshot.exists || !messageSnapshot.exists) {
      throw StateError(tr('الرسالة غير موجودة'));
    }
    if (messageSnapshot.data()?['senderUid'] != _uid) {
      throw StateError(tr('يمكنك حذف رسائلك فقط'));
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
    String? imageUrl,
  }) async {
    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc();
    String? otherUid;
    try {
      // قراءة واحدة داخل المعاملة تكفي للفحص والكتابة (كانت ~8 قراءات).
      // القواعد في الخادم هي المرجع؛ الفحص هنا لرسالة خطأ مفهومة فقط.
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(chat);
        final current = snapshot.data();
        if (!snapshot.exists || current == null) {
          throw StateError(tr('المحادثة غير موجودة'));
        }
        final participants =
            List<String>.from(current['participants'] as List);
        if (!participants.contains(_uid)) {
          throw StateError(tr('لا تملك صلاحية إرسال رسالة في هذه المحادثة'));
        }
        final other =
            participants.firstWhere((participant) => participant != _uid);
        otherUid = other;

        // غير الأصدقاء: رسالة أولى نصية فقط، ثم الانتظار حتى يردّ الطرف الآخر.
        final accepted = current['accepted'] as bool? ?? true;
        final currentSender = current['lastSenderUid'] as String? ?? '';
        final hasMessages =
            (current['lastMessageId'] as String? ?? '').isNotEmpty;
        final startedBy =
            List<String>.from(current['startedBy'] as List? ?? const []);
        final replying = hasMessages && currentSender != _uid;
        if (!accepted && !replying && !await areMutualFriends(other)) {
          if (hasMessages || startedBy.contains(_uid)) {
            throw StateError(tr('انتظر رد الطرف الآخر لتكمل المراسلة'));
          }
          if (kind != 'text') {
            throw StateError(tr('الرسالة الأولى لغير الأصدقاء نص فقط'));
          }
        }

        final messageData = <String, dynamic>{
          'senderUid': _uid,
          'text': text,
          'kind': kind,
          'deliveredTo': [_uid],
          'readBy': [_uid],
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (imageUrl != null) {
          messageData['imageUrl'] = imageUrl;
        } else if (imageBytes != null) {
          messageData['image'] = Blob(imageBytes);
        }
        // الردّ على رسالة الطرف الآخر يجعل المحادثة «مقبولة» للطرفين.
        final acceptsNow =
            !accepted && currentSender.isNotEmpty && currentSender != _uid;
        transaction.update(chat, {
          'lastMessage': text,
          'lastSenderUid': _uid,
          'lastMessageId': message.id,
          'updatedAt': FieldValue.serverTimestamp(),
          if (acceptsNow) 'accepted': true,
          // يُسجَّل المرسل ولا يُمسح بحذف رسالته (يمنع «أرسل ثم احذف»).
          if (!startedBy.contains(_uid))
            'startedBy': FieldValue.arrayUnion([_uid]),
        });
        transaction.set(message, messageData);
      });
    } on FirebaseException catch (e) {
      // رفض القواعد غالباً بسبب الحظر: نُظهر رسالة مفهومة.
      final other = otherUid;
      if (e.code == 'permission-denied' &&
          other != null &&
          await isBlockedEither(other)) {
        throw StateError(tr('لا يمكن إرسال الرسائل بعد الحظر'));
      }
      rethrow;
    }
  }

  /// من راسلتهم مؤخراً (الأحدث أولاً)، من سجل المحادثات. تُهمل المحادثات
  /// الفارغة التي لم تُرسل فيها أي رسالة. لا يعلّم الرسائل كمُسلَّمة.
  static Future<List<String>> recentChatPartnerIds() async {
    final snapshot =
        await _chats.where('participants', arrayContains: _uid).get();
    final items = snapshot.docs
        .map(Conversation.tryFromDoc)
        .whereType<Conversation>()
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final c in items)
        if (c.visibleFor(_uid)) c.otherParticipant(_uid),
    ];
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

  /// يسجّل زيارتي لملف [ownerUid] (يُحدَّث وقتها عند كل زيارة).
  static Future<void> recordProfileVisit(String ownerUid) {
    if (ownerUid == _uid) return Future.value();
    return _db
        .collection('users')
        .doc(ownerUid)
        .collection('profileVisits')
        .doc(_uid)
        .set({'at': FieldValue.serverTimestamp()});
  }

  /// من زاروا ملفي خلال آخر 30 يوماً (الأحدث أولاً).
  static Stream<List<ProfileVisit>> profileVisits() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _db
        .collection('users')
        .doc(_uid)
        .collection('profileVisits')
        .where('at', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('at', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => [
              for (final doc in snapshot.docs)
                if (doc.data()['at'] is Timestamp)
                  ProfileVisit(doc.id, (doc.data()['at'] as Timestamp).toDate()),
            ]);
  }

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
      if (type == 'follow') {
        query = query.where('type', whereIn: ['follow', 'followAccepted']);
      } else if (type != null) {
        query = query.where('type', isEqualTo: type);
      }
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

  static void addFollowRequestNotification({
    required WriteBatch batch,
    required String recipientUid,
    required String actorUid,
    required String actorUsername,
  }) {
    if (recipientUid == actorUid) return;
    batch.set(_notifications(recipientUid).doc('followRequest_$actorUid'), {
      'type': 'followRequest',
      'actorUid': actorUid,
      'actorUsername': actorUsername,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static void addFollowAcceptedNotification({
    required WriteBatch batch,
    required String recipientUid,
    required String actorUid,
    required String actorUsername,
  }) {
    if (recipientUid == actorUid) return;
    batch.set(_notifications(recipientUid).doc('followAccepted_$actorUid'), {
      'type': 'followAccepted',
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

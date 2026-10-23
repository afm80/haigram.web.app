import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

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

/// خريطة {uid: true/false} مثل pinned / muted.
Map<String, bool> _boolMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  raw.forEach((key, value) {
    if (key is String && value is bool) out[key] = value;
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

  /// من ثبّت المحادثة / كتمها (مفتاحها uid).
  final Map<String, bool> pinned;
  final Map<String, bool> muted;

  /// كتم مؤقت: وقت انتهاء الكتم لكل مستخدم (كإنستغرام: ساعة/8/24 ساعة).
  final Map<String, DateTime> mutedUntil;

  /// من أرشف المحادثة ومتى (مفتاحها uid).
  final Map<String, bool> archived;
  final Map<String, DateTime> archivedAt;

  /// مقبولة: غير المقبولة = طلب رسالة لم يردّ عليه أحد بعد.
  final bool accepted;

  /// علّمتها «غير مقروءة» يدوياً على هذا الجهاز (كإنستغرام). لا تُزامن.
  final bool localUnread;

  /// محادثة جماعية: اسم وصورة، من أنشأها، وقائمة المشرفين.
  final bool isGroup;
  final String groupName;
  final String groupPhoto;
  final String createdBy;
  final List<String> admins;

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
    this.pinned = const {},
    this.muted = const {},
    this.mutedUntil = const {},
    this.archived = const {},
    this.archivedAt = const {},
    this.accepted = true,
    this.localUnread = false,
    this.isGroup = false,
    this.groupName = '',
    this.groupPhoto = '',
    this.createdBy = '',
    this.admins = const [],
  });

  bool pinnedFor(String uid) => pinned[uid] == true;

  /// مكتومة لديّ: كتم دائم، أو كتم مؤقت لم ينتهِ بعد.
  bool mutedFor(String uid) {
    if (muted[uid] == true) return true;
    final until = mutedUntil[uid];
    return until != null && until.isAfter(DateTime.now());
  }

  /// هل هذا المستخدم مشرف في المجموعة؟ (المنشئ مشرف دائماً)
  bool isAdminOf(String uid) =>
      isGroup && (createdBy == uid || admins.contains(uid));

  /// عنوان المجموعة الظاهر في الواجهة.
  String get groupTitle => groupName.trim().isEmpty ? 'مجموعة' : groupName;

  /// باقي الأعضاء (غيري).
  List<String> othersFor(String uid) =>
      participants.where((participant) => participant != uid).toList();

  /// مؤرشفة لديّ ولم يصلها نشاط بعد الأرشفة: تعود تلقائياً للصندوق عند وصول
  /// رسالة جديدة (كإنستغرام).
  bool archivedFor(String uid) {
    if (archived[uid] != true) return false;
    final at = archivedAt[uid];
    return at == null || !updatedAt.isAfter(at);
  }

  String otherParticipant(String uid) =>
      participants.firstWhere((participant) => participant != uid);

  /// آخر رسالة من الطرف الآخر ولم أفتح المحادثة بعدها.
  /// تشمل التعليم اليدوي «كغير مقروء» (كإنستغرام).
  bool unreadFor(String uid) {
    if (localUnread) return true;
    if (lastMessageId.isEmpty ||
        lastSenderUid.isEmpty ||
        lastSenderUid == uid) {
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

  /// طلب رسالة لي: غير مقبولة، ووصلتني رسالة من الطرف الآخر ولم أردّ بعد
  /// (كإنستغرام: تظهر في «طلبات الرسائل» منفصلة عن الصندوق).
  bool isRequestFor(String uid) =>
      !accepted &&
      lastMessageId.isNotEmpty &&
      lastSenderUid.isNotEmpty &&
      lastSenderUid != uid;

  /// null إن كان المستند تالفاً (بدل أن يكسر قائمة المحادثات كلها).
  static Conversation? tryFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      {bool localUnread = false}) {
    try {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] as List);
      final group = data['isGroup'] == true;
      if (group) {
        if (participants.length < 2) return null;
      } else if (participants.length != 2 ||
          participants[0] == participants[1]) {
        return null;
      }
      return Conversation(
        id: doc.id,
        participants: participants,
        lastMessage: data['lastMessage'] as String? ?? '',
        lastSenderUid: data['lastSenderUid'] as String? ?? '',
        lastMessageId: data['lastMessageId'] as String? ?? '',
        updatedAt:
            _readTs(data['updatedAt'], pending: doc.metadata.hasPendingWrites),
        readAt: _tsMap(data['readAt']),
        deliveredAt: _tsMap(data['deliveredAt']),
        clearedAt: _tsMap(data['clearedAt']),
        pinned: _boolMap(data['pinned']),
        muted: _boolMap(data['muted']),
        mutedUntil: _tsMap(data['mutedUntil']),
        archived: _boolMap(data['archived']),
        archivedAt: _tsMap(data['archivedAt']),
        accepted: data['accepted'] as bool? ?? true,
        localUnread: localUnread,
        isGroup: group,
        groupName: data['groupName'] as String? ?? '',
        groupPhoto: data['groupPhoto'] as String? ?? '',
        createdBy: data['createdBy'] as String? ?? '',
        admins: List<String>.from(data['admins'] as List? ?? const []),
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
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderUid;
  final Map<String, String> reactions;

  /// عُدّلت الرسالة بعد إرسالها (يظهر وسم «معدّلة»).
  final bool edited;

  /// أُعيد توجيهها من محادثة أخرى (يظهر وسم «مُعاد توجيهه»).
  final bool forwarded;

  /// مشاركة غنية (بطاقة) داخل المحادثة: النوع (post/profile) والمعرّف.
  final String? shareType;
  final String? shareId;

  /// سطر وصفي تحت عنوان البطاقة (وصف المنشور أو نبذة الملف).
  final String? shareSubtitle;
  final String? shareImage;
  final String? shareLink;

  /// رابط الصورة عند استعمال Cloudinary/Storage (وضع التجربة يستعمل [imageBytes]).
  final String? imageUrl;

  /// موقع مُرسل (kind == 'location').
  final double? lat;
  final double? lng;

  /// صورة «تُعرض مرة واحدة» (view-once): تُخفى عن المستلم بعد أول فتح.
  final bool viewOnce;

  /// من فتح الصورة مرة الواحدة (يُضاف المستلم نفسه عند العرض).
  final List<String> viewedBy;

  /// وضع الاختفاء: وقت انتهاء صلاحية الرسالة؛ تُخفى بعده.
  final DateTime? expiresAt;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
    required this.deliveredTo,
    required this.readBy,
    required this.kind,
    required this.imageBytes,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderUid,
    this.reactions = const {},
    this.edited = false,
    this.forwarded = false,
    this.shareType,
    this.shareId,
    this.shareSubtitle,
    this.shareImage,
    this.shareLink,
    this.imageUrl,
    this.lat,
    this.lng,
    this.viewOnce = false,
    this.viewedBy = const [],
    this.expiresAt,
  });

  static ChatMessage? fromMap(
    String id,
    Map<String, dynamic> data, {
    bool pendingWrites = false,
  }) {
    try {
      return ChatMessage(
        id: id,
        senderUid: data['senderUid'] as String,
        text: data['text'] as String? ?? '',
        createdAt: _readTs(data['createdAt'], pending: pendingWrites),
        deliveredTo:
            List<String>.from(data['deliveredTo'] as List? ?? const []),
        readBy: List<String>.from(data['readBy'] as List? ?? const []),
        kind: data['kind'] as String? ?? 'text',
        imageBytes: (data['image'] as Blob?)?.bytes,
        imageUrl: data['imageUrl'] as String?,
        lat: (data['lat'] as num?)?.toDouble(),
        lng: (data['lng'] as num?)?.toDouble(),
        replyToMessageId: data['replyToMessageId'] as String?,
        replyToText: data['replyToText'] as String?,
        replyToSenderUid: data['replyToSenderUid'] as String?,
        edited: data.containsKey('editedAt'),
        forwarded: data['forwarded'] == true,
        shareType: data['shareType'] as String?,
        shareId: data['shareId'] as String?,
        shareSubtitle: data['shareSubtitle'] as String?,
        shareImage: data['shareImage'] as String?,
        shareLink: data['shareLink'] as String?,
        viewOnce: data['viewOnce'] == true,
        viewedBy: List<String>.from(data['viewedBy'] as List? ?? const []),
        expiresAt: data['expiresAt'] is Timestamp
            ? (data['expiresAt'] as Timestamp).toDate()
            : null,
        reactions: Map<String, String>.from(
          (data['reactions'] as Map?)?.map(
                (key, value) => MapEntry(key as String, value as String),
              ) ??
              const <String, String>{},
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// null إن كانت الرسالة تالفة (حقل ناقص أو بنوع خاطئ): تُتجاهل هي وحدها
  /// بدل أن يفشل تحميل المحادثة كلها.
  static ChatMessage? tryFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return fromMap(
      doc.id,
      doc.data(),
      pendingWrites: doc.metadata.hasPendingWrites,
    );
  }
}

/// رسالة محفوظة: نسخة من الرسالة + المحادثة التي جاءت منها (كإنستغرام).
class SavedMessage {
  final ChatMessage message;
  final String conversationId;
  final DateTime savedAt;

  const SavedMessage({
    required this.message,
    required this.conversationId,
    required this.savedAt,
  });

  static SavedMessage? tryFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final message = ChatMessage.fromMap(
        doc.id,
        data,
        pendingWrites: doc.metadata.hasPendingWrites,
      );
      if (message == null) return null;
      return SavedMessage(
        message: message,
        conversationId: data['conversationId'] as String? ?? '',
        savedAt:
            _readTs(data['savedAt'], pending: doc.metadata.hasPendingWrites),
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
  static StreamSubscription<String>? _pushTokenRefreshSub;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;
  static String get currentUid => _uid;
  static const _webPushVapidKey =
      String.fromEnvironment('FB_WEB_PUSH_VAPID_KEY');

  static Stream<RemoteMessage> get foregroundChatMessages =>
      FirebaseMessaging.onMessage;

  static Future<void> registerChatPushNotifications() async {
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken(
      vapidKey: kIsWeb && _webPushVapidKey.isNotEmpty ? _webPushVapidKey : null,
    );
    if (token != null && token.isNotEmpty) await _savePushToken(token);
    _pushTokenRefreshSub ??= messaging.onTokenRefresh.listen((freshToken) {
      _savePushToken(freshToken).catchError((Object _) {});
    });
  }

  /// عند تسجيل الخروج: يحذف توكن هذا الجهاز من حسابي ويُبطله، فلا تصل رسائل
  /// الحساب السابق لجهاز مشترك. تُستدعى قبل signOut (القواعد تتطلب الدخول).
  /// كل خطوة مستقلة، وأي فشل لا يمنع تسجيل الخروج.
  static Future<void> unregisterPushNotifications() async {
    final messaging = FirebaseMessaging.instance;
    await _pushTokenRefreshSub?.cancel();
    _pushTokenRefreshSub = null;
    String? token;
    try {
      token = await messaging
          .getToken(
            vapidKey:
                kIsWeb && _webPushVapidKey.isNotEmpty ? _webPushVapidKey : null,
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (token != null && token.isNotEmpty) {
      try {
        await _db
            .collection('users')
            .doc(_uid)
            .collection('pushTokens')
            .doc(token)
            .delete()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    try {
      await messaging.deleteToken().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> _savePushToken(String token) async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    await _db
        .collection('users')
        .doc(_uid)
        .collection('pushTokens')
        .doc(token)
        .set({
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  static TextDirection inferTextDirection(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return TextDirection.ltr;
    final rune = trimmed.runes.first;
    final isArabic = (rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F) ||
        (rune >= 0x08A0 && rune <= 0x08FF) ||
        (rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF);
    return isArabic ? TextDirection.rtl : TextDirection.ltr;
  }

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

  /// معرّفات من حظرتُهم (الأحدث أولاً).
  static Stream<List<String>> blockedUserIds() => _db
      .collection('userBlocks')
      .doc(_uid)
      .collection('blocked')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) doc.id]);

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
      // ملاحظتي الحالية (إن وُجدت) لا يجب أن يراها من حظرته. محاولة لا تُفشل الحظر.
      try {
        await _db.collection('notes').doc(_uid).update({
          'viewers': FieldValue.arrayRemove([otherUid]),
        });
      } catch (_) {}
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

  /// محادثات أُرسل لها «تم التسليم» في هذه الجلسة، حتى لا نكتب
  /// المستند نفسه عند كل تحديث لقائمة المحادثات.
  static final Set<String> _deliveredMarked = <String>{};

  /// محادثات علّمتها «غير مقروءة» يدوياً على هذا الجهاز (كإنستغرام: لا تُزامن
  /// على السيرفر ولا تمسّ إيصالات القراءة).
  static final Set<String> _manualUnread = <String>{};

  /// يُبَث عند تغيّر [_manualUnread] لإعادة بناء القوائم دون كتابة على السيرفر.
  static final StreamController<void> _unreadChanges =
      StreamController<void>.broadcast();

  /// هل علّمتُ المحادثة «غير مقروءة» يدوياً؟
  static bool isManuallyUnread(String conversationId) =>
      _manualUnread.contains(conversationId);

  /// تعليم محادثة «غير مقروءة» أو إلغاء ذلك (محلياً على هذا الجهاز فقط).
  static void setChatUnread(String conversationId, bool unread) {
    final changed = unread
        ? _manualUnread.add(conversationId)
        : _manualUnread.remove(conversationId);
    if (changed) _unreadChanges.add(null);
  }

  static Stream<List<Conversation>> conversations() {
    // ندمج تغيّرات «غير المقروء» المحلية مع لقطة Firestore، فنعيد الإصدار
    // الأخيرة عند كل تغيير محلي (بلا قراءة أو كتابة إضافية).
    final controller = StreamController<List<Conversation>>();
    QuerySnapshot<Map<String, dynamic>>? latest;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? source;
    StreamSubscription<void>? local;

    void emit() {
      final snapshot = latest;
      if (snapshot == null || controller.isClosed) return;
      controller.add(_mapConversations(snapshot));
    }

    controller.onListen = () {
      source = _chats
          .where('participants', arrayContains: _uid)
          .snapshots()
          .listen((snapshot) {
        latest = snapshot;
        emit();
      }, onError: controller.addError);
      local = _unreadChanges.stream.listen((_) => emit());
    };
    controller.onCancel = () async {
      await source?.cancel();
      await local?.cancel();
    };
    return controller.stream;
  }

  /// يحوّل لقطة المحادثات إلى نماذج مرتّبة ويعلّم «تم التسليم» لمن يحتاج.
  static List<Conversation> _mapConversations(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final items = snapshot.docs
        .map((doc) => Conversation.tryFromDoc(
              doc,
              localUnread: _manualUnread.contains(doc.id),
            ))
        .whereType<Conversation>()
        .toList()
      ..sort((a, b) {
        // المحادثات المثبتة أولاً، ثم الأحدث.
        final aPinned = a.pinnedFor(_uid);
        final bPinned = b.pinnedFor(_uid);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    for (final conversation in items) {
      if (conversation.lastSenderUid != _uid &&
          conversation.lastMessageId.isNotEmpty) {
        final delivered = conversation.deliveredAt[_uid];
        if (delivered != null && !conversation.updatedAt.isAfter(delivered)) {
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
  }

  /// عدد الرسائل الواردة منذ [since] (تجميع count رخيص، بلا قراءة الرسائل).
  /// عند تمرير [fromUid] نحصر العدّ على رسائل الطرف الآخر (دردشة فردية).
  /// يُستعمل لشارة «غير المقروء» الرقمية في قائمة المحادثات.
  static Future<int> unreadMessageCount(
    String conversationId,
    DateTime since, {
    String? fromUid,
  }) {
    Query<Map<String, dynamic>> query = _chats
        .doc(conversationId)
        .collection('messages')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since));
    if (fromUid != null && fromUid.isNotEmpty) {
      query = query.where('senderUid', isEqualTo: fromUid);
    }
    return query.count().get().then((result) => result.count ?? 0);
  }

  /// عدد المحادثات التي فيها رسالة غير مقروءة (لشارة تبويب الرسائل، كإنستغرام).
  /// تستثني المؤرشفة (لها صفّها المستقل) وتشمل طلبات الرسائل غير المقروءة.
  static Stream<int> unreadChatCount() => conversations().map((items) => items
      .where((conversation) =>
          conversation.visibleFor(_uid) &&
          !conversation.archivedFor(_uid) &&
          conversation.unreadFor(_uid))
      .length);

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
    final base =
        _chats.doc(conversationId).collection('messages').orderBy('createdAt');
    final query = since == null
        ? base.limitToLast(limit)
        : base.where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    return query.snapshots().map((snapshot) => snapshot.docs
        .map(ChatMessage.tryFromDoc)
        .whereType<ChatMessage>()
        .toList());
  }

  static Future<List<ChatMessage>> searchMessages(
    String conversationId,
    String query,
  ) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];

    final collection = _chats.doc(conversationId).collection('messages');
    final matches = <ChatMessage>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> pageQuery =
          collection.orderBy('createdAt', descending: true).limit(80);
      if (cursor != null) pageQuery = pageQuery.startAfterDocument(cursor);
      final page = await pageQuery.get();
      for (final document in page.docs) {
        final message = ChatMessage.tryFromDoc(document);
        if (message != null && message.text.toLowerCase().contains(term)) {
          matches.add(message);
        }
      }
      if (page.docs.length < 80) break;
      cursor = page.docs.last;
    }
    return matches;
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
            isLessThanOrEqualTo:
                Timestamp.fromDate(before.add(const Duration(milliseconds: 1))))
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

  /// قبول طلب رسالة: يجعل المحادثة مقبولة بلا إرسال رسالة (كإنستغرام)، متاح
  /// فقط لمن وصلته رسالة الطرف الآخر ولم يردّ بعد.
  static Future<void> acceptChatRequest(String conversationId) {
    return _chats.doc(conversationId).update({'accepted': true});
  }

  /// الحد الأقصى لعدد المحادثات المثبّتة (كإنستغرام).
  static const int maxPinnedChats = 3;

  /// تثبيت المحادثة (أو إلغاء تثبيتها) لديّ فقط.
  static Future<void> setChatPinned(String conversationId, bool pinned) async {
    if (pinned) {
      final snapshot = await _chats.doc(conversationId).get();
      final current = _boolMap(snapshot.data()?['pinned']);
      final count = current.values.where((value) => value).length;
      if (current[_uid] != true && count >= maxPinnedChats) {
        throw StateError(tr('يمكنك تثبيت 3 محادثات فقط'));
      }
    }
    await _chats.doc(conversationId).update({'pinned.$_uid': pinned});
  }

  /// كتم المحادثة لديّ فقط: حتى وقت محدد، أو حتى إعادة التشغيل (بلا وقت).
  /// لا إشعار دفع لرسائلها.
  static Future<void> setChatMuted(
    String conversationId, {
    required bool muted,
    DateTime? until,
  }) {
    final forever = muted && until == null;
    final expiry =
        muted && until != null ? until : DateTime.fromMillisecondsSinceEpoch(0);
    return _chats.doc(conversationId).update({
      'muted.$_uid': forever,
      'mutedUntil.$_uid': Timestamp.fromDate(expiry),
    });
  }

  /// أرشفة المحادثة لديّ (أو إلغاء أرشفتها): تخفيها من الصندوق، وتعود تلقائياً
  /// عند وصول رسالة جديدة (بفضل archivedAt مقابل updatedAt).
  static Future<void> setChatArchived(String conversationId, bool archived) {
    return _chats.doc(conversationId).update({
      'archived.$_uid': archived,
      'archivedAt.$_uid': FieldValue.serverTimestamp(),
    });
  }

  /// تثبيت رسالة داخل المحادثة (أو إلغاء تثبيتها بتمرير null): تظهر للطرفين.
  static Future<void> setPinnedMessage(
      String conversationId, String? messageId) {
    return _chats
        .doc(conversationId)
        .update({'pinnedMessageId': messageId ?? ''});
  }

  /// صور المحادثة (الأحدث أولاً) لشبكة الوسائط المشتركة في تفاصيل المحادثة.
  static Future<List<ChatMessage>> chatImages(String conversationId,
      {int limit = 30}) async {
    final snapshot = await _chats
        .doc(conversationId)
        .collection('messages')
        .where('kind', isEqualTo: 'image')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map(ChatMessage.tryFromDoc)
        .whereType<ChatMessage>()
        .toList();
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

  // ===== المحادثات الجماعية =====

  /// ثوابت حدود المجموعة (مطابقة لقواعد Firestore).
  static const groupNameMax = 60;
  static const groupMembersMax = 250;

  /// ينشئ مجموعة باسم [name] وعضوين على الأقل غيري من [memberUids]، ويعيد
  /// معرّف المحادثة. المنشئ مشرف، والمجموعة مقبولة دائماً (لا طلب رسالة).
  static Future<String> createGroup({
    required String name,
    required List<String> memberUids,
    String? photoUrl,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > groupNameMax) {
      throw ArgumentError(tr('اسم المجموعة غير صالح'));
    }
    final members = <String>{_uid, ...memberUids}
        .where((uid) => uid.isNotEmpty)
        .toList()
      ..sort();
    if (members.length < 3) {
      throw ArgumentError(tr('المجموعة تحتاج عضوين على الأقل معك'));
    }
    if (members.length > groupMembersMax) {
      throw ArgumentError(tr('عدد أعضاء المجموعة كبير'));
    }
    final photo = (photoUrl ?? '').trim();
    final reference = _chats.doc();
    await reference.set({
      'participants': members,
      'isGroup': true,
      'groupName': cleanName,
      if (photo.isNotEmpty) 'groupPhoto': photo,
      'createdBy': _uid,
      'admins': [_uid],
      'lastMessage': '',
      'lastSenderUid': '',
      'lastMessageId': '',
      'accepted': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  /// يضيف أعضاء إلى مجموعة (المشرف فقط حسب القواعد).
  static Future<void> addGroupMembers(
      String conversationId, List<String> uids) async {
    final clean = uids.where((uid) => uid.isNotEmpty && uid != _uid).toList();
    if (clean.isEmpty) return;
    await _chats.doc(conversationId).update({
      'participants': FieldValue.arrayUnion(clean),
    });
  }

  /// يزيل عضواً من المجموعة (المشرف فقط، ولا يمكن إزالة المنشئ).
  static Future<void> removeGroupMember(
      String conversationId, String uid) async {
    if (uid == _uid) return leaveGroup(conversationId);
    await _chats.doc(conversationId).update({
      'participants': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
    });
  }

  /// يغادر المجموعة (يبقى المنشئ؛ إن غادر وحده تُهمَل المجموعة).
  static Future<void> leaveGroup(String conversationId) {
    return _chats.doc(conversationId).update({
      'participants': FieldValue.arrayRemove([_uid]),
      'admins': FieldValue.arrayRemove([_uid]),
    });
  }

  static Future<void> setGroupName(String conversationId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > groupNameMax) {
      throw ArgumentError(tr('اسم المجموعة غير صالح'));
    }
    await _chats.doc(conversationId).update({'groupName': clean});
  }

  static Future<void> setGroupPhoto(String conversationId, String photoUrl) {
    return _chats.doc(conversationId).update({'groupPhoto': photoUrl.trim()});
  }

  /// يرقّي/يعزل مشرفاً (المشرف فقط).
  static Future<void> setGroupAdmin(
      String conversationId, String uid, bool admin) {
    return _chats.doc(conversationId).update({
      'admins':
          admin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> sendMessage(
    String conversationId,
    String text, {
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderUid,
    DateTime? expiresAt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw ArgumentError(tr('يجب أن تكون الرسالة بين حرف واحد و2000 حرف'));
    }
    await _sendChatMessage(
      conversationId,
      text: trimmed,
      kind: 'text',
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderUid: replyToSenderUid,
      expiresAt: expiresAt,
    );
  }

  static Future<void> sendSticker(
    String conversationId,
    String sticker, {
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderUid,
    DateTime? expiresAt,
  }) async {
    if (sticker.isEmpty || sticker.length > 24) {
      throw ArgumentError.value(sticker, 'sticker', tr('ملصق غير صالح'));
    }
    await _sendChatMessage(
      conversationId,
      text: sticker,
      kind: 'sticker',
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderUid: replyToSenderUid,
      expiresAt: expiresAt,
    );
  }

  static Future<void> sendImage(
    String conversationId,
    Uint8List imageBytes, {
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderUid,
    bool viewOnce = false,
    DateTime? expiresAt,
  }) async {
    // مع Cloudinary/Storage تُرفع الصورة وتُحفظ بالرابط فقط، فيمكن أن تكون
    // أكبر وأوضح؛ وضع التجربة (داخل المستند) يبقى بحد 700 كيلوبايت.
    final maxBytes = PostService.useRemoteMedia ? 4 * 1024 * 1024 : 700 * 1024;
    if (imageBytes.isEmpty || imageBytes.length > maxBytes) {
      throw ArgumentError(PostService.useRemoteMedia
          ? tr('حجم الصورة كبير جداً')
          : tr('حجم الصورة يجب ألا يتجاوز 700 كيلوبايت'));
    }
    final url = await PostService.uploadChatImage(imageBytes);
    await _sendChatMessage(
      conversationId,
      text: tr('📷 صورة'),
      kind: 'image',
      imageBytes: url == null ? imageBytes : null,
      imageUrl: url,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderUid: replyToSenderUid,
      viewOnce: viewOnce,
      expiresAt: expiresAt,
    );
  }

  /// يسجّل أن المستلم فتح صورة «تُعرض مرة واحدة» (يُخفى المحتوى بعدها لديه).
  /// يُحدَّث التسليم/القراءة معه ليبقى الطلب صالحاً وفق القواعد.
  static Future<void> markMessageViewed(
      String conversationId, String messageId) async {
    await _chats
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'viewedBy': FieldValue.arrayUnion([_uid]),
      'deliveredTo': FieldValue.arrayUnion([_uid]),
      'readBy': FieldValue.arrayUnion([_uid]),
    });
  }

  /// إعادة توجيه رسالة (نص / صورة / ملصق / موقع) إلى محادثة أخرى كما هي،
  /// موسومة بـ«مُعاد توجيهه». الصورة تُعاد برابطها نفسه بلا رفع جديد.
  static Future<void> forwardMessage(
      String conversationId, ChatMessage message) async {
    if (message.kind == 'image') {
      final url = message.imageUrl;
      final bytes = message.imageBytes;
      if (url == null && bytes == null) {
        throw StateError(tr('لا يمكن إعادة توجيه هذه الرسالة'));
      }
      await _sendChatMessage(
        conversationId,
        text: tr('📷 صورة'),
        kind: 'image',
        imageUrl: url,
        imageBytes: url == null ? bytes : null,
        forwarded: true,
      );
      return;
    }
    if (message.kind == 'location') {
      final lat = message.lat;
      final lng = message.lng;
      if (lat == null || lng == null) {
        throw StateError(tr('لا يمكن إعادة توجيه هذه الرسالة'));
      }
      final label = message.text.trim();
      await _sendChatMessage(
        conversationId,
        text: label.isEmpty || label.length > 200 ? tr('📍 موقع') : label,
        kind: 'location',
        lat: lat,
        lng: lng,
        forwarded: true,
      );
      return;
    }
    final text = message.text.trim();
    if ((message.kind != 'text' && message.kind != 'sticker') ||
        text.isEmpty ||
        text.length > 2000) {
      throw StateError(tr('لا يمكن إعادة توجيه هذه الرسالة'));
    }
    await _sendChatMessage(
      conversationId,
      text: text,
      kind: message.kind,
      forwarded: true,
    );
  }

  /// مشاركة غنية داخل المحادثة: منشور أو ملف شخصي كبطاقة قابلة للنقر.
  /// [title] هو نص البطاقة (يُستعمل أيضاً كمعاينة في قائمة المحادثات).
  static Future<void> sendShare(
    String conversationId, {
    required String type,
    String? id,
    required String title,
    String? subtitle,
    String? image,
    String? link,
  }) async {
    if (type != 'post' && type != 'profile' && type != 'story') {
      throw ArgumentError.value(type, 'type', tr('نوع مشاركة غير صالح'));
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 200) {
      throw ArgumentError(tr('عنوان المشاركة غير صالح'));
    }
    String? clean(String? value, int max) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty || trimmed.length > max ? null : trimmed;
    }

    await _sendChatMessage(
      conversationId,
      text: cleanTitle,
      kind: 'share',
      shareType: type,
      shareId: clean(id, 128),
      shareSubtitle: clean(subtitle, 1000),
      shareImage: clean(image, 1000),
      shareLink: clean(link, 1000),
    );
  }

  /// ردّ أو تفاعل على قصة، يصل كبطاقة مرتبطة بالقصة (صورة مصغّرة + فتحها بالنقر)
  /// بدل نص عادي. النص الأطول من 200 حرف يُرسل كرسالة نصية عادية.
  static Future<void> sendStoryReply(
    String conversationId,
    Post story,
    String text,
  ) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (clean.length > 200) {
      await sendMessage(conversationId, trf('ردّ على القصة: {0}', [clean]));
      return;
    }
    final caption = story.caption.trim();
    await sendShare(
      conversationId,
      type: 'story',
      id: story.id,
      title: clean,
      subtitle: caption.isEmpty
          ? null
          : (caption.length > 100 ? caption.substring(0, 100) : caption),
      image: story.mediaUrl,
    );
  }

  /// إرسال موقعي الحالي كبطاقة (كإنستغرام). [label] اسمها الظاهر إن وُجد.
  static Future<void> sendLocation(
    String conversationId, {
    required double lat,
    required double lng,
    String? label,
  }) async {
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw ArgumentError(tr('موقع غير صالح'));
    }
    final clean = (label ?? '').trim();
    await _sendChatMessage(
      conversationId,
      text: clean.isEmpty || clean.length > 200 ? tr('📍 موقع') : clean,
      kind: 'location',
      lat: lat,
      lng: lng,
    );
  }

  // ===== الرسائل المحفوظة (Saved) =====
  static CollectionReference<Map<String, dynamic>> _savedMessages() =>
      _db.collection('users').doc(_uid).collection('savedMessages');

  /// معرّفات الرسائل المحفوظة (لعرض «حفظ» أو «إلغاء الحفظ»).
  static Stream<Set<String>> savedMessageIds() => _savedMessages()
      .snapshots()
      .map((snapshot) => {for (final doc in snapshot.docs) doc.id});

  /// المحفوظات (الأحدث حفظاً أولاً).
  static Stream<List<SavedMessage>> savedMessages() => _savedMessages()
      .orderBy('savedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(SavedMessage.tryFromDoc)
          .whereType<SavedMessage>()
          .toList());

  /// حفظ نسخة من الرسالة عندي (لا تُحذف بحذف الرسالة الأصلية).
  static Future<void> saveMessage(String conversationId, ChatMessage message) {
    return _savedMessages().doc(message.id).set({
      'conversationId': conversationId,
      'senderUid': message.senderUid,
      'text': message.text,
      'kind': message.kind,
      'createdAt': message.createdAt,
      'savedAt': FieldValue.serverTimestamp(),
      if (message.imageUrl != null) 'imageUrl': message.imageUrl,
      if (message.shareType != null) 'shareType': message.shareType,
      if (message.shareId != null) 'shareId': message.shareId,
      if (message.shareSubtitle != null) 'shareSubtitle': message.shareSubtitle,
      if (message.shareImage != null) 'shareImage': message.shareImage,
      if (message.shareLink != null) 'shareLink': message.shareLink,
      if (message.lat != null) 'lat': message.lat,
      if (message.lng != null) 'lng': message.lng,
    });
  }

  static Future<void> unsaveMessage(String messageId) =>
      _savedMessages().doc(messageId).delete();

  // ===== «حذف لديّ فقط»: معرّفات الرسائل المخفية عن المستخدم الحالي =====
  static DocumentReference<Map<String, dynamic>> _hiddenDoc(
          String conversationId) =>
      _chats.doc(conversationId).collection('hiddenMessages').doc(_uid);

  static Stream<Set<String>> hiddenMessageIds(String conversationId) =>
      _hiddenDoc(conversationId).snapshots().map(
            (snapshot) => Set<String>.from(
                (snapshot.data()?['ids'] as List?) ?? const []),
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

  static Future<void> setMessageReaction(
    String conversationId,
    String messageId,
    String? reaction,
  ) async {
    if (reaction != null && (reaction.isEmpty || reaction.runes.length > 8)) {
      throw ArgumentError.value(reaction, 'reaction', tr('تفاعل غير صالح'));
    }
    final field = 'reactions.$_uid';
    await _chats
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({field: reaction ?? FieldValue.delete()});
  }

  /// مدة السماح بتعديل الرسالة النصية بعد إرسالها. تطابق شرط
  /// `15, 'm'` في قواعد Firestore؛ غيّرهما معاً.
  static const messageEditWindow = Duration(minutes: 15);

  /// يعدّل نص رسالتي النصية (خلال [messageEditWindow] من إرسالها). إن كانت
  /// آخر رسالة في المحادثة يتغير معها نص المعاينة في قائمة المحادثات، دون
  /// تغيير updatedAt فلا تقفز المحادثة ولا تظهر «غير مقروءة».
  static Future<void> editMessage(
      String conversationId, String messageId, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw ArgumentError(tr('يجب أن تكون الرسالة بين حرف واحد و2000 حرف'));
    }
    final chat = _chats.doc(conversationId);
    final message = chat.collection('messages').doc(messageId);
    final snapshots = await Future.wait([chat.get(), message.get()]);
    final chatSnapshot = snapshots[0];
    final messageSnapshot = snapshots[1];
    final data = messageSnapshot.data();
    if (!chatSnapshot.exists || !messageSnapshot.exists || data == null) {
      throw StateError(tr('الرسالة غير موجودة'));
    }
    if (data['senderUid'] != _uid || (data['kind'] ?? 'text') != 'text') {
      throw StateError(tr('يمكنك تعديل رسائلك النصية فقط'));
    }
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp ||
        DateTime.now().difference(createdAt.toDate()) > messageEditWindow) {
      throw StateError(tr('انتهت مدة تعديل الرسالة'));
    }
    if ((data['text'] as String? ?? '') == trimmed) return;

    final batch = _db.batch();
    batch.update(message, {
      'text': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });
    if (chatSnapshot.data()?['lastMessageId'] == messageId) {
      batch.update(chat, {'lastMessage': trimmed});
    }
    await batch.commit();
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
      final previousMessages =
          recentMessages.docs.where((document) => document.id != messageId);
      final previous = previousMessages.isEmpty ? null : previousMessages.first;
      // يعود updatedAt إلى وقت الرسالة السابقة نفسه (Timestamp الخام بلا تحويل
      // إلى DateTime حتى لا تضيع الميكروثواني)، وإلا ظهرت المحادثة «غير مقروءة»
      // وقفزت لأعلى القائمة بعد الحذف. إن لم تبقَ رسائل يُستعمل وقت الخادم.
      final previousCreatedAt = previous?.data()['createdAt'];
      if (previous != null && previousCreatedAt is! Timestamp) {
        throw StateError(tr('تعذر حذف الرسالة الآن، حاول بعد لحظات'));
      }
      batch.update(chat, {
        'lastMessage': previous?.data()['text'] ?? '',
        'lastSenderUid': previous?.data()['senderUid'] ?? '',
        'lastMessageId': previous?.id ?? '',
        'updatedAt':
            previous == null ? FieldValue.serverTimestamp() : previousCreatedAt,
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
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderUid,
    bool forwarded = false,
    String? shareType,
    String? shareId,
    String? shareSubtitle,
    String? shareImage,
    String? shareLink,
    double? lat,
    double? lng,
    bool viewOnce = false,
    DateTime? expiresAt,
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
        final participants = List<String>.from(current['participants'] as List);
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
          if (forwarded) 'forwarded': true,
          if (viewOnce) 'viewOnce': true,
          if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
          if (shareType != null) 'shareType': shareType,
          if (shareId != null) 'shareId': shareId,
          if (shareSubtitle != null) 'shareSubtitle': shareSubtitle,
          if (shareImage != null) 'shareImage': shareImage,
          if (shareLink != null) 'shareLink': shareLink,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
          if (replyToText != null) 'replyToText': replyToText,
          if (replyToSenderUid != null) 'replyToSenderUid': replyToSenderUid,
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
        if (!c.isGroup && c.visibleFor(_uid)) c.otherParticipant(_uid),
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

  static Stream<Map<String, DateTime>> typingState(String conversationId) =>
      _chats.doc(conversationId).snapshots().map((snapshot) {
        final raw = snapshot.data()?['typing'];
        if (raw is! Map) return const <String, DateTime>{};
        final now = DateTime.now();
        final typing = <String, DateTime>{};
        for (final entry in raw.entries) {
          if (entry.key is! String || entry.value is! Timestamp) continue;
          final timestamp = entry.value.toDate();
          final delta = now.difference(timestamp).inSeconds;
          if (delta <= 8) {
            typing[entry.key as String] = timestamp;
          }
        }
        return typing;
      });

  /// يكتب/يمسح مدخلي فقط في خريطة typing بكتابة واحدة بلا قراءة مسبقة.
  /// الاستدعاء المتكرر مسؤولية الشاشة (تحديد المعدّل)، وتتجاهل القراءة
  /// المدخلات الأقدم من 8 ثوانٍ فلا يبقى «يكتب…» عالقاً إن لم يصل المسح.
  static Future<void> setTyping(String conversationId,
      {required bool isTyping}) {
    return _chats.doc(conversationId).update({
      'typing.$_uid':
          isTyping ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
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
                  ProfileVisit(
                      doc.id, (doc.data()['at'] as Timestamp).toDate()),
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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

import 'social_service.dart';
import 'user_service.dart';

import '../l10n.dart';
import '../share_links.dart';
import '../video_source.dart';

enum PostType { photo, text, story }

/// مستخدم مذكور داخل القصة.
class StoryMention {
  final String uid;
  final String username;
  const StoryMention({required this.uid, required this.username});

  Map<String, dynamic> toMap() => {'uid': uid, 'username': username};

  static List<StoryMention> listFrom(Object? v) {
    if (v is! List) return const [];
    final out = <StoryMention>[];
    for (final e in v) {
      if (e is Map && e['uid'] is String && e['username'] is String) {
        out.add(StoryMention(
            uid: e['uid'] as String, username: e['username'] as String));
      }
    }
    return out;
  }
}

/// صندوق أسئلة داخل القصة: عبارة (مثل «اسألني شيئاً») يجيب عنها المشاهدون.
/// موضع عنصر تفاعلي فوق القصة: [x] و[y] مركزه كنسبة (0..1) من عرض الوسائط
/// وارتفاعها، و[s] التكبير، و[ar] نسبة عرض الصورة إلى ارتفاعها (لحساب مكانها
/// في العارض). كلها اختيارية: القصص القديمة بدونها تبقى أسفل الشاشة.
double? _posNum(Object? v, double lo, double hi) =>
    v is num && v.isFinite ? v.toDouble().clamp(lo, hi).toDouble() : null;

double _r4(double v) => (v * 10000).round() / 10000;

Map<String, dynamic> _posToMap(double? x, double? y, double? s, double? ar) => {
      if (x != null && y != null) 'x': _r4(x),
      if (x != null && y != null) 'y': _r4(y),
      if (s != null) 's': _r4(s),
      if (ar != null) 'ar': _r4(ar),
    };

class StoryQuestion {
  final String q;
  final double? x, y, s, ar;
  const StoryQuestion({required this.q, this.x, this.y, this.s, this.ar});

  bool get placed => x != null && y != null;

  StoryQuestion withPos({double? x, double? y, double? s}) =>
      StoryQuestion(q: q, x: x ?? this.x, y: y ?? this.y, s: s ?? this.s, ar: ar);

  StoryQuestion withAspect(double? ar) =>
      StoryQuestion(q: q, x: x, y: y, s: s, ar: ar);

  /// نص جديد مع إبقاء موضع [old] (أو موضع افتراضي عند [defY]).
  StoryQuestion placedLike(StoryQuestion? old, double defY) => StoryQuestion(
      q: q, x: old?.x ?? 0.5, y: old?.y ?? defY, s: old?.s ?? 1, ar: old?.ar);

  Map<String, dynamic> toMap() => {'q': q, ..._posToMap(x, y, s, ar)};

  static StoryQuestion? fromMap(Object? m) {
    if (m is! Map) return null;
    final q = m['q'];
    if (q is String && q.isNotEmpty) {
      return StoryQuestion(
          q: q,
          x: _posNum(m['x'], 0, 1),
          y: _posNum(m['y'], 0, 1),
          s: _posNum(m['s'], 0.3, 3),
          ar: _posNum(m['ar'], 0.1, 10));
    }
    return null;
  }
}

/// شريط إيموجي داخل القصة: سؤال اختياري وإيموجي يسحبه المشاهد (0 إلى 100).
class StorySlider {
  final String q;
  final String e;
  final double? x, y, s, ar;
  const StorySlider(
      {required this.q, required this.e, this.x, this.y, this.s, this.ar});

  bool get placed => x != null && y != null;

  StorySlider withPos({double? x, double? y, double? s}) => StorySlider(
      q: q, e: e, x: x ?? this.x, y: y ?? this.y, s: s ?? this.s, ar: ar);

  StorySlider withAspect(double? ar) =>
      StorySlider(q: q, e: e, x: x, y: y, s: s, ar: ar);

  StorySlider placedLike(StorySlider? old, double defY) => StorySlider(
      q: q,
      e: e,
      x: old?.x ?? 0.5,
      y: old?.y ?? defY,
      s: old?.s ?? 1,
      ar: old?.ar);

  Map<String, dynamic> toMap() => {'q': q, 'e': e, ..._posToMap(x, y, s, ar)};

  static StorySlider? fromMap(Object? m) {
    if (m is! Map) return null;
    final q = m['q'];
    final e = m['e'];
    if (q is String && e is String && e.isNotEmpty) {
      return StorySlider(
          q: q,
          e: e,
          x: _posNum(m['x'], 0, 1),
          y: _posNum(m['y'], 0, 1),
          s: _posNum(m['s'], 0.3, 3),
          ar: _posNum(m['ar'], 0.1, 10));
    }
    return null;
  }
}

/// معلومات مضافة للقصة: رابط، موقع، عدّ تنازلي، ملصق وقت. كلها اختيارية.
class StoryInfo {
  String? linkUrl;
  String? linkLabel;
  String? location;
  String? countdownTitle;
  int? countdownAt; // بالميلي ثانية (UTC)
  int? timeMode; // 0 الساعة، 1 التاريخ، 2 الاثنان

  StoryInfo(
      {this.linkUrl,
      this.linkLabel,
      this.location,
      this.countdownTitle,
      this.countdownAt,
      this.timeMode});

  bool get isEmpty =>
      linkUrl == null &&
      location == null &&
      countdownAt == null &&
      timeMode == null;

  /// الحقول التي تُكتب مع مستند القصة.
  Map<String, dynamic> toExtra() => {
        if (linkUrl != null)
          'link': {'u': linkUrl, 'l': linkLabel ?? ''},
        if (location != null) 'location': {'n': location},
        if (countdownAt != null)
          'countdown': {'t': countdownTitle ?? '', 'at': countdownAt},
        if (timeMode != null) 'time': {'m': timeMode},
      };

  static StoryInfo? fromMap(Map<String, dynamic> m) {
    final info = StoryInfo();
    final l = m['link'];
    if (l is Map && l['u'] is String) {
      info.linkUrl = l['u'] as String;
      info.linkLabel = l['l'] is String ? l['l'] as String : '';
    }
    final loc = m['location'];
    if (loc is Map && loc['n'] is String) info.location = loc['n'] as String;
    final c = m['countdown'];
    if (c is Map && c['at'] is num) {
      info.countdownAt = (c['at'] as num).toInt();
      info.countdownTitle = c['t'] is String ? c['t'] as String : '';
    }
    final t = m['time'];
    if (t is Map && t['m'] is num) info.timeMode = (t['m'] as num).toInt();
    return info.isEmpty ? null : info;
  }
}

/// إجابة مشاهد على صندوق أسئلة القصة (يقرؤها صاحب القصة).
class StoryAnswer {
  final String uid;
  final String username;
  final String name;
  final String text;
  final DateTime at;
  const StoryAnswer(
      {required this.uid,
      required this.username,
      required this.name,
      required this.text,
      required this.at});
}

/// استطلاع داخل القصة: سؤال وخياران.
class StoryPoll {
  final String q;
  final String a;
  final String b;
  final double? x, y, s, ar;
  const StoryPoll(
      {required this.q,
      required this.a,
      required this.b,
      this.x,
      this.y,
      this.s,
      this.ar});

  bool get placed => x != null && y != null;

  StoryPoll withPos({double? x, double? y, double? s}) => StoryPoll(
      q: q,
      a: a,
      b: b,
      x: x ?? this.x,
      y: y ?? this.y,
      s: s ?? this.s,
      ar: ar);

  StoryPoll withAspect(double? ar) =>
      StoryPoll(q: q, a: a, b: b, x: x, y: y, s: s, ar: ar);

  StoryPoll placedLike(StoryPoll? old, double defY) => StoryPoll(
      q: q,
      a: a,
      b: b,
      x: old?.x ?? 0.5,
      y: old?.y ?? defY,
      s: old?.s ?? 1,
      ar: old?.ar);

  Map<String, dynamic> toMap() =>
      {'q': q, 'a': a, 'b': b, ..._posToMap(x, y, s, ar)};

  static StoryPoll? fromMap(Object? m) {
    if (m is! Map) return null;
    final q = m['q'];
    final a = m['a'];
    final b = m['b'];
    if (q is String && a is String && b is String && q.isNotEmpty) {
      return StoryPoll(
          q: q,
          a: a,
          b: b,
          x: _posNum(m['x'], 0, 1),
          y: _posNum(m['y'], 0, 1),
          s: _posNum(m['s'], 0.3, 3),
          ar: _posNum(m['ar'], 0.1, 10));
    }
    return null;
  }
}

class Post {
  final String id;
  final PostType type;
  final String uid;
  final String username;
  final String name;
  final String caption;
  final String? mediaUrl;
  final String? mediaId; // وضع التجربة: الملف مخزّن في Firestore على قطع
  final List<String> albumUrls; // ألبوم: روابط كل الصور (الأولى = mediaUrl)
  final String? videoId; // معرّف الفيديو على المنصة إن وُجد (يوتيوب: 11 حرفاً)
  final String? videoProvider; // المنصة (youtube وغيرها)؛ فارغ = يوتيوب (منشورات قديمة)
  final String? videoUrl; // الرابط الأصلي للمنصات غير يوتيوب
  final bool isShort; // فيديو عمودي (شورتز، ريلز، تيك توك)
  final int? bg; // قصة نصية: رقم الخلفية الملونة (فارغ = قصة صورة)
  final int? tbg; // منشور نصي: رقم الخلفية الملونة (فارغ = بلا خلفية)
  final int? tc; // منشور نصي: رقم لون النص (فارغ = اللون الافتراضي)
  final StoryPoll? poll; // استطلاع داخل القصة (اختياري)
  final StoryQuestion? question; // صندوق أسئلة داخل القصة (اختياري)
  final StorySlider? slider; // شريط إيموجي داخل القصة (اختياري)
  final StoryInfo? info; // رابط/موقع/عدّ تنازلي/وقت (اختياري)
  final List<StoryMention> mentions; // مستخدمون مذكورون في القصة
  final bool authorPrivate; // حساب صاحب المنشور خاص (تفرضه قواعد Firestore)
  final bool closeFriends; // قصة للأصدقاء المقربين فقط (مجموعة closeStories)
  final String? sharedFromUsername; // قصة مشاركة من منشور: صاحب الأصل
  final String? sharedFromUid;
  final String? repostedFromUid; // إعادة نشر: صاحب المنشور الأصلي
  final String? repostedFromUsername;
  final String? repostedFromPostId;
  final int chunks;
  final String mime;
  final int likes;
  final int views;
  final int comments;
  final int shares;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.type,
    required this.uid,
    required this.username,
    this.name = '',
    required this.caption,
    required this.mediaUrl,
    this.mediaId,
    this.albumUrls = const [],
    this.videoId,
    this.videoProvider,
    this.videoUrl,
    this.isShort = false,
    this.bg,
    this.tbg,
    this.tc,
    this.poll,
    this.question,
    this.slider,
    this.info,
    this.mentions = const [],
    this.authorPrivate = false,
    this.closeFriends = false,
    this.sharedFromUsername,
    this.sharedFromUid,
    this.repostedFromUid,
    this.repostedFromUsername,
    this.repostedFromPostId,
    this.chunks = 0,
    this.mime = 'image/jpeg',
    required this.likes,
    required this.views,
    this.comments = 0,
    this.shares = 0,
    required this.createdAt,
  });

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Post(
      id: d.id,
      type: PostType.values
          .firstWhere((t) => t.name == m['type'], orElse: () => PostType.text),
      uid: m['uid'] ?? '',
      username: m['username'] ?? tr('مستخدم'),
      name: m['name'] ?? '',
      caption: m['caption'] ?? '',
      mediaUrl: m['mediaUrl'],
      mediaId: m['mediaId'],
      albumUrls: (m['albumUrls'] is List)
          ? (m['albumUrls'] as List).whereType<String>().toList()
          : const <String>[],
      videoId: m['videoId'] as String?,
      videoProvider: m['videoProvider'] as String?,
      videoUrl: m['videoUrl'] as String?,
      isShort: m['isShort'] == true,
      bg: (m['bg'] as num?)?.toInt(),
      tbg: (m['tbg'] as num?)?.toInt(),
      tc: (m['tc'] as num?)?.toInt(),
      poll: StoryPoll.fromMap(m['poll']),
      question: StoryQuestion.fromMap(m['question']),
      slider: StorySlider.fromMap(m['slider']),
      info: StoryInfo.fromMap(m),
      mentions: StoryMention.listFrom(m['mentions']),
      authorPrivate: m['authorPrivate'] == true,
      closeFriends: m['closeFriends'] == true,
      sharedFromUsername: m['sharedFromUsername'] as String?,
      sharedFromUid: m['sharedFromUid'] as String?,
      repostedFromUid: m['repostedFromUid'] as String?,
      repostedFromUsername: m['repostedFromUsername'] as String?,
      repostedFromPostId: m['repostedFromPostId'] as String?,
      chunks: (m['chunks'] ?? 0) as int,
      mime: m['mime'] ?? 'image/jpeg',
      likes: (m['likes'] ?? 0) as int,
      views: (m['views'] ?? 0) as int,
      comments: (m['comments'] ?? 0) as int,
      shares: (m['shares'] ?? 0) as int,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// منشور فيديو قديم بقي في قاعدة البيانات (التطبيق لا يعرض الفيديو).
  static bool isLegacyVideo(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null) return false;
    return m['type'] == 'video' ||
        (m['mime'] is String && (m['mime'] as String).startsWith('video/'));
  }

  bool get hasVideo => videoId != null && videoId!.isNotEmpty;

  /// منشور ألبوم: أكثر من صورة في منشور واحد.
  bool get isAlbum => albumUrls.length > 1;

  /// روابط صور المنشور بالترتيب (صورة واحدة للمنشور العادي).
  List<String> get imageUrls =>
      isAlbum ? albumUrls : (mediaUrl != null ? [mediaUrl!] : const []);

  /// مصدر الفيديو (المنصة والمعرّف)، أو null إن لم يكن للمنشور فيديو صالح.
  VideoSource? get video => hasVideo
      ? VideoSource.fromStored(
          provider: videoProvider, id: videoId, url: videoUrl, isShort: isShort)
      : null;

  /// صورة الفيديو المصغّرة إن وفّرتها المنصة (لا تستهلك أي حصة من Firebase أو
  /// Cloudinary). null للمنصات التي ترسم غلافاً بدلها.
  String? get videoThumb => video?.thumbUrl;

  List<String> get hashtags => RegExp(r'#[\p{L}\p{N}_]+', unicode: true)
      .allMatches(caption)
      .map((m) => m.group(0)!)
      .toList();
}

/// دفعة من المنشورات مع مؤشر لمتابعة الجلب من بعدها.
class PostPage {
  final List<Post> posts;
  final DocumentSnapshot<Map<String, dynamic>>? cursor; // آخر مستند في الدفعة
  final bool hasMore;
  const PostPage(this.posts, this.cursor, this.hasMore);
}

/// علاقتي بحساب آخر: لا شيء، طلب متابعة معلّق (حساب خاص)، أو أتابعه.
enum FollowState { none, requested, following }

class PostService {
  /// false = وضع التجربة المجاني تماماً (الملفات داخل Firestore، بدون بطاقة).
  /// true  = Firebase Storage (يتطلب خطة Blaze). فعّله بـ --dart-define=USE_STORAGE=true
  static const useStorage = bool.fromEnvironment('USE_STORAGE');
  static const _chunkSize = 900 * 1024; // أقل من حد مستند Firestore (1MB)

  /// Cloudinary (مجاني): رفع غير موقّع عبر upload preset. يُفعَّل بتمرير
  /// --dart-define=CLOUDINARY_CLOUD_NAME=... --dart-define=CLOUDINARY_UPLOAD_PRESET=...
  /// وإن لم تُمرَّر القيمتان يعمل التطبيق كما كان (Firebase Storage أو Firestore).
  static const cloudinaryCloud = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const cloudinaryPreset =
      String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static bool get useCloudinary =>
      cloudinaryCloud.isNotEmpty && cloudinaryPreset.isNotEmpty;

  /// هل الوسائط تُخزَّن خارج Firestore (رابط مباشر)؟ تحدد حدود الحجم.
  static bool get useRemoteMedia => useCloudinary || useStorage;

  static bool isCloudinaryUrl(String url) =>
      url.startsWith('https://res.cloudinary.com/');

  /// رابط صورة مُحسَّن من Cloudinary (صيغة وجودة تلقائية وعرض محدد).
  /// الروابط الأخرى تُرجَع كما هي.
  static String optimizedImageUrl(String url, int width) {
    const marker = '/image/upload/';
    if (!isCloudinaryUrl(url) || !url.contains(marker)) return url;
    return url.replaceFirst(marker, '${marker}f_auto,q_auto,w_$width/');
  }
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static User get _user => FirebaseAuth.instance.currentUser!;

  static String get uidOrEmpty => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// زائر يتصفح بدون تسجيل دخول: قراءة فقط، وبقراءة واحدة بدل المتابعة اللحظية.
  static bool get isGuest => FirebaseAuth.instance.currentUser == null;

  static User get currentUser => _user;

  /// يزداد عند أي فعل يغيّر الأعداد (متابعة، إعجاب، نشر، حذف) فتعيد
  /// العدّادات في الملف الشخصي تحميل نفسها فوراً دون إعادة فتح الصفحة.
  static final statsTick = ValueNotifier<int>(0);
  static void notifyStatsChanged() => statsTick.value++;

  /// اسم المستخدم (@) الخاص بي.
  static String get username {
    final m = UserService.me;
    if (m != null && m.username.isNotEmpty) return m.username;
    if (isGuest) return '';
    final u = _user;
    return (u.displayName?.trim().isNotEmpty ?? false)
        ? u.displayName!
        : (u.email?.split('@').first ?? 'user');
  }

  static String get displayName => UserService.me?.displayName ?? username;

  static Query<Map<String, dynamic>> _byType(PostType t) => _db
      .collection('posts')
      .where('type', isEqualTo: t.name)
      .orderBy('createdAt', descending: true);

  /// هل الخطأ رفض صلاحية من قواعد Firestore (مثل منشور حساب خاص لا أتابعه)؟
  static bool _isDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  /// يقيّد استعلام المنشورات بكاتب واحد بشكل تقبله قواعد Firestore:
  /// - أنا: يكفي تقييد uid.
  /// - حساب عام: نضيف authorPrivate == false.
  /// - حساب خاص: بلا فلتر إضافي، وتسمح القواعد فقط إن كنت أتابعه.
  static Future<Query<Map<String, dynamic>>> _scopeToAuthor(
      Query<Map<String, dynamic>> q, String uid) async {
    q = q.where('uid', isEqualTo: uid);
    if (uid == uidOrEmpty) return q;
    final target = await UserService.profileOf(uid);
    return target?.isPrivate == true
        ? q
        : q.where('authorPrivate', isEqualTo: false);
  }

  /// بلا [uid]: منشورات الحسابات العامة فقط (القواعد ترفض الاستعلام بدون هذا الفلتر).
  /// مع [uid]: منشورات ذلك المستخدم إن كان لي حق رؤيتها.
  /// [since]: يعيد المنشورات الأحدث من هذا الوقت فقط (تستخدمه القصص كي لا
  /// تزاحم القصصُ المنتهية القصصَ الحيّة داخل حد [limit]). نفس الفهرس الحالي.
  static Stream<List<Post>> stream(PostType t,
      {String? uid, int limit = 40, DateTime? since}) {
    Query<Map<String, dynamic>> sinceOf(Query<Map<String, dynamic>> q) =>
        since == null
            ? q
            : q.where('createdAt', isGreaterThan: Timestamp.fromDate(since));
    if (uid == null) {
      final q = sinceOf(_byType(t).where('authorPrivate', isEqualTo: false))
          .limit(limit);
      if (isGuest) {
        return Stream.fromFuture(q.get().then((s) => _parse(s.docs)));
      }
      return q.snapshots().map((s) => _parse(s.docs));
    }
    return Stream.fromFuture(_scopeToAuthor(_byType(t), uid)).asyncExpand(
        (q) => sinceOf(q).limit(limit).snapshots().map((s) => _parse(s.docs)));
  }

  /// دفعة واحدة من منشورات الحسابات العامة بالأحدث، للتحميل عند التمرير.
  /// مرّر [after] (مؤشر الدفعة السابقة) لجلب ما بعدها. تستخدم فهرس
  /// authorPrivate + type + createdAt الموجود، فلا حاجة لفهرس جديد.
  /// مع [uids]: منشورات هذه الحسابات فقط (حتى 30، حد Firestore لـ whereIn).
  /// الحسابات الخاصة مستبعدة لأن القواعد لا تسمح باستعلام متعدد الحسابات عليها.
  static Future<PostPage> page(PostType t,
      {DocumentSnapshot<Map<String, dynamic>>? after,
      int limit = 15,
      List<String>? uids}) async {
    if (uids != null && uids.isEmpty) return const PostPage([], null, false);
    var q = _byType(t).where('authorPrivate', isEqualTo: false);
    if (uids != null) q = q.where('uid', whereIn: uids.take(30).toList());
    q = q.limit(limit);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    return PostPage(
      _parse(snap.docs),
      snap.docs.isEmpty ? after : snap.docs.last,
      snap.docs.length >= limit,
    );
  }

  /// دفعة من منشورات حساب واحد (خاص أتابعه أو عام). استعلام بحساب ثابت فتسمح
  /// القواعد به لأنني أتابعه. يستخدم فهرس type + uid + createdAt الموجود.
  static Future<PostPage> userPage(String uid,
      {DocumentSnapshot<Map<String, dynamic>>? after, int limit = 10}) async {
    var q = _db
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .where('type', whereIn: const ['photo', 'text'])
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    return PostPage(
      _parse(snap.docs),
      snap.docs.isEmpty ? after : snap.docs.last,
      snap.docs.length >= limit,
    );
  }

  // ---- «غير مهتم»: منشورات أخفيتها عن نفسي (تُحفظ في حسابي) ----
  static final hiddenIds = ValueNotifier<Set<String>>(<String>{});

  static CollectionReference<Map<String, dynamic>> get _hiddenRef =>
      _db.collection('users').doc(_user.uid).collection('hiddenPosts');

  /// يحمّل المخفيّات من حسابي. أي فشل (مثل قواعد لم تُنشر بعد) يُتجاهل.
  static Future<void> loadHiddenIds() async {
    if (isGuest) return;
    try {
      final snap = await _hiddenRef.get();
      hiddenIds.value = {...hiddenIds.value, ...snap.docs.map((d) => d.id)};
    } catch (_) {}
  }

  static Future<void> hidePost(String postId) async {
    hiddenIds.value = {...hiddenIds.value, postId};
    try {
      await _hiddenRef
          .doc(postId)
          .set({'at': FieldValue.serverTimestamp()});
    } catch (_) {
      hiddenIds.value = {...hiddenIds.value}..remove(postId);
      rethrow;
    }
  }

  static Future<void> unhidePost(String postId) async {
    hiddenIds.value = {...hiddenIds.value}..remove(postId);
    try {
      await _hiddenRef.doc(postId).delete();
    } catch (_) {}
  }

  /// يحوّل المستندات إلى منشورات ويتجاهل الفيديوهات القديمة.
  static List<Post> _parse(
          Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) =>
      [
        for (final d in docs)
          if (!Post.isLegacyVideo(d)) Post.fromDoc(d),
      ];

  static Stream<List<Post>> profilePosts(String uid, {int limit = 90}) =>
      Stream.fromFuture(_scopeToAuthor(
              _db
                  .collection('posts')
                  .where('type', whereIn: const ['photo', 'text'])
                  .orderBy('createdAt', descending: true),
              uid))
          .asyncExpand((q) => isGuest
              ? Stream.fromFuture(
                  q.limit(limit).get().then((s) => _parse(s.docs)))
              : q.limit(limit).snapshots().map((s) => _parse(s.docs)));

  static Future<List<Post>> search(String text) async {
    final snap = await _db
        .collection('posts')
        .where('authorPrivate', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    final all = _parse(snap.docs);
    final q = text.toLowerCase();
    return all
        .where((p) =>
            p.type != PostType.story &&
            (p.caption.toLowerCase().contains(q) ||
                p.username.toLowerCase().contains(q)))
        .toList();
  }

  // الاستكشاف: قراءة واحدة (30 منشوراً صور/نص عام) تغذّي الصور والفيديوهات
  // والهاشتاقات معاً، وتُخزَّن 5 دقائق في الذاكرة لتوفير قراءات Firebase.
  static const _trendingTtl = Duration(minutes: 5);
  static const _exploreReadLimit = 30;
  static DateTime? _exploreAt;
  static List<Post>? _exploreCache;
  static Future<List<Post>>? _exploreInflight;

  static bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < _trendingTtl;

  static Future<List<Post>> exploreFeed({bool force = false}) {
    if (!force && _fresh(_exploreAt) && _exploreCache != null) {
      return Future.value(_exploreCache!);
    }
    return _exploreInflight ??=
        _loadExplore().whenComplete(() => _exploreInflight = null);
  }

  static Future<List<Post>> _loadExplore() async {
    final snap = await _db
        .collection('posts')
        .where('authorPrivate', isEqualTo: false)
        .where('type', whereIn: const ['photo', 'text'])
        .orderBy('createdAt', descending: true)
        .limit(_exploreReadLimit)
        .get();
    _exploreCache = _parse(snap.docs);
    _exploreAt = DateTime.now();
    return _exploreCache!;
  }

  /// أكثر الهاشتاقات تكراراً في [posts] (القصص مستثناة).
  static Map<String, int> tagsOf(List<Post> posts) {
    final counts = <String, int>{};
    for (final post in posts) {
      if (post.type == PostType.story) continue;
      for (final t in post.hashtags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(15));
  }

  static Future<Map<String, int>> trendingTags({bool force = false}) async =>
      tagsOf(await exploreFeed(force: force));

  /// منشور بمعرّفه. يعيد null إن لم يوجد أو لم يكن لي حق رؤيته
  /// (القواعد ترفض قراءة منشور غير موجود أو منشور حساب خاص لا أتابعه).
  static Future<Post?> postById(String postId) async {
    try {
      final snapshot = await _db.collection('posts').doc(postId).get();
      if (!snapshot.exists || Post.isLegacyVideo(snapshot)) return null;
      return Post.fromDoc(snapshot);
    } on FirebaseException catch (e) {
      if (_isDenied(e)) return null;
      rethrow;
    }
  }

  /// يجلب قصة بمعرّفها (عامة أو أصدقاء مقرّبين) إن كانت ما زالت ضمن 24 ساعة
  /// ومسموحاً لي برؤيتها؛ وإلا يعيد null (منتهية/محذوفة/غير مسموحة).
  static Future<Post?> storyById(String storyId) async {
    try {
      final snapshot = await _db.collection(_colOf(storyId)).doc(storyId).get();
      if (!snapshot.exists) return null;
      final p = Post.fromDoc(snapshot);
      if (p.type != PostType.story) return null;
      if (p.createdAt.isBefore(_storyCutoff())) return null;
      return p;
    } on FirebaseException catch (e) {
      if (_isDenied(e)) return null;
      rethrow;
    }
  }

  static String postLink(Post post) => postLinkFor(post.id);

  /// رفع ملف إلى Storage مع تتبّع نسبة التقدم.
  static Future<String> _upload(Uint8List bytes, String path,
      String contentType, void Function(double)? onProgress) async {
    final ref = _storage.ref(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    await task;
    return ref.getDownloadURL();
  }

  /// يرفع الملف إلى Cloudinary ويعيد الرابط المباشر (https).
  /// ملاحظة: التقدم هنا ثنائي (يبدأ 0 وينتهي 1) لأن حزمة http لا تعطي تقدّم الرفع.
  static Future<String> _uploadCloudinary(
      Uint8List bytes, String mime, String ext) async {
    final fileExt = ext == 'quicktime' ? 'mov' : ext;
    final uri = Uri.https(
        'api.cloudinary.com', '/v1_1/$cloudinaryCloud/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = cloudinaryPreset
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: '${_stamp()}.$fileExt'));
    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> json = const {};
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}
    if (streamed.statusCode != 200) {
      final message = (json['error'] is Map ? json['error']['message'] : null) ??
          'HTTP ${streamed.statusCode}';
      throw StateError(trf('فشل الرفع إلى Cloudinary: {0}', [message]));
    }
    final url = json['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError(tr('لم يُرجع Cloudinary رابط الملف'));
    }
    return url;
  }

  /// يرفع صورة محادثة إلى Cloudinary أو Storage ويعيد رابطها المباشر.
  /// يعيد null في وضع التجربة (بلا تخزين خارجي)، فتُحفظ الصورة داخل المستند.
  static Future<String?> uploadChatImage(Uint8List bytes) async {
    if (useCloudinary) return _uploadCloudinary(bytes, 'image/jpeg', 'jpg');
    if (useStorage) {
      return _upload(bytes, 'photos/${_user.uid}/chat_${_stamp()}.jpg',
          'image/jpeg', null);
    }
    return null;
  }

  /// وضع التجربة: يقسّم الملف إلى قطع ويحفظها في مجموعة media.
  static Future<String> _storeInFirestore(
      Uint8List bytes, void Function(double)? onProgress) async {
    final id = _db.collection('media').doc().id;
    final n = (bytes.length / _chunkSize).ceil();
    for (var i = 0; i < n; i++) {
      final end = math.min(bytes.length, (i + 1) * _chunkSize);
      final part = Uint8List.sublistView(bytes, i * _chunkSize, end);
      await _db
          .collection('media')
          .doc('${id}_$i')
          .set({'uid': _user.uid, 'i': i, 'data': Blob(part)});
      onProgress?.call((i + 1) / n);
    }
    return id;
  }

  static final _bytesCache = <String, Future<Uint8List>>{};

  /// بايتات الملف المخزّن في Firestore (مع تخزين مؤقت في الذاكرة).
  static Future<Uint8List> mediaBytes(Post p) {
    return _bytesCache.putIfAbsent(p.mediaId!, () async {
      final docs = await Future.wait(List.generate(p.chunks,
          (i) => _db.collection('media').doc('${p.mediaId}_$i').get()));
      final b = BytesBuilder(copy: false);
      for (final d in docs) {
        b.add((d.data()!['data'] as Blob).bytes);
      }
      return b.toBytes();
    });
  }

  /// حالة خصوصية حسابي كما هي في الخادم (تُكتب على كل منشور جديد وتطابقها القواعد).
  static Future<bool> _myPrivacy() async {
    try {
      final s = await _db.collection('users').doc(_user.uid).get();
      return s.data()?['isPrivate'] == true;
    } catch (_) {
      return UserService.me?.isPrivate ?? false;
    }
  }

  static Future<void> _create(PostType type, String caption, String? url,
      {String? mediaId,
      int chunks = 0,
      String? mime,
      bool closeFriends = false,
      Map<String, dynamic> extra = const {}}) async {
    final data = <String, dynamic>{
      'type': type.name,
      'uid': _user.uid,
      'username': username,
      'name': displayName,
      'caption': caption,
      'mediaUrl': url,
      'mediaId': mediaId,
      'chunks': chunks,
      'mime': mime,
      'likes': 0,
      'views': 0,
      'comments': 0,
      'authorPrivate': await _myPrivacy(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    data.addAll(extra);
    if (type == PostType.story) {
      // وقت انتهاء القصة: سياسة TTL في Firestore تحذف المستند بعده تلقائياً
      // حتى لو لم يفتح صاحبها التطبيق (فعّلها من وحدة التحكم على الحقل expireAt).
      data['expireAt'] = Timestamp.fromDate(DateTime.now().add(storyLifetime));
    }
    if (closeFriends) {
      // قصة للأصدقاء المقربين: مجموعة منفصلة، وقائمة من يحق له رؤيتها وقت النشر.
      final allowed = await closeFriendIds();
      if (allowed.isEmpty) {
        throw StateError(tr('أضف أصدقاء مقربين أولاً'));
      }
      data['closeFriends'] = true;
      data['allowed'] = allowed;
      final id = '$_closeIdPrefix${_db.collection('closeStories').doc().id}';
      await _db.collection('closeStories').doc(id).set(data);
      notifyStatsChanged();
      return;
    }
    await _db.collection('posts').add(data);
    notifyStatsChanged();
  }

  /// يزامن authorPrivate على كل منشوراتي وقصصي مع إعداد الخصوصية الحالي.
  /// يُستدعى بعد تبديل خصوصية الحساب. الدفعات 10 مستندات فقط كي لا نتجاوز
  /// حد 20 عملية وصول لقواعد Firestore في الدفعة الواحدة.
  static Future<void> syncAuthorPrivacy(bool isPrivate) async {
    final snap = await _db
        .collection('posts')
        .where('uid', isEqualTo: _user.uid)
        .get();
    final stale = snap.docs
        .where((d) => d.data()['authorPrivate'] != isPrivate)
        .toList();
    for (var i = 0; i < stale.length; i += 10) {
      final batch = _db.batch();
      for (final d in stale.skip(i).take(10)) {
        batch.update(d.reference, {'authorPrivate': isPrivate});
      }
      await batch.commit();
    }
    if (stale.isNotEmpty) notifyStatsChanged();
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// يضيف صورة منشور إلى قصتي مع ذكر صاحبها. لا يعيد رفع الصورة: تشير القصة
  /// إلى الملف نفسه (رابط أو قطع Firestore).
  static Future<void> shareToStory(Post p) {
    if (p.authorPrivate && p.uid != _user.uid) {
      throw StateError(tr('لا يمكن مشاركة منشور من حساب خاص'));
    }
    final extra = {
      'sharedFromUid': p.uid,
      'sharedFromUsername': p.username,
      'sharedFromPostId': p.id,
    };
    if (p.hasVideo) {
      // الفيديو: تُنشر صورته المصغّرة كقصة مع ذكر صاحبه (إن وُجدت صورة للمنصة).
      final thumb = p.videoThumb;
      if (thumb == null) {
        throw StateError(tr('لا يمكن إضافة هذا الفيديو إلى القصة'));
      }
      return _create(PostType.story, '', thumb, mime: 'image/jpeg', extra: extra);
    }
    if (p.type != PostType.photo) {
      throw StateError(tr('يمكن إضافة الصور والفيديو فقط إلى القصة'));
    }
    return _create(PostType.story, '', p.mediaUrl,
        mediaId: p.mediaId, chunks: p.chunks, mime: p.mime, extra: extra);
  }

  // ---- إعادة النشر ----
  static Query<Map<String, dynamic>> _myRepostQuery(String originalId) => _db
      .collection('posts')
      .where('uid', isEqualTo: _user.uid)
      .where('repostedFromPostId', isEqualTo: originalId)
      .limit(1);

  /// هل أعدت نشر هذا المنشور؟ (يعمل أيضاً إن كان [p] نفسه إعادة نشر.)
  static Stream<bool> isReposted(Post p) => isGuest
      ? Stream.value(false)
      : _myRepostQuery(p.repostedFromPostId ?? p.id)
      .snapshots()
      .map((s) => s.docs.isNotEmpty);

  /// يعيد نشر المنشور في ملفي (نسخة تشير إلى الملف نفسه مع ذكر صاحبه)،
  /// وإن كنت أعدت نشره سابقاً يلغي إعادة النشر. يرجع true عند النشر.
  static Future<bool> toggleRepost(Post p) async {
    final originalId = p.repostedFromPostId ?? p.id;
    final originalUid = p.repostedFromUid ?? p.uid;
    final originalUsername = p.repostedFromUsername ?? p.username;
    final existing = await _myRepostQuery(originalId).get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.delete();
      notifyStatsChanged();
      return false;
    }
    if (originalUid == _user.uid) {
      throw StateError(tr('لا يمكنك إعادة نشر منشورك'));
    }
    if (p.authorPrivate) {
      throw StateError(tr('لا يمكن إعادة نشر منشور من حساب خاص'));
    }
    if (p.type == PostType.story) {
      throw StateError(tr('لا يمكن إعادة نشر القصص'));
    }
    await _create(p.type, p.caption, p.mediaUrl,
        mediaId: p.mediaId,
        chunks: p.chunks,
        mime: p.mime,
        extra: {
          if (p.hasVideo) 'videoId': p.videoId,
          if (p.hasVideo && p.videoProvider != null)
            'videoProvider': p.videoProvider,
          if (p.hasVideo && p.videoUrl != null) 'videoUrl': p.videoUrl,
          if (p.hasVideo && p.isShort) 'isShort': true,
          if (p.isAlbum) 'albumUrls': p.albumUrls,
          'repostedFromUid': originalUid,
          'repostedFromUsername': originalUsername,
          'repostedFromPostId': originalId,
        });
    return true;
  }

  /// ينشر وسائط (صورة/قصة). [mime] مثل image/jpeg.
  static Future<void> publishMedia(
    PostType type,
    Uint8List bytes, {
    required String mime,
    required String ext,
    required String caption,
    required void Function(double) onProgress,
    Map<String, dynamic> extra = const {},
    bool closeFriends = false,
  }) async {
    if (useCloudinary) {
      onProgress(0);
      final url = await _uploadCloudinary(bytes, mime, ext);
      onProgress(1);
      await _create(type, caption, url,
          mime: mime, extra: extra, closeFriends: closeFriends);
    } else if (useStorage) {
      final url = await _upload(
          bytes, 'photos/${_user.uid}/${_stamp()}.$ext', mime, onProgress);
      await _create(type, caption, url,
          mime: mime, extra: extra, closeFriends: closeFriends);
    } else {
      final id = await _storeInFirestore(bytes, onProgress);
      await _create(type, caption, null,
          mediaId: id,
          chunks: (bytes.length / _chunkSize).ceil(),
          mime: mime,
          extra: extra,
          closeFriends: closeFriends);
    }
  }

  /// أقصى عدد صور في ألبوم واحد.
  static const maxAlbumImages = 10;

  /// ينشر ألبوماً (عدة صور في منشور واحد). يتطلب تخزيناً بروابط مباشرة
  /// (Cloudinary أو Storage)؛ وضع التجربة (Firestore) لا يدعم الألبومات.
  static Future<void> publishAlbum(
    List<Uint8List> images, {
    required String mime,
    required String ext,
    required String caption,
    required void Function(double) onProgress,
  }) async {
    if (images.length < 2) {
      throw StateError(tr('الألبوم يحتاج صورتين على الأقل'));
    }
    if (images.length > maxAlbumImages) {
      throw StateError(trf('الحد الأقصى {0} صور', [maxAlbumImages]));
    }
    if (!useRemoteMedia) {
      throw StateError(tr('الألبومات تتطلب تفعيل Cloudinary أو Storage'));
    }
    final urls = <String>[];
    onProgress(0);
    for (var i = 0; i < images.length; i++) {
      final String url;
      if (useCloudinary) {
        url = await _uploadCloudinary(images[i], mime, ext);
      } else {
        url = await _upload(images[i],
            'photos/${_user.uid}/${_stamp()}_$i.$ext', mime, null);
      }
      urls.add(url);
      onProgress((i + 1) / images.length);
    }
    await _create(PostType.photo, caption, urls.first,
        mime: mime, extra: {'albumUrls': urls});
  }

  /// يستخرج معرّف الفيديو من أي صيغة رابط يوتيوب:
  /// watch?v= ، youtu.be ، shorts ، live ، embed ، /v/ ، m. ، music. ، youtube-nocookie.
  /// يعيد null إذا لم يكن الرابط يوتيوب صالحاً.
  static String? youtubeId(String input) {
    final v = VideoSource.parse(input);
    return v?.provider == VideoProvider.youtube ? v!.id : null;
  }

  /// هل الرابط رابط شورتز (youtube.com/shorts/ID)؟
  static bool isShortsLink(String input) {
    final v = VideoSource.parse(input);
    return v?.provider == VideoProvider.youtube && v!.isShort;
  }

  static String youtubeWatchUrl(String id) => VideoSource.youtubeWatch(id);

  /// منشور نصي، وقد يرافقه (أو يحلّ محلّه) فيديو يوتيوب.
  static Future<void> publishText(String text,
          {VideoSource? video, int? tbg, int? tc}) =>
      _create(PostType.text, text, null, extra: {
        if (tbg != null) 'tbg': tbg,
        if (tc != null) 'tc': tc,
        if (video != null) 'videoId': video.id,
        // يوتيوب بلا حقلي المنصة والرابط (متوافق مع المنشورات والقواعد القديمة).
        if (video != null && video.provider != VideoProvider.youtube) ...{
          'videoProvider': video.provider.name,
          'videoUrl': video.url,
        },
        if (video != null && video.isShort) 'isShort': true,
      });

  /// قصة نصية بخلفية ملونة (بدون صورة). [bg] رقم الخلفية من story_backgrounds.dart.
  static Future<void> publishTextStory(String text, int bg,
          {StoryPoll? poll,
          StoryQuestion? question,
          StorySlider? slider,
          StoryInfo? info,
          List<StoryMention> mentions = const [],
          bool closeFriends = false}) =>
      _create(PostType.story, text, null, closeFriends: closeFriends, extra: {
        'bg': bg,
        if (poll != null) 'poll': poll.toMap(),
        if (question != null) 'question': question.toMap(),
        if (slider != null) 'slider': slider.toMap(),
        if (info != null) ...info.toExtra(),
        if (mentions.isNotEmpty)
          'mentions': [for (final m in mentions) m.toMap()],
      });

  // ---- الإعجاب والحفظ والمتابعة ----
  static DocumentReference<Map<String, dynamic>> _likeRef(String postId) =>
      _db.collection('posts').doc(postId).collection('likes').doc(_user.uid);

  static Stream<bool> isLiked(String postId) => isGuest
      ? Stream.value(false)
      : _likeRef(postId).snapshots().map((s) => s.exists);

  /// عدد الإعجابات الحي للمنشور.
  static Stream<int> likeCount(String postId) {
    final ref = _db.collection('posts').doc(postId);
    int n(DocumentSnapshot<Map<String, dynamic>> s) =>
        ((s.data()?['likes'] ?? 0) as num).toInt();
    if (isGuest) return Stream.fromFuture(ref.get().then(n));
    return ref.snapshots().map(n);
  }

  // ---- مشاهدات القصص ----
  /// يسجّل أن المستخدم الحالي شاهد القصة (مرة واحدة لكل مستخدم). لا يسجّل لصاحبها.
  static Future<void> recordStoryView(Post story) async {
    if (isGuest || story.uid == _user.uid) return;
    await _db
        .collection(_colOf(story.id))
        .doc(story.id)
        .collection('views')
        .doc(_user.uid)
        // دمج: حتى لا تُمحى الإيموجي التي تفاعلتُ بها عند مشاهدة القصة مجدداً.
        .set({'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  /// يسجّل تفاعلي بإيموجي على القصة ليراه صاحبها في قائمة المشاهدين.
  /// (الرسالة الخاصة تُرسل منفصلة.) لا يسجّل لصاحب القصة.
  static Future<void> reactToStory(Post story, String emoji) async {
    if (isGuest || story.uid == _user.uid || emoji.isEmpty || emoji.length > 16) {
      return;
    }
    await _db
        .collection(_colOf(story.id))
        .doc(story.id)
        .collection('views')
        .doc(_user.uid)
        .set({'at': FieldValue.serverTimestamp(), 'e': emoji},
            SetOptions(merge: true));
  }

  // ---- استطلاع القصة ----
  /// يسجّل تصويتي (0 أو 1). مرة واحدة فقط؛ القواعد ترفض التعديل.
  static Future<void> votePoll(String postId, int choice) => _db
      .collection(_colOf(postId))
      .doc(postId)
      .collection('votes')
      .doc(_user.uid)
      .set({'choice': choice, 'at': FieldValue.serverTimestamp()});

  /// تصويتي في استطلاع القصة، أو null إن لم أصوّت.
  static Future<int?> myPollVote(String postId) async {
    if (isGuest) return null;
    final d = await _db
        .collection(_colOf(postId))
        .doc(postId)
        .collection('votes')
        .doc(_user.uid)
        .get();
    final c = d.data()?['choice'];
    return c is num ? c.toInt() : null;
  }

  /// عدد أصوات الخيارين [الأول، الثاني] (استعلام عدّ: قراءة واحدة لكل 1000 صوت).
  static Future<List<int>> pollCounts(String postId) async {
    final votes =
        _db.collection(_colOf(postId)).doc(postId).collection('votes');
    final r = await Future.wait([
      votes.where('choice', isEqualTo: 0).count().get(),
      votes.where('choice', isEqualTo: 1).count().get(),
    ]);
    return [r[0].count ?? 0, r[1].count ?? 0];
  }

  // ---- شريط إيموجي القصة ----
  /// يسجّل تقييمي (0 إلى 100). مرة واحدة فقط؛ القواعد ترفض التعديل.
  static Future<void> voteSlider(String storyId, int value) => _db
      .collection(_colOf(storyId))
      .doc(storyId)
      .collection('sliderVotes')
      .doc(_user.uid)
      .set({'v': value.clamp(0, 100), 'at': FieldValue.serverTimestamp()});

  /// تقييمي، أو null إن لم أقيّم.
  static Future<int?> mySliderVote(String storyId) async {
    if (isGuest) return null;
    final d = await _db
        .collection(_colOf(storyId))
        .doc(storyId)
        .collection('sliderVotes')
        .doc(_user.uid)
        .get();
    final v = d.data()?['v'];
    return v is num ? v.toInt() : null;
  }

  /// عدد المقيّمين ومتوسط تقييمهم (0 إلى 100) باستعلام تجميعي واحد.
  static Future<(int, double)> sliderStats(String storyId) async {
    final r = await _db
        .collection(_colOf(storyId))
        .doc(storyId)
        .collection('sliderVotes')
        .aggregate(count(), average('v'))
        .get();
    return (r.count ?? 0, r.getAverage('v') ?? 0.0);
  }

  // ---- صندوق أسئلة القصة ----
  static const maxAnswerLength = 200;

  /// يرسل إجابتي على صندوق الأسئلة. مرة واحدة فقط؛ القواعد ترفض التعديل.
  static Future<void> answerQuestion(String storyId, String text) {
    final clean = text.trim();
    if (clean.isEmpty) throw StateError(tr('اكتب إجابتك أولاً'));
    if (clean.length > maxAnswerLength) {
      throw StateError(tr('الإجابة طويلة جداً'));
    }
    return _db
        .collection(_colOf(storyId))
        .doc(storyId)
        .collection('answers')
        .doc(_user.uid)
        .set({
      'username': username,
      'name': displayName,
      'text': clean,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// هل أجبت سابقاً على صندوق أسئلة هذه القصة؟
  static Future<bool> hasAnswered(String storyId) async {
    if (isGuest) return false;
    final d = await _db
        .collection(_colOf(storyId))
        .doc(storyId)
        .collection('answers')
        .doc(_user.uid)
        .get();
    return d.exists;
  }

  /// عدد الإجابات (استعلام عدّ). يقرأه صاحب القصة.
  static Future<int> answerCount(String storyId) async {
    final r = await _db
        .collection(_colOf(storyId))
        .doc(storyId)
        .collection('answers')
        .count()
        .get();
    return r.count ?? 0;
  }

  /// إجابات قصتي (الأحدث أولاً). يقرؤها صاحب القصة فقط.
  static Stream<List<StoryAnswer>> storyAnswers(String storyId) => _db
      .collection(_colOf(storyId))
      .doc(storyId)
      .collection('answers')
      .orderBy('at', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              if (d.data()['at'] is Timestamp && d.data()['text'] is String)
                StoryAnswer(
                    uid: d.id,
                    username: (d.data()['username'] ?? '') as String,
                    name: (d.data()['name'] ?? '') as String,
                    text: d.data()['text'] as String,
                    at: (d.data()['at'] as Timestamp).toDate()),
          ]);

  /// من شاهدوا قصتي (الأحدث أولاً). يقرؤها صاحب القصة فقط.
  static Stream<List<StoryViewEntry>> storyViewers(String postId) => _db
      .collection(_colOf(postId))
      .doc(postId)
      .collection('views')
      .orderBy('at', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              if (d.data()['at'] is Timestamp)
                StoryViewEntry(
                    d.id,
                    (d.data()['at'] as Timestamp).toDate(),
                    d.data()['e'] is String &&
                            (d.data()['e'] as String).isNotEmpty
                        ? d.data()['e'] as String
                        : null),
          ]);

  static Future<void> toggleLike(String postId, bool liked) async {
    if (isCloseId(postId)) {
      throw StateError(tr('الإعجاب غير متاح لقصص الأصدقاء المقربين'));
    }
    final batch = _db.batch();
    final post = _db.collection('posts').doc(postId);
    DocumentSnapshot<Map<String, dynamic>> postSnapshot;
    try {
      postSnapshot = await post.get();
    } on FirebaseException catch (e) {
      if (_isDenied(e)) throw StateError(tr('المنشور غير متاح'));
      rethrow;
    }
    if (!postSnapshot.exists) {
      throw StateError(tr('المنشور غير موجود'));
    }
    final ownerUid = postSnapshot.data()?['uid'] as String?;
    // نسخة على ملف المستخدم لعرضها في تبويب الإعجابات.
    final likedRef =
        _db.collection('users').doc(_user.uid).collection('liked').doc(postId);
    if (liked) {
      batch.delete(_likeRef(postId));
      batch.delete(likedRef);
      batch.update(post, {'likes': FieldValue.increment(-1)});
    } else {
      batch.set(_likeRef(postId), {'at': FieldValue.serverTimestamp()});
      batch.set(likedRef, {'at': FieldValue.serverTimestamp()});
      batch.update(post, {'likes': FieldValue.increment(1)});
      if (ownerUid != null) {
        SocialService.addLikeNotification(
          batch: batch,
          recipientUid: ownerUid,
          actorUid: _user.uid,
          actorUsername: username,
          postId: postId,
        );
      }
    }
    await batch.commit();
    notifyStatsChanged();
  }

  static DocumentReference<Map<String, dynamic>> _saveRef(String postId) =>
      _db.collection('users').doc(_user.uid).collection('saved').doc(postId);

  static Stream<bool> isSaved(String postId) => isGuest
      ? Stream.value(false)
      : _saveRef(postId).snapshots().map((s) => s.exists);

  static Future<void> toggleSave(String postId, bool saved) => saved
      ? _saveRef(postId).delete()
      : _saveRef(postId).set({'at': FieldValue.serverTimestamp()});

  static Stream<bool> isFollowing(String targetUid) => isGuest
      ? Stream.value(false)
      : _db
      .collection('users')
      .doc(_user.uid)
      .collection('following')
      .doc(targetUid)
      .snapshots()
      .map((s) => s.exists);

  static DocumentReference<Map<String, dynamic>> _requestRef(
          String targetUid, String requesterUid) =>
      _db
          .collection('users')
          .doc(targetUid)
          .collection('followRequests')
          .doc(requesterUid);

  /// حالة علاقتي بحساب: لا شيء / طلب معلّق / أتابعه.
  static Stream<FollowState> followState(String targetUid) {
    if (isGuest) return Stream.value(FollowState.none);
    late final StreamController<FollowState> controller;
    StreamSubscription<bool>? followSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? requestSub;
    bool? following;
    bool? requested;

    void emitIfReady() {
      if (following == null || requested == null) return;
      controller.add(following!
          ? FollowState.following
          : requested!
              ? FollowState.requested
              : FollowState.none);
    }

    controller = StreamController<FollowState>(
      onListen: () {
        followSub = isFollowing(targetUid).listen((value) {
          following = value;
          emitIfReady();
        }, onError: controller.addError);
        requestSub = _requestRef(targetUid, _user.uid).snapshots().listen(
          (snapshot) {
            requested = snapshot.exists;
            emitIfReady();
          },
          onError: (Object error) {
            // قراءة الطلب غير ضرورية للمتابعة العامة: نتعامل معه كغير موجود.
            requested = false;
            emitIfReady();
          },
        );
      },
      onCancel: () async {
        await followSub?.cancel();
        await requestSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// متابعة حقيقية: حساب عام ← متابعة فورية، حساب خاص ← طلب ينتظر موافقة صاحبه.
  static Future<FollowState> follow(String targetUid) async {
    if (targetUid.isEmpty || targetUid == _user.uid) {
      throw ArgumentError.value(targetUid, 'targetUid', tr('مستخدم غير صالح'));
    }
    // قراءة طازجة من الخادم (دون التخزين المؤقت) لمعرفة هل الحساب خاص الآن.
    final target = await _db.collection('users').doc(targetUid).get();
    final isPrivate = target.data()?['isPrivate'] == true;
    final batch = _db.batch();
    if (isPrivate) {
      batch.set(_requestRef(targetUid, _user.uid),
          {'at': FieldValue.serverTimestamp()});
      SocialService.addFollowRequestNotification(
        batch: batch,
        recipientUid: targetUid,
        actorUid: _user.uid,
        actorUsername: username,
      );
      await batch.commit();
      return FollowState.requested;
    }
    batch.set(
        _db
            .collection('users')
            .doc(_user.uid)
            .collection('following')
            .doc(targetUid),
        {'at': FieldValue.serverTimestamp()});
    batch.set(
        _db
            .collection('users')
            .doc(targetUid)
            .collection('followers')
            .doc(_user.uid),
        {'at': FieldValue.serverTimestamp()});
    SocialService.addFollowNotification(
      batch: batch,
      recipientUid: targetUid,
      actorUid: _user.uid,
      actorUsername: username,
    );
    await batch.commit();
    notifyStatsChanged();
    return FollowState.following;
  }

  static Future<void> unfollow(String targetUid) async {
    final batch = _db.batch()
      ..delete(_db
          .collection('users')
          .doc(_user.uid)
          .collection('following')
          .doc(targetUid))
      ..delete(_db
          .collection('users')
          .doc(targetUid)
          .collection('followers')
          .doc(_user.uid));
    await batch.commit();
    notifyStatsChanged();
  }

  /// يلغي طلب متابعة أرسلته ولم يُقبل بعد.
  static Future<void> cancelFollowRequest(String targetUid) =>
      _requestRef(targetUid, _user.uid).delete();

  /// للتوافق: يتابع أو يلغي المتابعة حسب [following] (الحالة الحالية).
  static Future<void> toggleFollow(String targetUid, bool following) async {
    if (following) {
      await unfollow(targetUid);
    } else {
      await follow(targetUid);
    }
  }

  // ===== طلبات المتابعة الواردة إلى حسابي الخاص =====
  static Stream<List<String>> incomingFollowRequestIds() => isGuest
      ? Stream.value(const <String>[])
      : _db
      .collection('users')
      .doc(_user.uid)
      .collection('followRequests')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  static Stream<bool> hasIncomingRequest(String requesterUid) => isGuest
      ? Stream.value(false)
      : _requestRef(_user.uid, requesterUid).snapshots().map((s) => s.exists);

  static void _approveInto(WriteBatch batch, String requesterUid,
      {required bool notify}) {
    final me = _user.uid;
    batch.set(
        _db.collection('users').doc(me).collection('followers').doc(requesterUid),
        {'at': FieldValue.serverTimestamp()});
    batch.set(
        _db.collection('users').doc(requesterUid).collection('following').doc(me),
        {'at': FieldValue.serverTimestamp()});
    batch.delete(_requestRef(me, requesterUid));
    if (notify) {
      SocialService.addFollowAcceptedNotification(
        batch: batch,
        recipientUid: requesterUid,
        actorUid: me,
        actorUsername: username,
      );
    }
  }

  /// يقبل طلب متابعة: يصبح صاحب الطلب متابِعاً فعلياً ويصله إشعار بالقبول.
  static Future<void> approveFollowRequest(String requesterUid) async {
    final batch = _db.batch();
    _approveInto(batch, requesterUid, notify: true);
    await batch.commit();
    notifyStatsChanged();
  }

  /// يرفض طلب متابعة (يُحذف الطلب دون إشعار).
  static Future<void> declineFollowRequest(String requesterUid) =>
      _requestRef(_user.uid, requesterUid).delete();

  /// عند تحويل الحساب إلى عام: تُقبل كل الطلبات المعلّقة تلقائياً.
  static Future<void> approveAllFollowRequests() async {
    final snapshot = await _db
        .collection('users')
        .doc(_user.uid)
        .collection('followRequests')
        .get();
    final ids = snapshot.docs.map((d) => d.id).toList();
    // حد قواعد Firestore: 20 عملية وصول للدفعة، وكل قبول يستهلك 2.
    for (var i = 0; i < ids.length; i += 8) {
      final batch = _db.batch();
      for (final id in ids.skip(i).take(8)) {
        _approveInto(batch, id, notify: false);
      }
      await batch.commit();
    }
    if (ids.isNotEmpty) notifyStatsChanged();
  }

  static Stream<List<String>> followerIds(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('followers')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  static Future<int> countFollowers(String uid) async =>
      (await _db
              .collection('users')
              .doc(uid)
              .collection('followers')
              .count()
              .get())
          .count ??
      0;

  static Stream<List<String>> followingIds() => isGuest
      ? Stream.value(const <String>[])
      : _db
      .collection('users')
      .doc(_user.uid)
      .collection('following')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  static Future<int> countFollowing(String uid) async =>
      (await _db
              .collection('users')
              .doc(uid)
              .collection('following')
              .count()
              .get())
          .count ??
      0;

  /// عدد منشورات المستخدم (صور + نص، دون القصص). 0 إن كان حساباً خاصاً لا أتابعه.
  static Future<int> countPosts(String uid) async {
    try {
      final counts = await Future.wait(['photo', 'text'].map((t) async {
        final q = await _scopeToAuthor(
            _db.collection('posts').where('type', isEqualTo: t), uid);
        final snap = await q.count().get();
        return snap.count ?? 0;
      }));
      return counts.fold<int>(0, (a, b) => a + b);
    } on FirebaseException catch (e) {
      if (_isDenied(e)) return 0;
      rethrow;
    }
  }

  /// مجموع إعجابات منشورات المستخدم. يستعمل استعلام تجميع (قراءة واحدة تقريباً
  /// لكل 1000 منشور) وإن لم يتوفر يرجع للجمع اليدوي. 0 إن لم يحق لي رؤيتها.
  static Future<int> totalLikes(String uid) async {
    try {
      final query = await _scopeToAuthor(_db.collection('posts'), uid);
      try {
        final agg = await query.aggregate(sum('likes')).get();
        return (agg.getSum('likes') ?? 0).round();
      } catch (_) {
        final snap = await query.get();
        return snap.docs.fold<int>(
            0, (a, d) => a + ((d.data()['likes'] ?? 0) as num).toInt());
      }
    } on FirebaseException catch (e) {
      if (_isDenied(e)) return 0;
      rethrow;
    }
  }

  /// منشورات بمعرّفاتها (حتى 10)، بنفس ترتيب [ids]؛ المحذوفة أو غير المتاحة تُهمَل.
  /// قراءات منفردة لأن قواعد Firestore لا تقبل استعلام معرّفات على منشورات قد تكون خاصة.
  static Future<List<Post>> postsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final posts = await Future.wait(ids.take(10).map(postById));
    return [
      for (final p in posts)
        if (p != null) p,
    ];
  }

  // ---- منشور واحد، حذف ----
  static Stream<Post?> postStream(String id) => (isGuest
          ? Stream.fromFuture(_db.collection('posts').doc(id).get())
          : _db.collection('posts').doc(id).snapshots())
      .map<Post?>(
          (d) => d.exists && !Post.isLegacyVideo(d) ? Post.fromDoc(d) : null)
      .transform(StreamTransformer<Post?, Post?>.fromHandlers(
        handleError: (error, stack, sink) {
          // منشور لم يعد متاحاً لي (حُذف أو أصبح صاحبه خاصاً): نعامله كمحذوف.
          if (_isDenied(error)) {
            sink.add(null);
          } else {
            sink.addError(error, stack);
          }
        },
      ));

  /// تعديل نص المنشور/وصف الفيديو (للمالك فقط حسب قواعد Firestore).
  static Future<void> updateCaption(Post p, String caption) async {
    await _db.collection('posts').doc(p.id).update({'caption': caption});
  }

  /// تعديل منشور نصي: النص مع الخلفية ولون النص (null = إزالته).
  static Future<void> updateTextPost(Post p,
      {required String caption, int? tbg, int? tc}) async {
    await _db.collection('posts').doc(p.id).update({
      'caption': caption,
      'tbg': tbg ?? FieldValue.delete(),
      'tc': tc ?? FieldValue.delete(),
    });
  }

  /// إضافة صور لمنشور نصي: يتحوّل إلى منشور صورة (أو ألبوم) بالنص نفسه،
  /// وتُزال الخلفية ولون النص لأنهما للمنشور النصي فقط.
  static Future<void> convertTextToPhotoPost(
    Post p, {
    required String caption,
    required List<Uint8List> images,
    required String mime,
    required String ext,
    void Function(double)? onProgress,
  }) async {
    if (images.isEmpty) {
      throw StateError(tr('اختر صورة واحدة على الأقل'));
    }
    if (images.length > maxAlbumImages) {
      throw StateError(trf('الحد الأقصى {0} صور', [maxAlbumImages]));
    }
    if (!useRemoteMedia) {
      throw StateError(tr('إضافة الصور تتطلب تفعيل Cloudinary أو Storage'));
    }
    final urls = <String>[];
    onProgress?.call(0);
    for (var i = 0; i < images.length; i++) {
      final String url;
      if (useCloudinary) {
        url = await _uploadCloudinary(images[i], mime, ext);
      } else {
        url = await _upload(images[i],
            'photos/${_user.uid}/${_stamp()}_$i.$ext', mime, null);
      }
      urls.add(url);
      onProgress?.call((i + 1) / images.length);
    }
    await _db.collection('posts').doc(p.id).update({
      'type': PostType.photo.name,
      'caption': caption,
      'mediaUrl': urls.first,
      'mime': mime,
      if (urls.length > 1) 'albumUrls': urls,
      'tbg': FieldValue.delete(),
      'tc': FieldValue.delete(),
    });
    notifyStatsChanged();
  }

  static Future<void> deletePost(Post p) async {
    // إعادة النشر تشير إلى ملف الأصل، فلا نحذف ملفاته مع النسخة.
    // القصة المشاركة من منشور تشير إلى ملف المنشور الأصلي نفسه، فلا نحذفه معها.
    final sharesOriginalFile = p.sharedFromUid != null;
    if (p.type == PostType.story) {
      await _deleteStoryExtras(p.id);
    }
    if (isCloseId(p.id)) {
      // قصة أصدقاء مقربين: مجموعة منفصلة ولا ملفات مشتركة.
      await _db.collection('closeStories').doc(p.id).delete();
      notifyStatsChanged();
      return;
    }
    if (p.mediaId != null &&
        p.repostedFromPostId == null &&
        !sharesOriginalFile) {
      for (var i = 0; i < p.chunks; i++) {
        try {
          await _db.collection('media').doc('${p.mediaId}_$i').delete();
        } catch (_) {}
      }
    }
    await _db.collection('posts').doc(p.id).delete();
    // إن كان مثبّتاً أعلى الملف فأزل تثبيته.
    try {
      await _db.collection('users').doc(_user.uid).update({
        'pinnedPostIds': FieldValue.arrayRemove([p.id]),
      });
    } catch (_) {}
    notifyStatsChanged();
  }

  /// يحذف مشاهدات القصة وأصواتها وإعجاباتها قبل حذف القصة نفسها (القواعد تتحقق
  /// من صاحب القصة، فلا بد أن تسبق حذف المستند). أي فشل لا يوقف حذف القصة.
  static Future<void> _deleteStoryExtras(String storyId) async {
    for (final sub in const ['views', 'votes', 'sliderVotes', 'answers', 'likes']) {
      try {
        if (sub == 'likes' && isCloseId(storyId)) continue;
        final snap = await _db
            .collection(_colOf(storyId))
            .doc(storyId)
            .collection(sub)
            .limit(500)
            .get();
        for (var i = 0; i < snap.docs.length; i += 25) {
          await Future.wait([
            for (final d in snap.docs.skip(i).take(25))
              d.reference.delete().catchError((_) {}),
          ]);
        }
      } catch (_) {}
    }
  }

  // ---- المحفوظات ----
  static Stream<List<Post>> savedPosts() => isGuest
      ? Stream.value(const <Post>[])
      : _db
          .collection('users')
          .doc(_user.uid)
          .collection('saved')
          .orderBy('at', descending: true)
          .snapshots()
          .asyncMap((s) async {
        final posts = await Future.wait(s.docs.map((d) => postById(d.id)));
        return [
          for (final p in posts)
            if (p != null) p,
        ];
      });

  /// المنشورات (صور ونصوص) التي أعجب بها المستخدم [uid]، الأحدث أولاً.
  static Stream<List<Post>> likedPosts(String uid, {int limit = 60}) => _db
          .collection('users')
          .doc(uid)
          .collection('liked')
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .asyncMap((s) async {
        final posts = await Future.wait(s.docs.map((d) => postById(d.id)));
        return [
          for (final p in posts)
            if (p != null && p.type != PostType.story) p,
        ];
      });

  // ---- التعليقات ----
  static CollectionReference<Map<String, dynamic>> _commentsRef(
          String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  static Stream<List<Comment>> comments(String postId) {
    final q = _commentsRef(postId).orderBy('createdAt');
    return (isGuest ? Stream.fromFuture(q.get()) : q.snapshots())
        .map((s) => s.docs.map(Comment.fromDoc).toList());
  }

  /// يضيف تعليقاً (نصاً أو ملصقاً أو صورة). بلا قراءات مسبقة، فيظهر فوراً.
  /// [kind]: text | sticker | image.
  static Future<void> addComment(
    String postId,
    String text, {
    required String ownerUid,
    String kind = 'text',
    Uint8List? imageBytes,
    String? parentId,
    String? replyToUsername,
  }) async {
    if (imageBytes != null && (imageBytes.isEmpty || imageBytes.length > 700 * 1024)) {
      throw ArgumentError(tr('حجم الصورة يجب ألا يتجاوز 700 كيلوبايت'));
    }
    final batch = _db.batch();
    final commentRef = _commentsRef(postId).doc();
    final data = <String, dynamic>{
      'uid': _user.uid,
      'username': username,
      'name': displayName,
      'text': text,
      'kind': kind,
      'likedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (imageBytes != null) data['image'] = Blob(imageBytes);
    // رد على تعليق: يُخزَّن في نفس المجموعة مع parentId (مستوى واحد فقط مثل إنستغرام).
    if (parentId != null && parentId.isNotEmpty) {
      data['parentId'] = parentId;
      if (replyToUsername != null && replyToUsername.isNotEmpty) {
        data['replyToUsername'] = replyToUsername;
      }
    }
    batch.set(commentRef, data);
    batch.update(_db.collection('posts').doc(postId),
        {'comments': FieldValue.increment(1)});
    SocialService.addCommentNotification(
      batch: batch,
      recipientUid: ownerUid,
      actorUid: _user.uid,
      actorUsername: username,
      postId: postId,
      commentId: commentRef.id,
      commentText: text,
    );
    await batch.commit();
  }

  /// يزيد عدّاد المشاركات بمقدار 1 عند مشاركة المنشور.
  static Future<void> registerShare(String postId) async {
    try {
      await _db
          .collection('posts')
          .doc(postId)
          .update({'shares': FieldValue.increment(1)});
    } catch (_) {}
  }

  /// يحذف التعليق مع كل ردوده، وينقص عدّاد التعليقات بعدد المحذوف.
  static Future<void> deleteComment(String postId, String commentId) async {
    final replies = await _commentsRef(postId)
        .where('parentId', isEqualTo: commentId)
        .get();
    final batch = _db.batch();
    batch.delete(_commentsRef(postId).doc(commentId));
    for (final r in replies.docs) {
      batch.delete(r.reference);
    }
    batch.update(_db.collection('posts').doc(postId),
        {'comments': FieldValue.increment(-(1 + replies.docs.length))});
    await batch.commit();
  }

  static Future<void> toggleCommentLike(String postId, String commentId) =>
      _db.runTransaction((transaction) async {
        final reference = _commentsRef(postId).doc(commentId);
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw StateError(tr('التعليق غير موجود'));
        }
        final likedBy =
            List<String>.from(snapshot.data()?['likedBy'] as List? ?? const []);
        transaction.update(reference, {
          'likedBy': likedBy.contains(_user.uid)
              ? FieldValue.arrayRemove([_user.uid])
              : FieldValue.arrayUnion([_user.uid]),
        });
      });

  // ---- القصص (تختفي بعد 24 ساعة) ----
  static const storyLifetime = Duration(hours: 24);

  // ---- الأصدقاء المقربون ----
  // قائمتي: مستند واحد closeFriends/{uid} فيه uids. قصص المقربين في مجموعة
  // closeStories منفصلة (معرّفها يبدأ بـ cf_) وفيها allowed: من يحق له رؤيتها.
  static const maxCloseFriends = 100;
  static const _closeIdPrefix = 'cf_';
  static bool isCloseId(String id) => id.startsWith(_closeIdPrefix);
  static String _colOf(String id) => isCloseId(id) ? 'closeStories' : 'posts';

  static DocumentReference<Map<String, dynamic>> get _closeListRef =>
      _db.collection('closeFriends').doc(_user.uid);

  static Future<List<String>> closeFriendIds() async {
    if (isGuest) return const <String>[];
    final s = await _closeListRef.get();
    final l = s.data()?['uids'];
    return l is List ? l.whereType<String>().toList() : <String>[];
  }

  static Future<void> saveCloseFriends(Iterable<String> ids) {
    final clean = ids
        .where((e) => e.isNotEmpty && e != _user.uid)
        .toSet()
        .take(maxCloseFriends)
        .toList();
    return _closeListRef.set({
      'uids': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// قصص الأصدقاء المقربين: التي أُدرجتُ فيها + قصصي أنا. تحتاج فهرساً مركّباً
  /// (allowed + createdAt)؛ وإن لم يُنشأ بعد يبقى الشريط يعمل بدونها.
  static Stream<List<Post>> _closeStoriesForMe() {
    final since = Timestamp.fromDate(_storyCutoff());
    final forMe = _db
        .collection('closeStories')
        .where('allowed', arrayContains: _user.uid)
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((q) => _parse(q.docs));
    final mine = _db
        .collection('closeStories')
        .where('uid', isEqualTo: _user.uid)
        .limit(30)
        .snapshots()
        .map((q) => _parse(q.docs));
    return _mergeLists(_safeList(forMe), _safeList(mine));
  }

  /// يدمج قائمتي منشورات في قائمة واحدة بلا تكرار، مرتبة بالأحدث.
  static Stream<List<Post>> _mergeLists(
      Stream<List<Post>> a, Stream<List<Post>> b) {
    late final StreamController<List<Post>> controller;
    StreamSubscription<List<Post>>? subA;
    StreamSubscription<List<Post>>? subB;
    List<Post>? listA;
    List<Post>? listB;

    void emit() {
      final x = listA;
      final y = listB;
      if (x == null || y == null) return;
      final byId = {for (final p in [...x, ...y]) p.id: p};
      controller.add(
          byId.values.toList()..sort((m, n) => n.createdAt.compareTo(m.createdAt)));
    }

    controller = StreamController<List<Post>>(
      onListen: () {
        subA = a.listen((v) {
          listA = v;
          emit();
        }, onError: controller.addError);
        subB = b.listen((v) {
          listB = v;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return controller.stream;
  }

  /// يبدّل إلى تدفّق جديد كلما وصلت قيمة جديدة من [source] (ويلغي القديم).
  static Stream<R> _switchMap<T, R>(
      Stream<T> source, Stream<R> Function(T) build) {
    late final StreamController<R> controller;
    StreamSubscription<T>? outer;
    StreamSubscription<R>? inner;
    controller = StreamController<R>(
      onListen: () {
        outer = source.listen((v) {
          inner?.cancel();
          inner = build(v).listen(controller.add, onError: controller.addError);
        }, onError: controller.addError);
      },
      onCancel: () async {
        await outer?.cancel();
        await inner?.cancel();
      },
    );
    return controller.stream;
  }

  /// قصص من أتابعهم (حسابات عامة)، على دفعات من 30 (حد whereIn).
  /// تستخدم الفهرس الموجود authorPrivate + type + uid + createdAt.
  static Stream<List<Post>> _followedStories(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <Post>[]);
    Stream<List<Post>>? merged;
    for (var i = 0; i < ids.length && i < 300; i += 30) {
      final chunk = ids.sublist(i, math.min(i + 30, ids.length));
      final s = _byType(PostType.story)
          .where('authorPrivate', isEqualTo: false)
          .where('uid', whereIn: chunk)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(_storyCutoff()))
          .limit(60)
          .snapshots()
          .map((q) => _parse(q.docs));
      merged = merged == null ? s : _mergeLists(merged, s);
    }
    return merged!;
  }

  static DateTime _storyCutoff() => DateTime.now().subtract(storyLifetime);

  /// يمنع أي خطأ في تدفّق فرعي (قواعد/فهرس) من إسقاط شريط القصص كله.
  static Stream<List<Post>> _safeList(Stream<List<Post>> s) => s.transform(
      StreamTransformer<List<Post>, List<Post>>.fromHandlers(
          handleError: (e, st, sink) => sink.add(const <Post>[])));

  /// من بين من أتابعهم، أيّهم حسابه خاص (يُقرأ ملفه مرة واحدة ويُخزَّن في الذاكرة).
  static Future<List<String>> _privateAmong(List<String> ids) async {
    final res = await Future.wait([
      for (final id in ids.take(60))
        UserService.profileOf(id)
            .then<String?>((u) => u?.isPrivate == true ? id : null)
            .catchError((_) => null),
    ]);
    return [
      for (final r in res)
        if (r != null) r,
    ];
  }

  /// قصص الحسابات الخاصة التي أتابعها. القواعد لا تسمح باستعلام متعدد الحسابات
  /// عليها، فنستعلم عن كل حساب خاص وحده (يسمح به كوني متابعاً له).
  static Stream<List<Post>> _followedPrivateStories(List<String> ids) async* {
    yield const <Post>[];
    final priv = await _privateAmong(ids);
    if (priv.isEmpty) return;
    final since = Timestamp.fromDate(_storyCutoff());
    Stream<List<Post>>? merged;
    for (final uid in priv.take(30)) {
      final s = _safeList(_byType(PostType.story)
          .where('uid', isEqualTo: uid)
          .where('createdAt', isGreaterThan: since)
          .limit(10)
          .snapshots()
          .map((q) => _parse(q.docs)));
      merged = merged == null ? s : _mergeLists(merged, s);
    }
    yield* merged!;
  }

  /// قصص من أتابعهم أولاً (دون سقف الأحدث-100 العام)، وقصصي أنا دائماً،
  /// وأحدث قصص الحسابات العامة للاكتشاف. القصص العامة تستثني الحسابات الخاصة.
  static Stream<List<Post>> _visibleStories() {
    final cutoff = _storyCutoff();
    final discover = stream(PostType.story, limit: 50, since: cutoff);
    if (isGuest) return discover;
    final mine =
        stream(PostType.story, uid: uidOrEmpty, limit: 30, since: cutoff);
    final followed = _switchMap<List<String>, List<Post>>(
        followingIds(),
        (ids) => _mergeLists(
            _followedStories(ids), _safeList(_followedPrivateStories(ids))));
    return _mergeLists(
        _mergeLists(_mergeLists(discover, mine), followed),
        _closeStoriesForMe());
  }

  static Stream<List<StoryGroup>> storyGroups() =>
      _visibleStories().map((list) {
        final cutoff = DateTime.now().subtract(storyLifetime);
        final live = list.where((p) => p.createdAt.isAfter(cutoff)).toList();
        final byUser = <String, List<Post>>{};
        for (final p in live.reversed) {
          (byUser[p.uid] ??= []).add(p); // الأقدم أولاً
        }
        return byUser.entries
            .map((e) => StoryGroup(
                uid: e.key, username: e.value.last.username, stories: e.value))
            .toList();
      });

  /// يحذف قصصي المنتهية (أقدم من 24 ساعة) لتوفير الحصة المجانية.
  static Future<void> cleanupMyExpiredStories() async {
    if (isGuest) return;
    final snap = await _db
        .collection('posts')
        .where('type', isEqualTo: 'story')
        .where('uid', isEqualTo: _user.uid)
        .orderBy('createdAt', descending: true)
        .get();
    final cutoff = DateTime.now().subtract(storyLifetime);
    for (final d in snap.docs) {
      final p = Post.fromDoc(d);
      if (p.createdAt.isBefore(cutoff)) await deletePost(p);
    }
    // قصص الأصدقاء المقربين المنتهية.
    try {
      final close = await _db
          .collection('closeStories')
          .where('uid', isEqualTo: _user.uid)
          .get();
      for (final d in close.docs) {
        final p = Post.fromDoc(d);
        if (p.createdAt.isBefore(cutoff)) await deletePost(p);
      }
    } catch (_) {}
  }

  // ---- قوائم المتابعين / المتابَعين ----
  static Future<List<String>> followerIdsOnce(String uid) async =>
      (await _db.collection('users').doc(uid).collection('followers').get())
          .docs
          .map((d) => d.id)
          .toList();

  static Future<List<String>> followingIdsOnce(String uid) async =>
      (await _db.collection('users').doc(uid).collection('following').get())
          .docs
          .map((d) => d.id)
          .toList();
}

class Comment {
  final String id;
  final String uid;
  final String username;
  final String name;
  final String text;
  final String kind;
  final Uint8List? imageBytes;
  final List<String> likedBy;
  final DateTime createdAt;

  /// معرّف التعليق الأب إن كان هذا ردّاً، و[replyToUsername] من يُرَدّ عليه.
  final String? parentId;
  final String? replyToUsername;

  Comment(
      {required this.id,
      required this.uid,
      required this.username,
      required this.name,
      required this.text,
      this.kind = 'text',
      this.imageBytes,
      required this.likedBy,
      required this.createdAt,
      this.parentId,
      this.replyToUsername});

  factory Comment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Comment(
      id: d.id,
      uid: m['uid'] ?? '',
      username: m['username'] ?? tr('مستخدم'),
      name: m['name'] ?? '',
      text: m['text'] ?? '',
      kind: m['kind'] as String? ?? 'text',
      imageBytes: (m['image'] as Blob?)?.bytes,
      likedBy: List<String>.from(m['likedBy'] as List? ?? const []),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      parentId: m['parentId'] as String?,
      replyToUsername: m['replyToUsername'] as String?,
    );
  }
}

/// قصص مستخدم واحد (الأقدم أولاً).
class StoryViewEntry {
  final String uid;
  final DateTime at;
  final String? reaction; // إيموجي تفاعل المشاهد (إن وُجد)
  StoryViewEntry(this.uid, this.at, [this.reaction]);
}

class StoryGroup {
  final String uid;
  final String username;
  final List<Post> stories;
  StoryGroup(
      {required this.uid, required this.username, required this.stories});

  /// هل فيها قصة للأصدقاء المقربين؟
  bool get hasClose => stories.any((s) => s.closeFriends);
}

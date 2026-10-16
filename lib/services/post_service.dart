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

enum PostType { photo, text, story }

class Post {
  final String id;
  final PostType type;
  final String uid;
  final String username;
  final String name;
  final String caption;
  final String? mediaUrl;
  final String? mediaId; // وضع التجربة: الملف مخزّن في Firestore على قطع
  final String? videoId; // معرّف فيديو يوتيوب (11 حرفاً) إن وُجد
  final bool isShort; // رابط شورتز (عمودي 9:16)
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
    this.videoId,
    this.isShort = false,
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
      username: m['username'] ?? 'مستخدم',
      name: m['name'] ?? '',
      caption: m['caption'] ?? '',
      mediaUrl: m['mediaUrl'],
      mediaId: m['mediaId'],
      videoId: m['videoId'] as String?,
      isShort: m['isShort'] == true,
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

  /// صورة الفيديو المصغّرة من يوتيوب (لا تستهلك أي حصة من Firebase أو Cloudinary).
  String? get videoThumb =>
      hasVideo ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg' : null;

  List<String> get hashtags => RegExp(r'#[\p{L}\p{N}_]+', unicode: true)
      .allMatches(caption)
      .map((m) => m.group(0)!)
      .toList();
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

  static User get currentUser => _user;

  /// يزداد عند أي فعل يغيّر الأعداد (متابعة، إعجاب، نشر، حذف) فتعيد
  /// العدّادات في الملف الشخصي تحميل نفسها فوراً دون إعادة فتح الصفحة.
  static final statsTick = ValueNotifier<int>(0);
  static void notifyStatsChanged() => statsTick.value++;

  /// اسم المستخدم (@) الخاص بي.
  static String get username {
    final m = UserService.me;
    if (m != null && m.username.isNotEmpty) return m.username;
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

  static Stream<List<Post>> stream(PostType t, {String? uid, int limit = 40}) {
    var q = _byType(t);
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    return q
        .limit(limit)
        .snapshots()
        .map((s) => _parse(s.docs));
  }

  /// يحوّل المستندات إلى منشورات ويتجاهل الفيديوهات القديمة.
  static List<Post> _parse(
          Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) =>
      [
        for (final d in docs)
          if (!Post.isLegacyVideo(d)) Post.fromDoc(d),
      ];

  static Stream<List<Post>> profilePosts(String uid, {int limit = 90}) => _db
      .collection('posts')
      .where('type', whereIn: const ['photo', 'text'])
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) => _parse(snapshot.docs));

  static Future<List<Post>> search(String text) async {
    final snap = await _db
        .collection('posts')
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

  // الأكثر رواجاً: نخزّن النتيجة 5 دقائق في الذاكرة ونقرأ 60 منشوراً فقط
  // (كان 150 لكل فتح لصفحة الاستكشاف) لتوفير قراءات Firebase.
  static const _trendingTtl = Duration(minutes: 5);
  static const _trendingReadLimit = 60;
  static DateTime? _tagsAt;
  static Map<String, int>? _tagsCache;

  static bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < _trendingTtl;

  static Future<Map<String, int>> trendingTags() async {
    if (_fresh(_tagsAt) && _tagsCache != null) return _tagsCache!;
    final snap = await _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(_trendingReadLimit)
        .get();
    final counts = <String, int>{};
    for (final post in _parse(snap.docs)) {
      if (post.type == PostType.story) continue;
      for (final t in post.hashtags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _tagsCache = Map.fromEntries(sorted.take(15));
    _tagsAt = DateTime.now();
    return _tagsCache!;
  }

  static Future<Post?> postById(String postId) async {
    final snapshot = await _db.collection('posts').doc(postId).get();
    if (!snapshot.exists || Post.isLegacyVideo(snapshot)) return null;
    return Post.fromDoc(snapshot);
  }

  static String postLink(Post post) =>
      Uri.base.replace(path: '/', queryParameters: {'p': post.id}).toString();

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
      throw StateError('فشل الرفع إلى Cloudinary: $message');
    }
    final url = json['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('لم يُرجع Cloudinary رابط الملف');
    }
    return url;
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

  static Future<void> _create(PostType type, String caption, String? url,
      {String? mediaId,
      int chunks = 0,
      String? mime,
      Map<String, dynamic> extra = const {}}) {
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
      'createdAt': FieldValue.serverTimestamp(),
    };
    data.addAll(extra);
    return _db.collection('posts').add(data).then((_) => notifyStatsChanged());
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// ينشر وسائط (صورة/قصة). [mime] مثل image/jpeg.
  static Future<void> publishMedia(
    PostType type,
    Uint8List bytes, {
    required String mime,
    required String ext,
    required String caption,
    required void Function(double) onProgress,
    Map<String, dynamic> extra = const {},
  }) async {
    if (useCloudinary) {
      onProgress(0);
      final url = await _uploadCloudinary(bytes, mime, ext);
      onProgress(1);
      await _create(type, caption, url, mime: mime, extra: extra);
    } else if (useStorage) {
      final url = await _upload(
          bytes, 'photos/${_user.uid}/${_stamp()}.$ext', mime, onProgress);
      await _create(type, caption, url, mime: mime, extra: extra);
    } else {
      final id = await _storeInFirestore(bytes, onProgress);
      await _create(type, caption, null,
          mediaId: id,
          chunks: (bytes.length / _chunkSize).ceil(),
          mime: mime,
          extra: extra);
    }
  }

  /// يستخرج معرّف الفيديو من أي صيغة رابط يوتيوب:
  /// watch?v= ، youtu.be ، shorts ، live ، embed ، /v/ ، m. ، music. ، youtube-nocookie.
  /// يعيد null إذا لم يكن الرابط يوتيوب صالحاً.
  static String? youtubeId(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
    final idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');
    String? id;
    if (host == 'youtu.be') {
      if (uri.pathSegments.isNotEmpty) id = uri.pathSegments.first;
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      final seg = uri.pathSegments;
      if (seg.isNotEmpty && seg.first == 'watch') {
        id = uri.queryParameters['v'];
      } else if (seg.length >= 2 &&
          const {'shorts', 'live', 'embed', 'v'}.contains(seg.first)) {
        id = seg[1];
      }
    }
    return (id != null && idRe.hasMatch(id)) ? id : null;
  }

  /// هل الرابط رابط شورتز (youtube.com/shorts/ID)؟
  static bool isShortsLink(String input) {
    var text = input.trim();
    if (text.isEmpty) return false;
    if (!text.contains('://')) text = 'https://$text';
    final seg = Uri.tryParse(text)?.pathSegments ?? const <String>[];
    return seg.isNotEmpty && seg.first == 'shorts';
  }

  static String youtubeWatchUrl(String id) => 'https://www.youtube.com/watch?v=$id';

  /// منشور نصي، وقد يرافقه (أو يحلّ محلّه) فيديو يوتيوب.
  static Future<void> publishText(String text,
          {String? videoId, bool isShort = false}) =>
      _create(PostType.text, text, null, extra: {
        if (videoId != null) 'videoId': videoId,
        if (videoId != null && isShort) 'isShort': true,
      });

  // ---- الإعجاب والحفظ والمتابعة ----
  static DocumentReference<Map<String, dynamic>> _likeRef(String postId) =>
      _db.collection('posts').doc(postId).collection('likes').doc(_user.uid);

  static Stream<bool> isLiked(String postId) =>
      _likeRef(postId).snapshots().map((s) => s.exists);

  /// عدد الإعجابات الحي للمنشور.
  static Stream<int> likeCount(String postId) => _db
      .collection('posts')
      .doc(postId)
      .snapshots()
      .map((s) => ((s.data()?['likes'] ?? 0) as num).toInt());

  // ---- مشاهدات القصص ----
  /// يسجّل أن المستخدم الحالي شاهد القصة (مرة واحدة لكل مستخدم). لا يسجّل لصاحبها.
  static Future<void> recordStoryView(Post story) async {
    if (story.uid == _user.uid) return;
    await _db
        .collection('posts')
        .doc(story.id)
        .collection('views')
        .doc(_user.uid)
        .set({'at': FieldValue.serverTimestamp()});
  }

  /// من شاهدوا قصتي (الأحدث أولاً). يقرؤها صاحب القصة فقط.
  static Stream<List<StoryViewEntry>> storyViewers(String postId) => _db
      .collection('posts')
      .doc(postId)
      .collection('views')
      .orderBy('at', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => [
            for (final d in s.docs)
              if (d.data()['at'] is Timestamp)
                StoryViewEntry(d.id, (d.data()['at'] as Timestamp).toDate()),
          ]);

  static Future<void> toggleLike(String postId, bool liked) async {
    final batch = _db.batch();
    final post = _db.collection('posts').doc(postId);
    final postSnapshot = await post.get();
    if (!postSnapshot.exists) {
      throw StateError('المنشور غير موجود');
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

  static Stream<bool> isSaved(String postId) =>
      _saveRef(postId).snapshots().map((s) => s.exists);

  static Future<void> toggleSave(String postId, bool saved) => saved
      ? _saveRef(postId).delete()
      : _saveRef(postId).set({'at': FieldValue.serverTimestamp()});

  static Stream<bool> isFollowing(String targetUid) => _db
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
      throw ArgumentError.value(targetUid, 'targetUid', 'مستخدم غير صالح');
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
  static Stream<List<String>> incomingFollowRequestIds() => _db
      .collection('users')
      .doc(_user.uid)
      .collection('followRequests')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  static Stream<bool> hasIncomingRequest(String requesterUid) =>
      _requestRef(_user.uid, requesterUid).snapshots().map((s) => s.exists);

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

  static Stream<List<String>> followingIds() => _db
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

  /// عدد منشورات المستخدم (صور + نص، دون القصص).
  static Future<int> countPosts(String uid) async {
    final counts = await Future.wait(['photo', 'text'].map((t) async {
      final snap = await _db
          .collection('posts')
          .where('type', isEqualTo: t)
          .where('uid', isEqualTo: uid)
          .count()
          .get();
      return snap.count ?? 0;
    }));
    return counts.fold<int>(0, (a, b) => a + b);
  }

  /// مجموع إعجابات منشورات المستخدم. يستعمل استعلام تجميع (قراءة واحدة تقريباً
  /// لكل 1000 منشور) وإن لم يتوفر يرجع للجمع اليدوي.
  static Future<int> totalLikes(String uid) async {
    final query = _db.collection('posts').where('uid', isEqualTo: uid);
    try {
      final agg = await query.aggregate(sum('likes')).get();
      return (agg.getSum('likes') ?? 0).round();
    } catch (_) {
      final snap = await query.get();
      return snap.docs
          .fold<int>(0, (a, d) => a + ((d.data()['likes'] ?? 0) as num).toInt());
    }
  }

  /// منشورات بمعرّفاتها (حتى 10)، بنفس ترتيب [ids]؛ المحذوفة تُهمَل.
  static Future<List<Post>> postsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snap = await _db
        .collection('posts')
        .where(FieldPath.documentId, whereIn: ids.take(10).toList())
        .get();
    final byId = {
      for (final d in snap.docs)
        if (!Post.isLegacyVideo(d)) d.id: Post.fromDoc(d),
    };
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  // ---- منشور واحد، حذف ----
  static Stream<Post?> postStream(String id) => _db
      .collection('posts')
      .doc(id)
      .snapshots()
      .map((d) => d.exists && !Post.isLegacyVideo(d) ? Post.fromDoc(d) : null);

  /// تعديل نص المنشور/وصف الفيديو (للمالك فقط حسب قواعد Firestore).
  static Future<void> updateCaption(Post p, String caption) async {
    await _db.collection('posts').doc(p.id).update({'caption': caption});
  }

  static Future<void> deletePost(Post p) async {
    if (p.mediaId != null) {
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

  // ---- المحفوظات ----
  static Stream<List<Post>> savedPosts() => _db
          .collection('users')
          .doc(_user.uid)
          .collection('saved')
          .orderBy('at', descending: true)
          .snapshots()
          .asyncMap((s) async {
        final docs = await Future.wait(
            s.docs.map((d) => _db.collection('posts').doc(d.id).get()));
        return _parse(docs.where((d) => d.exists));
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
        final docs = await Future.wait(
            s.docs.map((d) => _db.collection('posts').doc(d.id).get()));
        return _parse(docs.where((d) => d.exists))
            .where((post) => post.type != PostType.story)
            .toList();
      });

  // ---- التعليقات ----
  static CollectionReference<Map<String, dynamic>> _commentsRef(
          String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  static Stream<List<Comment>> comments(String postId) => _commentsRef(postId)
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(Comment.fromDoc).toList());

  /// يضيف تعليقاً (نصاً أو ملصقاً أو صورة). بلا قراءات مسبقة، فيظهر فوراً.
  /// [kind]: text | sticker | image.
  static Future<void> addComment(
    String postId,
    String text, {
    required String ownerUid,
    String kind = 'text',
    Uint8List? imageBytes,
  }) async {
    if (imageBytes != null && (imageBytes.isEmpty || imageBytes.length > 700 * 1024)) {
      throw ArgumentError('حجم الصورة يجب ألا يتجاوز 700 كيلوبايت');
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

  static Future<void> deleteComment(String postId, String commentId) async {
    final batch = _db.batch();
    batch.delete(_commentsRef(postId).doc(commentId));
    batch.update(_db.collection('posts').doc(postId),
        {'comments': FieldValue.increment(-1)});
    await batch.commit();
  }

  static Future<void> toggleCommentLike(String postId, String commentId) =>
      _db.runTransaction((transaction) async {
        final reference = _commentsRef(postId).doc(commentId);
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw StateError('التعليق غير موجود');
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

  static Stream<List<StoryGroup>> storyGroups() =>
      stream(PostType.story, limit: 100).map((list) {
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

  Comment(
      {required this.id,
      required this.uid,
      required this.username,
      required this.name,
      required this.text,
      this.kind = 'text',
      this.imageBytes,
      required this.likedBy,
      required this.createdAt});

  factory Comment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Comment(
      id: d.id,
      uid: m['uid'] ?? '',
      username: m['username'] ?? 'مستخدم',
      name: m['name'] ?? '',
      text: m['text'] ?? '',
      kind: m['kind'] as String? ?? 'text',
      imageBytes: (m['image'] as Blob?)?.bytes,
      likedBy: List<String>.from(m['likedBy'] as List? ?? const []),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// قصص مستخدم واحد (الأقدم أولاً).
class StoryViewEntry {
  final String uid;
  final DateTime at;
  StoryViewEntry(this.uid, this.at);
}

class StoryGroup {
  final String uid;
  final String username;
  final List<Post> stories;
  StoryGroup(
      {required this.uid, required this.username, required this.stories});
}

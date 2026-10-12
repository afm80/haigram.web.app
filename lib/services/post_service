import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../web_trim.dart';

enum PostType { video, photo, text }

class Post {
  final String id;
  final PostType type;
  final String uid;
  final String username;
  final String caption;
  final String? mediaUrl;
  final String? mediaId; // وضع التجربة: الملف مخزّن في Firestore على قطع
  final int chunks;
  final String mime;
  final int likes;
  final int views;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.type,
    required this.uid,
    required this.username,
    required this.caption,
    required this.mediaUrl,
    this.mediaId,
    this.chunks = 0,
    this.mime = 'video/mp4',
    required this.likes,
    required this.views,
    required this.createdAt,
  });

  factory Post.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Post(
      id: d.id,
      type: PostType.values.firstWhere((t) => t.name == m['type'], orElse: () => PostType.text),
      uid: m['uid'] ?? '',
      username: m['username'] ?? 'مستخدم',
      caption: m['caption'] ?? '',
      mediaUrl: m['mediaUrl'],
      mediaId: m['mediaId'],
      chunks: (m['chunks'] ?? 0) as int,
      mime: m['mime'] ?? 'video/mp4',
      likes: (m['likes'] ?? 0) as int,
      views: (m['views'] ?? 0) as int,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  List<String> get hashtags =>
      RegExp(r'#[\p{L}\p{N}_]+', unicode: true).allMatches(caption).map((m) => m.group(0)!).toList();
}

class PostService {
  /// false = وضع التجربة المجاني تماماً (الملفات داخل Firestore، بدون بطاقة).
  /// true  = Firebase Storage (يتطلب خطة Blaze). فعّله بـ --dart-define=USE_STORAGE=true
  static const useStorage = bool.fromEnvironment('USE_STORAGE');
  static const _chunkSize = 900 * 1024; // أقل من حد مستند Firestore (1MB)
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static User get _user => FirebaseAuth.instance.currentUser!;

  static String get uidOrEmpty => FirebaseAuth.instance.currentUser?.uid ?? '';

  static User get currentUser => _user;

  static String get username {
    final u = _user;
    return (u.displayName?.trim().isNotEmpty ?? false) ? u.displayName! : (u.email?.split('@').first ?? 'user');
  }

  static Query<Map<String, dynamic>> _byType(PostType t) =>
      _db.collection('posts').where('type', isEqualTo: t.name).orderBy('createdAt', descending: true);

  static Stream<List<Post>> stream(PostType t, {String? uid, int limit = 40}) {
    var q = _byType(t);
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    return q.limit(limit).snapshots().map((s) => s.docs.map(Post.fromDoc).toList());
  }

  static Future<List<Post>> search(String text) async {
    final snap = await _db.collection('posts').orderBy('createdAt', descending: true).limit(150).get();
    final all = snap.docs.map(Post.fromDoc);
    final q = text.toLowerCase();
    return all.where((p) => p.caption.toLowerCase().contains(q) || p.username.toLowerCase().contains(q)).toList();
  }

  static Future<Map<String, int>> trendingTags() async {
    final snap = await _db.collection('posts').orderBy('createdAt', descending: true).limit(150).get();
    final counts = <String, int>{};
    for (final d in snap.docs) {
      for (final t in Post.fromDoc(d).hashtags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(15));
  }

  /// رفع ملف إلى Storage مع تتبّع نسبة التقدم.
  static Future<String> _upload(Uint8List bytes, String path, String contentType, void Function(double)? onProgress) async {
    final ref = _storage.ref(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    await task;
    return ref.getDownloadURL();
  }

  /// وضع التجربة: يقسّم الملف إلى قطع ويحفظها في مجموعة media.
  static Future<String> _storeInFirestore(Uint8List bytes, void Function(double)? onProgress) async {
    final id = _db.collection('media').doc().id;
    final n = (bytes.length / _chunkSize).ceil();
    for (var i = 0; i < n; i++) {
      final end = math.min(bytes.length, (i + 1) * _chunkSize);
      final part = Uint8List.sublistView(bytes, i * _chunkSize, end);
      await _db.collection('media').doc('${id}_$i').set({'uid': _user.uid, 'i': i, 'data': Blob(part)});
      onProgress?.call((i + 1) / n);
    }
    return id;
  }

  static final _bytesCache = <String, Future<Uint8List>>{};
  static final _urlCache = <String, Future<String>>{};

  /// بايتات الملف المخزّن في Firestore (مع تخزين مؤقت في الذاكرة).
  static Future<Uint8List> mediaBytes(Post p) {
    return _bytesCache.putIfAbsent(p.mediaId!, () async {
      final docs = await Future.wait(List.generate(p.chunks, (i) => _db.collection('media').doc('${p.mediaId}_$i').get()));
      final b = BytesBuilder(copy: false);
      for (final d in docs) {
        b.add((d.data()!['data'] as Blob).bytes);
      }
      return b.toBytes();
    });
  }

  /// رابط قابل للتشغيل في video_player (رابط Storage أو رابط blob محلي).
  static Future<String> videoUrl(Post p) {
    if (p.mediaUrl != null) return Future.value(p.mediaUrl!);
    return _urlCache.putIfAbsent(p.mediaId!, () async => makeBlobUrl(await mediaBytes(p), p.mime));
  }

  static Future<void> _create(PostType type, String caption, String? url, {String? mediaId, int chunks = 0, String? mime}) {
    return _db.collection('posts').add({
      'type': type.name,
      'uid': _user.uid,
      'username': username,
      'caption': caption,
      'mediaUrl': url,
      'mediaId': mediaId,
      'chunks': chunks,
      'mime': mime,
      'likes': 0,
      'views': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<void> publishVideo(Uint8List bytes, String ext, String caption, void Function(double) onProgress) async {
    if (useStorage) {
      final url = await _upload(bytes, 'videos/${_user.uid}/${_stamp()}.$ext', 'video/$ext', onProgress);
      await _create(PostType.video, caption, url);
    } else {
      final id = await _storeInFirestore(bytes, onProgress);
      await _create(PostType.video, caption, null, mediaId: id, chunks: (bytes.length / _chunkSize).ceil(), mime: 'video/$ext');
    }
  }

  static Future<void> publishPhoto(Uint8List bytes, String caption, void Function(double) onProgress) async {
    if (useStorage) {
      final url = await _upload(bytes, 'photos/${_user.uid}/${_stamp()}.jpg', 'image/jpeg', onProgress);
      await _create(PostType.photo, caption, url);
    } else {
      final id = await _storeInFirestore(bytes, onProgress);
      await _create(PostType.photo, caption, null, mediaId: id, chunks: (bytes.length / _chunkSize).ceil(), mime: 'image/jpeg');
    }
  }

  static Future<void> publishText(String text) => _create(PostType.text, text, null);

  // ---- الإعجاب والحفظ والمتابعة ----
  static DocumentReference<Map<String, dynamic>> _likeRef(String postId) =>
      _db.collection('posts').doc(postId).collection('likes').doc(_user.uid);

  static Stream<bool> isLiked(String postId) => _likeRef(postId).snapshots().map((s) => s.exists);

  static Future<void> toggleLike(String postId, bool liked) async {
    final batch = _db.batch();
    final post = _db.collection('posts').doc(postId);
    if (liked) {
      batch.delete(_likeRef(postId));
      batch.update(post, {'likes': FieldValue.increment(-1)});
    } else {
      batch.set(_likeRef(postId), {'at': FieldValue.serverTimestamp()});
      batch.update(post, {'likes': FieldValue.increment(1)});
    }
    await batch.commit();
  }

  static DocumentReference<Map<String, dynamic>> _saveRef(String postId) =>
      _db.collection('users').doc(_user.uid).collection('saved').doc(postId);

  static Stream<bool> isSaved(String postId) => _saveRef(postId).snapshots().map((s) => s.exists);

  static Future<void> toggleSave(String postId, bool saved) =>
      saved ? _saveRef(postId).delete() : _saveRef(postId).set({'at': FieldValue.serverTimestamp()});

  static Stream<bool> isFollowing(String targetUid) => _db
      .collection('users').doc(_user.uid).collection('following').doc(targetUid)
      .snapshots().map((s) => s.exists);

  static Future<void> toggleFollow(String targetUid, bool following) async {
    final mine = _db.collection('users').doc(_user.uid).collection('following').doc(targetUid);
    final theirs = _db.collection('users').doc(targetUid).collection('followers').doc(_user.uid);
    final batch = _db.batch();
    if (following) {
      batch.delete(mine);
      batch.delete(theirs);
    } else {
      batch.set(mine, {'at': FieldValue.serverTimestamp(), 'username': ''});
      batch.set(theirs, {'at': FieldValue.serverTimestamp(), 'username': username});
    }
    await batch.commit();
  }

  static Stream<List<String>> followerIds(String uid) => _db
      .collection('users').doc(uid).collection('followers')
      .snapshots().map((s) => s.docs.map((d) => d.id).toList());

  static Future<Map<String, String>> followerNames(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('followers').get();
    return {for (final d in snap.docs) d.id: (d.data()['username'] ?? 'مستخدم') as String};
  }

  static Future<int> countFollowers(String uid) async =>
      (await _db.collection('users').doc(uid).collection('followers').count().get()).count ?? 0;

  static Stream<List<String>> followingIds() => _db
      .collection('users').doc(_user.uid).collection('following')
      .snapshots().map((s) => s.docs.map((d) => d.id).toList());

  static Future<int> countFollowing(String uid) async =>
      (await _db.collection('users').doc(uid).collection('following').count().get()).count ?? 0;

  static Future<int> totalLikes(String uid) async {
    final snap = await _db.collection('posts').where('uid', isEqualTo: uid).get();
    return snap.docs.fold<int>(0, (a, d) => a + ((d.data()['likes'] ?? 0) as int));
  }
}

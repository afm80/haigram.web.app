import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../web_trim.dart';
import 'social_service.dart';
import 'user_service.dart';

enum PostType { video, photo, text, story }

class Post {
  final String id;
  final PostType type;
  final String uid;
  final String username;
  final String name;
  final String caption;
  final String? mediaUrl;
  final String? mediaId; // وضع التجربة: الملف مخزّن في Firestore على قطع
  final String? soundPostId;
  final String? soundUsername;
  final int chunks;
  final String mime;
  final int likes;
  final int views;
  final int comments;
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
    this.soundPostId,
    this.soundUsername,
    this.chunks = 0,
    this.mime = 'video/mp4',
    required this.likes,
    required this.views,
    this.comments = 0,
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
      soundPostId: m['soundPostId'] as String?,
      soundUsername: m['soundUsername'] as String?,
      chunks: (m['chunks'] ?? 0) as int,
      mime: m['mime'] ?? 'video/mp4',
      likes: (m['likes'] ?? 0) as int,
      views: (m['views'] ?? 0) as int,
      comments: (m['comments'] ?? 0) as int,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// هل الوسائط فيديو (ريلز أو قصة فيديو)؟
  bool get isVideoMedia =>
      type == PostType.video ||
      (type == PostType.story && mime.startsWith('video/'));

  List<String> get hashtags => RegExp(r'#[\p{L}\p{N}_]+', unicode: true)
      .allMatches(caption)
      .map((m) => m.group(0)!)
      .toList();
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
        .map((s) => s.docs.map(Post.fromDoc).toList());
  }

  static Stream<List<Post>> profilePosts(String uid, {int limit = 90}) => _db
      .collection('posts')
      .where('type', whereIn: const ['video', 'photo', 'text'])
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Post.fromDoc).toList());

  static Future<List<Post>> search(String text) async {
    final snap = await _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    final all = snap.docs.map(Post.fromDoc);
    final q = text.toLowerCase();
    return all
        .where((p) =>
            p.type != PostType.story &&
            (p.caption.toLowerCase().contains(q) ||
                p.username.toLowerCase().contains(q)))
        .toList();
  }

  static Future<Map<String, int>> trendingTags() async {
    final snap = await _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    final counts = <String, int>{};
    for (final d in snap.docs) {
      final post = Post.fromDoc(d);
      if (post.type == PostType.story) continue;
      for (final t in post.hashtags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(15));
  }

  static Future<List<Post>> trendingVideos() async {
    final snap = await _db
        .collection('posts')
        .where('type', isEqualTo: PostType.video.name)
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    final videos = snap.docs.map(Post.fromDoc).toList()
      ..sort((a, b) {
        final aScore = a.likes * 2 + a.comments * 3;
        final bScore = b.likes * 2 + b.comments * 3;
        final byEngagement = bScore.compareTo(aScore);
        return byEngagement != 0
            ? byEngagement
            : b.createdAt.compareTo(a.createdAt);
      });
    return videos.take(30).toList();
  }

  static Future<Post?> postById(String postId) async {
    final snapshot = await _db.collection('posts').doc(postId).get();
    return snapshot.exists ? Post.fromDoc(snapshot) : null;
  }

  static String postLink(Post post) =>
      Uri.base.replace(path: '/', queryParameters: {'p': post.id}).toString();

  static Stream<List<Post>> videosWithSound(Post sound) => _db
          .collection('posts')
          .where('soundPostId', isEqualTo: sound.id)
          .snapshots()
          .map((snapshot) {
        final videos = snapshot.docs
            .map(Post.fromDoc)
            .where((post) => post.type == PostType.video)
            .toList();
        if (sound.type == PostType.video &&
            !videos.any((post) => post.id == sound.id)) {
          videos.add(sound);
        }
        videos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return videos;
      });

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
  static final _urlCache = <String, Future<String>>{};

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

  static Future<Uint8List> videoBytes(Post post) async {
    if (!post.isVideoMedia) {
      throw ArgumentError.value(post.id, 'post', 'المنشور ليس فيديو');
    }
    if (post.mediaId != null) return mediaBytes(post);
    final url = post.mediaUrl;
    if (url == null || url.isEmpty) {
      throw StateError('ملف الفيديو غير متاح للتنزيل');
    }
    final bytes = await _storage
        .refFromURL(url)
        .getData(300 * 1024 * 1024);
    if (bytes == null) throw StateError('تعذر تنزيل بيانات الفيديو');
    return bytes;
  }

  static Future<void> addVideoToStory(Post post) async {
    final bytes = await videoBytes(post);
    final extension = post.mime.split('/').last.split(';').first;
    await publishMedia(
      PostType.story,
      bytes,
      mime: post.mime,
      ext: extension,
      caption: 'فيديو تمت مشاركته من @${post.username}',
      onProgress: (_) {},
    );
  }

  /// رابط قابل للتشغيل في video_player (رابط Storage أو رابط blob محلي).
  static Future<String> videoUrl(Post p) {
    if (p.mediaUrl != null) return Future.value(p.mediaUrl!);
    return _urlCache.putIfAbsent(
        p.mediaId!, () async => makeBlobUrl(await mediaBytes(p), p.mime));
  }

  static Future<void> _create(PostType type, String caption, String? url,
      {String? mediaId,
      int chunks = 0,
      String? mime,
      String? soundPostId,
      String? soundUsername}) {
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
    if (soundPostId != null) {
      data['soundPostId'] = soundPostId;
      data['soundUsername'] = soundUsername;
    }
    return _db.collection('posts').add(data);
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// ينشر وسائط (ريلز/صورة/قصة). [mime] مثل image/jpeg أو video/mp4.
  static Future<void> publishMedia(
    PostType type,
    Uint8List bytes, {
    required String mime,
    required String ext,
    required String caption,
    required void Function(double) onProgress,
    String? soundPostId,
    String? soundUsername,
  }) async {
    if (soundPostId != null && type != PostType.video) {
      throw ArgumentError('Only video posts can reuse audio');
    }
    if (useStorage) {
      final folder = mime.startsWith('video/') ? 'videos' : 'photos';
      final url = await _upload(
          bytes, '$folder/${_user.uid}/${_stamp()}.$ext', mime, onProgress);
      await _create(type, caption, url,
          mime: mime, soundPostId: soundPostId, soundUsername: soundUsername);
    } else {
      final id = await _storeInFirestore(bytes, onProgress);
      await _create(type, caption, null,
          mediaId: id,
          chunks: (bytes.length / _chunkSize).ceil(),
          mime: mime,
          soundPostId: soundPostId,
          soundUsername: soundUsername);
    }
  }

  static Future<void> publishText(String text) =>
      _create(PostType.text, text, null);

  // ---- الإعجاب والحفظ والمتابعة ----
  static DocumentReference<Map<String, dynamic>> _likeRef(String postId) =>
      _db.collection('posts').doc(postId).collection('likes').doc(_user.uid);

  static Stream<bool> isLiked(String postId) =>
      _likeRef(postId).snapshots().map((s) => s.exists);

  static Future<void> toggleLike(String postId, bool liked) async {
    final batch = _db.batch();
    final post = _db.collection('posts').doc(postId);
    final postSnapshot = await post.get();
    if (!postSnapshot.exists) {
      throw StateError('المنشور غير موجود');
    }
    final ownerUid = postSnapshot.data()?['uid'] as String?;
    if (liked) {
      batch.delete(_likeRef(postId));
      batch.update(post, {'likes': FieldValue.increment(-1)});
    } else {
      batch.set(_likeRef(postId), {'at': FieldValue.serverTimestamp()});
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

  static Future<void> toggleFollow(String targetUid, bool following) async {
    final mine = _db
        .collection('users')
        .doc(_user.uid)
        .collection('following')
        .doc(targetUid);
    final theirs = _db
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(_user.uid);
    final batch = _db.batch();
    if (following) {
      batch.delete(mine);
      batch.delete(theirs);
    } else {
      batch.set(mine, {'at': FieldValue.serverTimestamp()});
      batch.set(theirs, {'at': FieldValue.serverTimestamp()});
      SocialService.addFollowNotification(
        batch: batch,
        recipientUid: targetUid,
        actorUid: _user.uid,
        actorUsername: username,
      );
    }
    await batch.commit();
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

  /// عدد منشورات المستخدم (فيديو + صور + نص، دون القصص).
  static Future<int> countPosts(String uid) async {
    final counts = await Future.wait(['video', 'photo', 'text'].map((t) async {
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

  static Future<int> totalLikes(String uid) async {
    final snap =
        await _db.collection('posts').where('uid', isEqualTo: uid).get();
    return snap.docs
        .fold<int>(0, (a, d) => a + ((d.data()['likes'] ?? 0) as int));
  }

  // ---- منشور واحد، حذف ----
  static Stream<Post?> postStream(String id) => _db
      .collection('posts')
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Post.fromDoc(d) : null);

  static Future<void> deletePost(Post p) async {
    if (p.mediaId != null) {
      for (var i = 0; i < p.chunks; i++) {
        try {
          await _db.collection('media').doc('${p.mediaId}_$i').delete();
        } catch (_) {}
      }
    }
    await _db.collection('posts').doc(p.id).delete();
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
        return docs.where((d) => d.exists).map(Post.fromDoc).toList();
      });

  // ---- التعليقات ----
  static CollectionReference<Map<String, dynamic>> _commentsRef(
          String postId) =>
      _db.collection('posts').doc(postId).collection('comments');

  static Stream<List<Comment>> comments(String postId) => _commentsRef(postId)
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(Comment.fromDoc).toList());

  static Future<void> addComment(String postId, String text) async {
    final batch = _db.batch();
    final commentRef = _commentsRef(postId).doc();
    final postSnapshot = await _db.collection('posts').doc(postId).get();
    if (!postSnapshot.exists) {
      throw StateError('المنشور غير موجود');
    }
    batch.set(commentRef, {
      'uid': _user.uid,
      'username': username,
      'name': displayName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('posts').doc(postId),
        {'comments': FieldValue.increment(1)});
    final ownerUid = postSnapshot.data()?['uid'] as String?;
    if (ownerUid != null) {
      SocialService.addCommentNotification(
        batch: batch,
        recipientUid: ownerUid,
        actorUid: _user.uid,
        actorUsername: username,
        postId: postId,
        commentId: commentRef.id,
        commentText: text,
      );
    }
    await batch.commit();
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    final batch = _db.batch();
    batch.delete(_commentsRef(postId).doc(commentId));
    batch.update(_db.collection('posts').doc(postId),
        {'comments': FieldValue.increment(-1)});
    await batch.commit();
  }

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
  final DateTime createdAt;

  Comment(
      {required this.id,
      required this.uid,
      required this.username,
      required this.name,
      required this.text,
      required this.createdAt});

  factory Comment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Comment(
      id: d.id,
      uid: m['uid'] ?? '',
      username: m['username'] ?? 'مستخدم',
      name: m['name'] ?? '',
      text: m['text'] ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// قصص مستخدم واحد (الأقدم أولاً).
class StoryGroup {
  final String uid;
  final String username;
  final List<Post> stories;
  StoryGroup(
      {required this.uid, required this.username, required this.stories});
}

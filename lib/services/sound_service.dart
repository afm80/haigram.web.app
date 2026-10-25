// الأصوات: صفحة قرص الصوت، الأصوات المحفوظة، وفيديوهات الصوت نفسه.
//
// البنية في Firestore:
//  - posts/{id}.sound = {id, title, uid, username}: الصوت الذي يستخدمه الفيديو
//    أو القصة. id هو معرّف منشور الفيديو الأصلي (الصوت الأصلي لا يحمل الحقل).
//  - users/{uid}/savedSounds/{soundId} = {at, title, uid, username}: أصواتي المحفوظة.
//  - فهرس posts: authorPrivate + sound.id + type + createdAt (firestore.indexes.json).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'post_service.dart';
import '../video_source.dart';

class SoundService {
  static final _db = FirebaseFirestore.instance;
  static bool get _guest => FirebaseAuth.instance.currentUser == null;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// فيديوهات الحسابات العامة التي تستخدم الصوت [soundId] (الأحدث أولاً).
  static Query<Map<String, dynamic>> _videos(String soundId) => _db
      .collection('posts')
      .where('authorPrivate', isEqualTo: false)
      .where('sound.id', isEqualTo: soundId)
      .where('type', isEqualTo: 'text')
      .orderBy('createdAt', descending: true);

  static bool _isFileVideo(Post p) => p.video?.provider == VideoProvider.file;

  /// دفعة من الفيديوهات التي تستخدم الصوت (بدون الفيديو الأصلي).
  static Future<PostPage> videosPage(String soundId,
      {DocumentSnapshot<Map<String, dynamic>>? after, int limit = 18}) async {
    var q = _videos(soundId).limit(limit);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    final posts = [
      for (final d in snap.docs)
        if (!Post.isLegacyVideo(d)) Post.fromDoc(d),
    ].where(_isFileVideo).toList();
    return PostPage(
      posts,
      snap.docs.isEmpty ? after : snap.docs.last,
      snap.docs.length >= limit,
    );
  }

  /// عدد الفيديوهات التي استخدمت الصوت (بدون الأصلي).
  static Future<int> usesCount(String soundId) async {
    final snap = await _videos(soundId).count().get();
    return snap.count ?? 0;
  }

  /// الفيديو الأصلي صاحب الصوت، أو null إن حُذف أو لم يعد متاحاً.
  static Future<Post?> original(String soundId) async {
    final p = await PostService.postById(soundId);
    if (p == null || p.authorPrivate && p.uid != PostService.uidOrEmpty) {
      return null;
    }
    return _isFileVideo(p) ? p : null;
  }

  // ---- الأصوات المحفوظة ----
  static CollectionReference<Map<String, dynamic>> get _savedCol =>
      _db.collection('users').doc(_uid).collection('savedSounds');

  static Stream<bool> isSaved(String soundId) => _guest
      ? Stream.value(false)
      : _savedCol.doc(soundId).snapshots().map((s) => s.exists);

  static Future<void> toggleSave(PostSound sound, bool saved) => saved
      ? _savedCol.doc(sound.id).delete()
      : _savedCol.doc(sound.id).set({
          'at': FieldValue.serverTimestamp(),
          'title': sound.title,
          'uid': sound.uid,
          'username': sound.username,
        });

  /// أصواتي المحفوظة، الأحدث أولاً.
  static Stream<List<PostSound>> savedSounds({int limit = 100}) => _guest
      ? Stream.value(const <PostSound>[])
      : _savedCol
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => [
                for (final d in s.docs)
                  if (PostSound.fromMap({...d.data(), 'id': d.id}) != null)
                    PostSound.fromMap({...d.data(), 'id': d.id})!,
              ]);
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/painting.dart';

/// ملف مستخدم: الاسم (يظهر بخط عريض) + اسم المستخدم الفريد (@) + النبذة.
class AppUser {
  final String uid;
  final String name;
  final String username;
  final String bio;
  final String? photoUrl;

  /// صورة شخصية مرفوعة (JPEG مصغّر بصيغة base64) محفوظة في مستند المستخدم.
  final String? photoB64;

  AppUser({
    required this.uid,
    required this.name,
    required this.username,
    this.bio = '',
    this.photoUrl,
    this.photoB64,
  });

  /// الصورة المعروضة: المرفوعة أولاً، ثم صورة Google، وإلا null (يظهر أول حرف).
  late final ImageProvider? avatarImage = _buildAvatar();

  ImageProvider? _buildAvatar() {
    final b = photoB64;
    if (b != null && b.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(b));
      } catch (_) {}
    }
    final u = photoUrl;
    if (u != null && u.isNotEmpty) return CachedNetworkImageProvider(u);
    return null;
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: d.id,
      name: (m['name'] ?? '') as String,
      username: (m['username'] ?? '') as String,
      bio: (m['bio'] ?? '') as String,
      photoUrl: m['photoUrl'] as String?,
      photoB64: m['photoB64'] as String?,
    );
  }

  /// الاسم المعروض: الاسم، وإلا اسم المستخدم.
  String get displayName => name.trim().isNotEmpty ? name : username;

  String get initial {
    final s = displayName.trim();
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  String get link => UserService.linkFor(username);
  String get shortLink => UserService.shortLinkFor(username);
}

class UsernameTaken implements Exception {
  const UsernameTaken();
}

class UserService {
  static final _db = FirebaseFirestore.instance;
  static final usernameRe = RegExp(r'^[a-z0-9._]{3,24}$');

  /// ملفي الشخصي (يُحمَّل عند الدخول).
  static AppUser? me;

  /// اسم المستخدم المختار أثناء التسجيل (يستعمله ensureProfile إن لم يُمرَّر اسم).
  static String? pendingUsername;

  static final _cache = <String, Future<AppUser?>>{};

  static String normalize(String s) => s.trim().toLowerCase().replaceAll('@', '');

  /// يعيد رسالة خطأ بالعربية أو null إذا كان الاسم صالحاً.
  static String? validate(String u) {
    if (u.length < 3) return 'اسم المستخدم 3 أحرف على الأقل';
    if (u.length > 24) return 'اسم المستخدم 24 حرفاً كحد أقصى';
    if (!usernameRe.hasMatch(u)) return 'اسم المستخدم: أحرف إنجليزية صغيرة وأرقام و _ و . فقط';
    return null;
  }

  /// رابط الملف الشخصي (يفتح التطبيق على ملف هذا المستخدم).
  static String linkFor(String username) => '${Uri.base.origin}/?u=$username';
  static String shortLinkFor(String username) => linkFor(username).replaceFirst(RegExp(r'^https?://'), '');

  static Future<bool> isAvailable(String username) async {
    final s = await _db.collection('usernames').doc(username).get();
    if (!s.exists) return true;
    return s.data()?['uid'] == FirebaseAuth.instance.currentUser?.uid;
  }

  static Future<void> _save({
    required String uid,
    required String username,
    required String name,
    required String bio,
    String? photoUrl,
    String? photoB64,
    String? oldUsername,
  }) {
    return _db.runTransaction((tx) async {
      if (oldUsername != username) {
        final nameRef = _db.collection('usernames').doc(username);
        final s = await tx.get(nameRef);
        if (s.exists && s.data()?['uid'] != uid) throw const UsernameTaken();
        if (!s.exists) tx.set(nameRef, {'uid': uid});
        if (oldUsername != null && oldUsername.isNotEmpty) {
          tx.delete(_db.collection('usernames').doc(oldUsername));
        }
      }
      tx.set(
        _db.collection('users').doc(uid),
        {'name': name, 'username': username, 'bio': bio, 'photoUrl': photoUrl, 'photoB64': photoB64},
        SetOptions(merge: true),
      );
    });
  }

  /// ينشئ ملف المستخدم إن لم يوجد (يشمل الحسابات القديمة) ويحمّله في [me].
  static Future<AppUser> ensureProfile({String? preferredUsername}) async {
    final u = FirebaseAuth.instance.currentUser!;
    final ref = _db.collection('users').doc(u.uid);
    final snap = await ref.get();
    final existing = snap.exists ? AppUser.fromDoc(snap) : null;
    if (existing != null && existing.username.isNotEmpty) {
      me = existing;
      _cache[u.uid] = Future.value(existing);
      return existing;
    }

    final name = (u.displayName ?? '').trim();
    var base = normalize(preferredUsername ?? pendingUsername ?? (u.email?.split('@').first ?? 'user'))
        .replaceAll(RegExp(r'[^a-z0-9._]'), '');
    if (base.length < 3) base = 'user${base.isEmpty ? '' : base}';
    if (base.length > 18) base = base.substring(0, 18);

    final rnd = math.Random();
    for (var i = 0; i < 8; i++) {
      final candidate = i == 0 ? base : '$base${rnd.nextInt(9000) + 1000}';
      try {
        await _save(uid: u.uid, username: candidate, name: name, bio: '', photoUrl: u.photoURL);
        final fresh = AppUser(uid: u.uid, name: name, username: candidate, photoUrl: u.photoURL);
        me = fresh;
        _cache[u.uid] = Future.value(fresh);
        return fresh;
      } on UsernameTaken {
        continue;
      }
    }
    throw Exception('تعذر إنشاء اسم مستخدم');
  }

  /// تعديل ملفي الشخصي. [photoB64] = الصورة المرفوعة (null لإزالتها). يرمي [UsernameTaken] إذا كان الاسم محجوزاً.
  static Future<void> updateProfile({
    required String name,
    required String username,
    required String bio,
    String? photoB64,
  }) async {
    final u = FirebaseAuth.instance.currentUser!;
    final old = me?.username;
    await _save(uid: u.uid, username: username, name: name, bio: bio, photoUrl: me?.photoUrl ?? u.photoURL, photoB64: photoB64, oldUsername: old);
    await u.updateDisplayName(name.isNotEmpty ? name : username);
    final fresh = AppUser(uid: u.uid, name: name, username: username, bio: bio, photoUrl: me?.photoUrl ?? u.photoURL, photoB64: photoB64);
    me = fresh;
    _cache[u.uid] = Future.value(fresh);
  }

  /// ملف مستخدم بمعرّفه (مع تخزين مؤقت). null إذا لم يُنشأ ملفه بعد.
  static Future<AppUser?> profileOf(String uid) {
    if (uid.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(uid, () async {
      final s = await _db.collection('users').doc(uid).get();
      if (!s.exists) return null;
      final user = AppUser.fromDoc(s);
      return user.username.isEmpty ? null : user;
    });
  }

  static Stream<AppUser?> profileStream(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((s) => s.exists ? AppUser.fromDoc(s) : null);

  static Future<AppUser?> byUsername(String username) async {
    final s = await _db.collection('usernames').doc(normalize(username)).get();
    final uid = s.data()?['uid'] as String?;
    return uid == null ? null : profileOf(uid);
  }

  /// بحث عن مستخدمين ببداية اسم المستخدم.
  static Future<List<AppUser>> search(String q) async {
    final text = normalize(q);
    if (text.isEmpty) return [];
    final snap = await _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: text)
        .where('username', isLessThan: '$text\uf8ff')
        .limit(20)
        .get();
    return snap.docs.map(AppUser.fromDoc).toList();
  }
}

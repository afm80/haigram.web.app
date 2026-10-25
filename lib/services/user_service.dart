import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/painting.dart';

import '../l10n.dart';
/// ملف مستخدم: الاسم (يظهر بخط عريض) + اسم المستخدم الفريد (@) + النبذة.
class AppUser {
  final String uid;
  final String name;
  final String username;
  final String bio;

  /// رابط اختياري يظهر تحت النبذة (http/https).
  final String website;
  final String? photoUrl;

  /// صورة شخصية مرفوعة (JPEG مصغّر بصيغة base64) محفوظة في مستند المستخدم.
  final String? photoB64;

  /// حساب خاص: المنشورات تظهر لمتابعيه فقط (إخفاء في الواجهة).
  final bool isPrivate;

  /// إخفاء تبويب الإعجابات عن الآخرين.
  final bool hideLikes;

  /// تسجيل زيارات الملف الشخصي وعرضها (يعمل عندما يفعّله الطرفان).
  final bool profileVisits;

  /// معرّفات المنشورات المثبّتة أعلى الملف (الأحدث تثبيتاً أولاً، حتى 3).
  final List<String> pinnedPostIds;

  /// توثيق الحساب (يكتبه الأدمن فقط من لوحة التحكم). الفئة لا تُخزَّن هنا
  /// لأن ملف المستخدم مقروء للجميع؛ تبقى في طلب التوثيق وتظهر للأدمن فقط.
  final bool verified;

  /// نهاية التوثيق للخطة الشهرية. null = دائم.
  final DateTime? verifiedUntil;

  AppUser({
    required this.uid,
    required this.name,
    required this.username,
    this.bio = '',
    this.website = '',
    this.photoUrl,
    this.photoB64,
    this.isPrivate = false,
    this.hideLikes = false,
    this.profileVisits = true,
    this.pinnedPostIds = const [],
    this.verified = false,
    this.verifiedUntil,
  });

  /// هل العلامة ظاهرة الآن؟ تُحسب وقت العرض، فتختفي تلقائياً بعد انتهاء الشهرية.
  bool get isVerified =>
      verified &&
      (verifiedUntil == null || verifiedUntil!.isAfter(DateTime.now()));

  AppUser withSettings({
    bool? isPrivate,
    bool? hideLikes,
    bool? profileVisits,
    List<String>? pinnedPostIds,
  }) =>
      AppUser(
        uid: uid,
        name: name,
        username: username,
        bio: bio,
        website: website,
        photoUrl: photoUrl,
        photoB64: photoB64,
        isPrivate: isPrivate ?? this.isPrivate,
        hideLikes: hideLikes ?? this.hideLikes,
        profileVisits: profileVisits ?? this.profileVisits,
        pinnedPostIds: pinnedPostIds ?? this.pinnedPostIds,
        verified: verified,
        verifiedUntil: verifiedUntil,
      );

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
      website: (m['website'] ?? '') as String,
      photoUrl: m['photoUrl'] as String?,
      photoB64: m['photoB64'] as String?,
      isPrivate: m['isPrivate'] == true,
      hideLikes: m['hideLikes'] == true,
      profileVisits: m['profileVisits'] != false,
      pinnedPostIds: List<String>.unmodifiable(
          (m['pinnedPostIds'] as List? ?? const []).whereType<String>()),
      verified: m['verified'] == true,
      verifiedUntil: (m['verifiedUntil'] is Timestamp)
          ? (m['verifiedUntil'] as Timestamp).toDate()
          : null,
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

class PinLimitReached implements Exception {
  const PinLimitReached();
  @override
  String toString() => trf('يمكنك تثبيت {0} منشورات كحد أقصى', [UserService.maxPinned]);
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
    if (u.length < 3) return tr('اسم المستخدم 3 أحرف على الأقل');
    if (u.length > 24) return tr('اسم المستخدم 24 حرفاً كحد أقصى');
    if (!usernameRe.hasMatch(u)) return tr('اسم المستخدم: أحرف إنجليزية صغيرة وأرقام و _ و . فقط');
    return null;
  }

  /// يطبّع رابط البايو: يضيف https:// عند غيابها. يعيد '' للفارغ، وnull إذا كان غير صالح.
  static String? normalizeWebsite(String input) {
    var v = input.trim();
    if (v.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(v)) v = 'https://$v';
    final uri = Uri.tryParse(v);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.host.contains('.') ||
        v.length > 100) {
      return null;
    }
    return v;
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
    String? website,
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
        {
          'name': name,
          'nameLower': name.trim().toLowerCase(),
          'username': username,
          'bio': bio,
          if (website != null) 'website': website,
          'photoUrl': photoUrl,
          'photoB64': photoB64,
        },
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
      // حسابات قديمة: نضيف حقل البحث بالاسم مرة واحدة.
      if (snap.data()?['nameLower'] == null) {
        ref
            .set({'nameLower': existing.name.trim().toLowerCase()},
                SetOptions(merge: true))
            .catchError((_) {});
      }
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
    throw Exception(tr('تعذر إنشاء اسم مستخدم'));
  }

  /// تعديل ملفي الشخصي. [photoB64] = الصورة المرفوعة (null لإزالتها). يرمي [UsernameTaken] إذا كان الاسم محجوزاً.
  static Future<void> updateProfile({
    required String name,
    required String username,
    required String bio,
    String website = '',
    String? photoB64,
  }) async {
    final u = FirebaseAuth.instance.currentUser!;
    final old = me?.username;
    await _save(uid: u.uid, username: username, name: name, bio: bio, website: website, photoUrl: me?.photoUrl ?? u.photoURL, photoB64: photoB64, oldUsername: old);
    await u.updateDisplayName(name.isNotEmpty ? name : username);
    final fresh = AppUser(
      uid: u.uid,
      name: name,
      username: username,
      bio: bio,
      website: website,
      photoUrl: me?.photoUrl ?? u.photoURL,
      photoB64: photoB64,
      isPrivate: me?.isPrivate ?? false,
      hideLikes: me?.hideLikes ?? false,
      pinnedPostIds: me?.pinnedPostIds ?? const [],
      verified: me?.verified ?? false,
      verifiedUntil: me?.verifiedUntil,
    );
    me = fresh;
    _cache[u.uid] = Future.value(fresh);
  }

  static const maxPinned = 3;

  /// يحدّث إعدادات الخصوصية (يُمرَّر ما تغيّر فقط).
  static Future<void> updatePrivacy(
      {bool? isPrivate, bool? hideLikes, bool? profileVisits}) async {
    final u = FirebaseAuth.instance.currentUser!;
    final data = <String, dynamic>{
      if (isPrivate != null) 'isPrivate': isPrivate,
      if (hideLikes != null) 'hideLikes': hideLikes,
      if (profileVisits != null) 'profileVisits': profileVisits,
    };
    if (data.isEmpty) return;
    await _db.collection('users').doc(u.uid).update(data);
    _applyToMe(
        isPrivate: isPrivate,
        hideLikes: hideLikes,
        profileVisits: profileVisits);
  }

  /// يثبّت منشوراً أعلى ملفي أو يلغي تثبيته. يرمي [PinLimitReached] عند تجاوز الحد.
  static Future<void> setPinned(String postId, bool pin) async {
    final u = FirebaseAuth.instance.currentUser!;
    final ref = _db.collection('users').doc(u.uid);
    late List<String> result;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final ids = <String>[
        ...(snap.data()?['pinnedPostIds'] as List? ?? const [])
            .whereType<String>(),
      ]..remove(postId);
      if (pin) {
        if (ids.length >= maxPinned) throw const PinLimitReached();
        ids.insert(0, postId);
      }
      tx.update(ref, {'pinnedPostIds': ids});
      result = ids;
    });
    _applyToMe(pinnedPostIds: result);
  }

  static void _applyToMe(
      {bool? isPrivate,
      bool? hideLikes,
      bool? profileVisits,
      List<String>? pinnedPostIds}) {
    final current = me;
    if (current == null) return;
    final fresh = current.withSettings(
      isPrivate: isPrivate,
      hideLikes: hideLikes,
      profileVisits: profileVisits,
      pinnedPostIds: pinnedPostIds,
    );
    me = fresh;
    _cache[fresh.uid] = Future.value(fresh);
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

  /// يمسح الملف المخزّن مؤقتاً (مثلاً بعد قبول التوثيق) ليُقرأ من جديد.
  static void invalidate(String uid) {
    _cache.remove(uid);
    if (me?.uid == uid) {
      profileOf(uid).then((u) {
        if (u != null) me = u;
      });
    }
  }

  static Stream<AppUser?> profileStream(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((s) => s.exists ? AppUser.fromDoc(s) : null);

  static Future<AppUser?> byUsername(String username) async {
    final s = await _db.collection('usernames').doc(normalize(username)).get();
    final uid = s.data()?['uid'] as String?;
    return uid == null ? null : profileOf(uid);
  }

  static Future<List<AppUser>> _prefix(String field, String text) async {
    if (text.isEmpty) return [];
    try {
      final snap = await _db
          .collection('users')
          .where(field, isGreaterThanOrEqualTo: text)
          .where(field, isLessThan: '$text\uf8ff')
          .limit(20)
          .get();
      return snap.docs.map(AppUser.fromDoc).toList();
    } catch (_) {
      return [];
    }
  }

  /// بحث عن مستخدمين ببداية اسم المستخدم أو بداية الاسم.
  static Future<List<AppUser>> search(String q) async {
    final text = normalize(q);
    final nameText = q.trim().replaceAll('@', '');
    if (text.isEmpty) return [];
    final results = await Future.wait([
      _prefix('username', text),
      _prefix('nameLower', nameText.toLowerCase()),
      // الحسابات القديمة التي لا تملك nameLower: مطابقة بنفس حالة الأحرف.
      _prefix('name', nameText),
    ]);
    final seen = <String>{};
    final out = <AppUser>[];
    for (final list in results) {
      for (final u in list) {
        if (u.username.isNotEmpty && seen.add(u.uid)) out.add(u);
      }
    }
    return out.take(30).toList();
  }
}

/// روابط المشاركة: ثابتة وصحيحة على الويب وأندرويد.
/// (Uri.base لا يصلح على أندرويد لأنه مسار ملف محلي.)
const String kSiteOrigin = 'https://haigram.web.app';

/// رابط المنشور: haigram.web.app/p/ID
String postLinkFor(String postId) => '$kSiteOrigin/p/$postId';

/// رابط الملف الشخصي: haigram.web.app/@username
String profileLinkFor(String username) => '$kSiteOrigin/@$username';

/// اسم المستخدم من رابط (/@name أو الصيغة القديمة ?u=name).
String? usernameFromUri(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isNotEmpty && segs.first.startsWith('@') && segs.first.length > 1) {
    return segs.first.substring(1);
  }
  final u = uri.queryParameters['u'];
  return (u != null && u.isNotEmpty) ? u : null;
}

/// رقم المنشور من رابط (/p/ID أو الصيغة القديمة ?p=ID).
String? postIdFromUri(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length >= 2 && segs.first == 'p' && segs[1].isNotEmpty) {
    return segs[1];
  }
  final p = uri.queryParameters['p'];
  return (p != null && p.isNotEmpty) ? p : null;
}

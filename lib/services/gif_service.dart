import 'dart:convert';

import 'package:http/http.dart' as http;

/// صورة متحركة من GIPHY: [url] للإرسال (حجم خفيف)، [previewUrl] للمعاينة.
class GifItem {
  final String url;
  final String previewUrl;
  final int width;
  final int height;

  const GifItem({
    required this.url,
    required this.previewUrl,
    required this.width,
    required this.height,
  });

  double get aspect => height <= 0 ? 1 : width / height;
}

/// بحث GIF عبر GIPHY. المفتاح يُمرَّر عند البناء:
/// --dart-define=GIPHY_API_KEY=... ؛ بلا مفتاح يختفي زر GIF من المحادثة.
class GifService {
  static const _apiKey = String.fromEnvironment('GIPHY_API_KEY');
  static const pageSize = 24;

  static bool get enabled => _apiKey.isNotEmpty;

  /// الروابط المقبولة فقط (تطابق قواعد Firestore).
  static final RegExp _allowed =
      RegExp(r'^https://(media[0-9]*|i)\.giphy\.com/.+$');

  static bool isAllowedUrl(String url) =>
      url.length <= 500 && _allowed.hasMatch(url);

  /// الأكثر رواجاً عند ترك البحث فارغاً، وإلا نتائج البحث. [offset] للصفحات.
  static Future<List<GifItem>> load(String query, {int offset = 0}) async {
    if (!enabled) return const [];
    final term = query.trim();
    final uri = Uri.https(
      'api.giphy.com',
      term.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search',
      {
        'api_key': _apiKey,
        if (term.isNotEmpty) 'q': term.length > 50 ? term.substring(0, 50) : term,
        'limit': '$pageSize',
        'offset': '$offset',
        'rating': 'g',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('gif ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    final items = <GifItem>[];
    for (final raw in data) {
      final item = _parse(raw);
      if (item != null) items.add(item);
    }
    return items;
  }

  static GifItem? _parse(Object? raw) {
    if (raw is! Map) return null;
    final images = raw['images'];
    if (images is! Map) return null;
    final full = images['fixed_width'];
    final small = images['fixed_width_small'] ?? full;
    if (full is! Map) return null;
    final url = full['url'];
    final previewUrl = small is Map ? small['url'] : null;
    final width = int.tryParse('${full['width']}') ?? 0;
    final height = int.tryParse('${full['height']}') ?? 0;
    if (url is! String ||
        previewUrl is! String ||
        !isAllowedUrl(url) ||
        width < 1 ||
        height < 1 ||
        width > 2000 ||
        height > 2000) {
      return null;
    }
    return GifItem(
        url: url, previewUrl: previewUrl, width: width, height: height);
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import '../theme.dart';

/// ترجمة النصوص بين العربية والإنجليزية عبر خدمة MyMemory المجانية (بلا مفتاح ولا خادم).
/// لتغيير الخدمة لاحقاً (مثل Google Cloud Translation) يكفي تعديل [_one] فقط.
class TranslateService {
  TranslateService._();

  static final Map<String, String> _cache = {};
  static final RegExp _arabic =
      RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
  static final RegExp _latin = RegExp(r'[A-Za-z]');

  /// لغة التطبيق الحالية = اللغة التي نترجم إليها.
  static String get target => AppLang.isEn ? 'en' : 'ar';

  /// يخمّن لغة النص من الأحرف: 'ar' أو 'en'، وnull إن لم يكن نصاً كافياً (إيموجي/أرقام/ملصق).
  static String? detect(String text) {
    final ar = _arabic.allMatches(text).length;
    final la = _latin.allMatches(text).length;
    if (ar + la < 3) return null;
    return ar >= la ? 'ar' : 'en';
  }

  /// هل يستحق النص زر الترجمة؟ (لغته تختلف عن لغة التطبيق)
  static bool needsTranslation(String text) {
    final src = detect(text);
    return src != null && src != target;
  }

  static Future<String> translate(String text) async {
    final src = detect(text);
    final tgt = target;
    if (src == null || src == tgt) return text;
    final key = '$src>$tgt:$text';
    final cached = _cache[key];
    if (cached != null) return cached;

    final out = StringBuffer();
    for (final chunk in _chunks(text)) {
      if (chunk.trim().isEmpty) {
        out.write(chunk);
        continue;
      }
      out.write(await _one(chunk, src, tgt));
    }
    final result = out.toString().trim();
    if (result.isEmpty) throw StateError('empty translation');
    _cache[key] = result;
    return result;
  }

  /// الخدمة تقبل حتى ~500 بايت في الطلب، فنقسّم النص عند الجمل والكلمات.
  static List<String> _chunks(String text) {
    const maxBytes = 400;
    final chunks = <String>[];
    var buf = StringBuffer();
    var bytes = 0;
    void flush() {
      if (buf.isNotEmpty) chunks.add(buf.toString());
      buf = StringBuffer();
      bytes = 0;
    }

    for (final m in RegExp(r'\S+|\s+').allMatches(text)) {
      final token = m.group(0)!;
      final b = utf8.encode(token).length;
      if (bytes > 0 && bytes + b > maxBytes) flush();
      buf.write(token);
      bytes += b;
      final last = token[token.length - 1];
      if (bytes >= 150 && '.!?؟\n'.contains(last)) flush();
    }
    flush();
    return chunks;
  }

  static Future<String> _one(String q, String src, String tgt) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get',
        {'q': q, 'langpair': '$src|$tgt'});
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw StateError('translate ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = body['responseData'];
    final t = data is Map ? (data['translatedText'] ?? '').toString() : '';
    final upper = t.toUpperCase();
    if ('${body['responseStatus']}' != '200' ||
        t.isEmpty ||
        upper.startsWith('MYMEMORY WARNING') ||
        upper.contains('QUERY LENGTH LIMIT')) {
      throw StateError('translate limit');
    }
    return _unescape(t);
  }

  static String _unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// يعرض النص عبر [builder] ويضيف تحته «عرض الترجمة» / «عرض الأصل»
/// فقط إذا كانت لغة النص تختلف عن لغة التطبيق.
class TranslatableText extends StatefulWidget {
  final String text;
  final Widget Function(String shown) builder;
  final bool centered;

  const TranslatableText({
    super.key,
    required this.text,
    required this.builder,
    this.centered = false,
  });

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  bool _showTranslated = false;
  bool _loading = false;
  bool _failed = false;
  String? _result;

  @override
  void didUpdateWidget(covariant TranslatableText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _showTranslated = false;
      _loading = false;
      _failed = false;
      _result = null;
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_showTranslated) {
      setState(() => _showTranslated = false);
      return;
    }
    if (_result != null) {
      setState(() => _showTranslated = true);
      return;
    }
    final original = widget.text;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await TranslateService.translate(original);
      if (!mounted || widget.text != original) return;
      setState(() {
        _result = r;
        _showTranslated = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!TranslateService.needsTranslation(widget.text)) {
      return widget.builder(widget.text);
    }
    final shown = (_showTranslated && _result != null) ? _result! : widget.text;
    final label = _loading
        ? tr('جارٍ الترجمة...')
        : _failed
            ? tr('تعذرت الترجمة، اضغط للمحاولة')
            : _showTranslated
                ? tr('عرض الأصل')
                : tr('عرض الترجمة');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          widget.centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        widget.builder(shown),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                color: context.appColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

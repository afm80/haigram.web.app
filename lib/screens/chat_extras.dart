import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../services/presence_service.dart';
import '../theme.dart';
import 'translate_widgets.dart' show TranslateService;

// ───────────────────────────── 1) الإيموجي الكبير ─────────────────────────────

bool _isRegional(int c) => c >= 0x1F1E6 && c <= 0x1F1FF;

bool _isEmojiModifier(int c) =>
    (c >= 0x1F3FB && c <= 0x1F3FF) || // درجات البشرة
    c == 0xFE0F ||
    c == 0xFE0E ||
    c == 0x20E3 ||
    (c >= 0xE0020 && c <= 0xE007F); // وسوم الأعلام

bool _isPictographic(int c) =>
    (c >= 0x1F300 && c <= 0x1FAFF) ||
    (c >= 0x1F000 && c <= 0x1F2FF) ||
    (c >= 0x2600 && c <= 0x27BF) ||
    (c >= 0x2B00 && c <= 0x2BFF) ||
    (c >= 0x2190 && c <= 0x21FF) ||
    (c >= 0x2300 && c <= 0x23FF) ||
    (c >= 0x25A0 && c <= 0x25FF) ||
    (c >= 0x2934 && c <= 0x2935) ||
    c == 0x00A9 ||
    c == 0x00AE ||
    c == 0x203C ||
    c == 0x2049 ||
    c == 0x2122 ||
    c == 0x2139 ||
    c == 0x24C2 ||
    c == 0x3030 ||
    c == 0x303D ||
    c == 0x3297 ||
    c == 0x3299;

/// يرجع الرمز التعبيري إن كانت الرسالة رمزاً واحداً فقط (يشمل المركّب
/// كالعائلة والأعلام ودرجات البشرة)، وإلا null.
String? singleEmoji(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 40) return null;
  final r = t.runes.toList();
  var units = 0;
  var i = 0;
  while (i < r.length) {
    final c = r[i];
    if (_isRegional(c)) {
      if (i + 1 < r.length && _isRegional(r[i + 1])) {
        units++;
        i += 2;
        continue;
      }
      return null;
    }
    final isKeycapBase = (c >= 0x30 && c <= 0x39) || c == 0x23 || c == 0x2A;
    if (isKeycapBase) {
      var j = i + 1;
      if (j < r.length && r[j] == 0xFE0F) j++;
      if (j < r.length && r[j] == 0x20E3) {
        units++;
        i = j + 1;
        continue;
      }
      return null;
    }
    if (!_isPictographic(c)) return null;
    units++;
    i++;
    while (i < r.length) {
      if (_isEmojiModifier(r[i])) {
        i++;
      } else if (r[i] == 0x200D &&
          i + 1 < r.length &&
          _isPictographic(r[i + 1])) {
        i += 2;
      } else {
        break;
      }
    }
  }
  return units == 1 ? t : null;
}

// ───────────────────────────── 2) معاينة الرابط ─────────────────────────────

final RegExp _linkRegex = RegExp(r'https?://\S+|www\.\S+');

/// أول رابط في النص (بعد إزالة علامات الترقيم الأخيرة) أو null.
String? firstLink(String text) {
  final m = _linkRegex.firstMatch(text);
  if (m == null) return null;
  var url = m.group(0)!;
  while (url.isNotEmpty && '.,!?؟،;:)]}'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  if (url.isEmpty) return null;
  if (url.startsWith('www.')) url = 'https://$url';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return url;
}

class LinkPreviewData {
  final String title;
  final String? description;
  final String? image;
  final String host;
  const LinkPreviewData({
    required this.title,
    required this.host,
    this.description,
    this.image,
  });
}

/// يجلب عنوان الصفحة وصورتها عبر خدمة Microlink (تدعم CORS فتعمل من المتصفح
/// بلا خادم). لتغيير الخدمة لاحقاً يكفي تعديل [_load] فقط.
class LinkPreviewService {
  LinkPreviewService._();

  static final Map<String, Future<LinkPreviewData?>> _cache = {};

  static Future<LinkPreviewData?> fetch(String url) =>
      _cache.putIfAbsent(url, () => _load(url));

  static Future<LinkPreviewData?> _load(String url) async {
    try {
      final uri = Uri.https('api.microlink.io', '/', {'url': url});
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['status'] != 'success') return null;
      final data = body['data'];
      if (data is! Map) return null;
      String? pickUrl(Object? v) {
        if (v is Map) {
          final u = (v['url'] ?? '').toString().trim();
          return u.isEmpty ? null : u;
        }
        return null;
      }

      final title = (data['title'] ?? '').toString().trim();
      final description = (data['description'] ?? '').toString().trim();
      final image = pickUrl(data['image']) ?? pickUrl(data['logo']);
      if (title.isEmpty && image == null) return null;
      return LinkPreviewData(
        title: title,
        description: description.isEmpty ? null : description,
        image: image,
        host: Uri.parse(url).host.replaceFirst(RegExp(r'^www\.'), ''),
      );
    } catch (_) {
      return null;
    }
  }
}

/// بطاقة الرابط: صورة + عنوان + اسم الموقع. لا تظهر شيئاً إن تعذّر الجلب.
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool mine;
  const LinkPreviewCard({super.key, required this.url, required this.mine});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  late Future<LinkPreviewData?> _future;

  @override
  void initState() {
    super.initState();
    _future = LinkPreviewService.fetch(widget.url);
  }

  @override
  void didUpdateWidget(covariant LinkPreviewCard old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _future = LinkPreviewService.fetch(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mine = widget.mine;
    return FutureBuilder<LinkPreviewData?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => launchUrl(Uri.parse(widget.url),
              mode: LaunchMode.externalApplication),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: mine ? Colors.white.withOpacity(0.14) : colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.image != null)
                  AspectRatio(
                    aspectRatio: 1.91,
                    child: Image.network(
                      data.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colors.surfaceHigh,
                        alignment: Alignment.center,
                        child: Icon(Icons.link_rounded, color: colors.textDim),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: mine ? Colors.white70 : colors.textDim,
                        ),
                      ),
                      if (data.title.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: mine ? Colors.white : colors.text,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────── 3) آخر نشاط ─────────────────────────────

/// «نشط قبل 5 دقائق» أو null إن كان قديماً جداً (أكثر من 30 يوماً).
String? lastActiveLabel(DateTime at) {
  final d = PresenceService.serverNow.difference(at);
  if (d.isNegative || d.inMinutes < 1) return tr('نشط قبل لحظات');
  if (d.inMinutes < 60) {
    final n = d.inMinutes;
    if (n == 1) return tr('نشط قبل دقيقة');
    if (n == 2) return tr('نشط قبل دقيقتين');
    return trf(n <= 10 ? 'نشط قبل {0} دقائق' : 'نشط قبل {0} دقيقة', [n]);
  }
  if (d.inHours < 24) {
    final n = d.inHours;
    if (n == 1) return tr('نشط قبل ساعة');
    if (n == 2) return tr('نشط قبل ساعتين');
    return trf(n <= 10 ? 'نشط قبل {0} ساعات' : 'نشط قبل {0} ساعة', [n]);
  }
  if (d.inDays <= 30) {
    final n = d.inDays;
    if (n == 1) return tr('نشط قبل يوم');
    if (n == 2) return tr('نشط قبل يومين');
    return trf(n <= 10 ? 'نشط قبل {0} أيام' : 'نشط قبل {0} يوماً', [n]);
  }
  return null;
}

/// نص آخر نشاط للطرف الآخر (يتجدد كل نصف دقيقة)، ويعرض [fallback] إن لم يُعرف.
class LastActiveText extends StatefulWidget {
  final String uid;
  final String fallback;
  final TextStyle style;
  const LastActiveText({
    super.key,
    required this.uid,
    required this.fallback,
    required this.style,
  });

  @override
  State<LastActiveText> createState() => _LastActiveTextState();
}

class _LastActiveTextState extends State<LastActiveText> {
  StreamSubscription<DateTime?>? _sub;
  Timer? _tick;
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _listen();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = PresenceService.lastActive(widget.uid).listen(
      (value) {
        if (mounted) setState(() => _at = value);
      },
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(covariant LastActiveText old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) {
      _at = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    final label = at == null ? null : lastActiveLabel(at);
    return Text(
      label ?? widget.fallback,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}

// ───────────────────────────── 4) ألوان المحادثة ─────────────────────────────

class ChatTheme {
  final String id;
  final String name;
  final Color color;
  const ChatTheme(this.id, this.name, this.color);

  static const defaultId = 'default';

  static const all = <ChatTheme>[
    ChatTheme('default', 'الافتراضي', AppColors.brandPurple),
    ChatTheme('ocean', 'أزرق', Color(0xFF1E6FD9)),
    ChatTheme('sunset', 'برتقالي', Color(0xFFE8590C)),
    ChatTheme('forest', 'أخضر', Color(0xFF2F855A)),
    ChatTheme('rose', 'وردي', Color(0xFFD6336C)),
    ChatTheme('night', 'نيلي', Color(0xFF4C51BF)),
    ChatTheme('gold', 'ذهبي', Color(0xFFB7791F)),
    ChatTheme('slate', 'رمادي', Color(0xFF52606D)),
  ];

  static ChatTheme byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}

/// اختيار المستخدم لمحادثة: اللون + هل تُطبَّق خلفية ملونة.
class ChatLook {
  final String themeId;
  final bool background;
  const ChatLook({this.themeId = ChatTheme.defaultId, this.background = false});

  ChatTheme get theme => ChatTheme.byId(themeId);
  Color get bubble => theme.color;
  bool get isDefault => themeId == ChatTheme.defaultId && !background;

  /// خلفية متدرجة خفيفة من لون المحادثة فوق لون الخلفية الأساسي، أو null.
  Decoration? backgroundDecoration(Color base) {
    if (!background) return null;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(theme.color.withOpacity(0.24), base),
          Color.alphaBlend(theme.color.withOpacity(0.06), base),
        ],
      ),
    );
  }

  ChatLook copyWith({String? themeId, bool? background}) => ChatLook(
        themeId: themeId ?? this.themeId,
        background: background ?? this.background,
      );
}

/// تخزين محلي لخيارات المحادثة (على هذا الجهاز) بنفس أسلوب المسودات.
class ChatPrefs {
  ChatPrefs._();

  static String _lookKey(String uid, String cid) => 'chat_look_${uid}_$cid';
  static String _nickKey(String uid, String other) => 'chat_nick_${uid}_$other';

  static Future<ChatLook> loadLook(String uid, String cid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_lookKey(uid, cid));
      if (raw == null) return const ChatLook();
      final parts = raw.split('|');
      return ChatLook(
        themeId: ChatTheme.byId(parts.first).id,
        background: parts.length > 1 && parts[1] == '1',
      );
    } catch (_) {
      return const ChatLook();
    }
  }

  static Future<void> saveLook(String uid, String cid, ChatLook look) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (look.isDefault) {
        await p.remove(_lookKey(uid, cid));
      } else {
        await p.setString(
            _lookKey(uid, cid), '${look.themeId}|${look.background ? 1 : 0}');
      }
    } catch (_) {}
  }

  static Future<String> loadNickname(String uid, String other) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_nickKey(uid, other)) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveNickname(
      String uid, String other, String nickname) async {
    try {
      final p = await SharedPreferences.getInstance();
      final value = nickname.trim();
      if (value.isEmpty) {
        await p.remove(_nickKey(uid, other));
      } else {
        await p.setString(_nickKey(uid, other), value);
      }
    } catch (_) {}
  }
}

/// ورقة اختيار لون/خلفية المحادثة. [onChanged] تُستدعى فور كل تغيير (معاينة حيّة).
Future<void> showChatLookSheet(
  BuildContext context, {
  required ChatLook initial,
  required ValueChanged<ChatLook> onChanged,
}) {
  var look = initial;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final colors = sheetContext.appColors;
        void change(ChatLook next) {
          setSheetState(() => look = next);
          onChanged(next);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('ألوان المحادثة'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final t in ChatTheme.all)
                      GestureDetector(
                        onTap: () => change(look.copyWith(themeId: t.id)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: t.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: look.themeId == t.id
                                      ? colors.text
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: look.themeId == t.id
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(t.name),
                              style: TextStyle(
                                  fontSize: 11, color: colors.textDim),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('خلفية ملونة')),
                  value: look.background,
                  onChanged: (v) => change(look.copyWith(background: v)),
                ),
                if (!look.isDefault)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => change(const ChatLook()),
                      child: Text(tr('إعادة الافتراضي')),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// ───────────────────────────── 5) الكنية ─────────────────────────────

/// يرجع الكنية الجديدة ('' = إزالتها)، أو null إن أُلغي الحوار.
Future<String?> showNicknameDialog(
  BuildContext context, {
  required String current,
  required String realName,
}) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('تعيين كنية')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trf('اسم خاص بـ {0} يظهر لك أنت فقط في هذه المحادثة.', [realName]),
            style: TextStyle(
                fontSize: 13, color: dialogContext.appColors.textDim),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: InputDecoration(hintText: tr('الكنية')),
            onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
          ),
        ],
      ),
      actions: [
        if (current.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Text(tr('إزالة الكنية')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(tr('حفظ')),
        ),
      ],
    ),
  );
}

// ───────────────────────────── 6) ترجمة الرسالة ─────────────────────────────

/// ورقة تعرض ترجمة الرسالة (إلى لغة التطبيق) مع نسخ الترجمة.
Future<void> showTranslationSheet(BuildContext context, String text) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TranslationSheet(text: text),
  );
}

class _TranslationSheet extends StatefulWidget {
  final String text;
  const _TranslationSheet({required this.text});

  @override
  State<_TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends State<_TranslationSheet> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = TranslateService.translate(widget.text);
  }

  void _retry() {
    setState(() => _future = TranslateService.translate(widget.text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: FutureBuilder<String>(
          future: _future,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState != ConnectionState.done;
            final failed = snapshot.hasError;
            final result = snapshot.data;
            final same = result != null && result.trim() == widget.text.trim();
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('ترجمة الرسالة'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('الأصل'),
                      style: TextStyle(fontSize: 12, color: colors.textDim)),
                  const SizedBox(height: 4),
                  Text(widget.text, style: const TextStyle(fontSize: 15)),
                  const Divider(height: 28),
                  Text(tr('الترجمة'),
                      style: TextStyle(fontSize: 12, color: colors.textDim)),
                  const SizedBox(height: 4),
                  if (waiting)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(tr('جارٍ الترجمة...'),
                            style: TextStyle(color: colors.textDim)),
                      ],
                    )
                  else if (failed)
                    Row(
                      children: [
                        Expanded(
                          child: Text(tr('تعذرت الترجمة'),
                              style: TextStyle(color: colors.textDim)),
                        ),
                        TextButton(
                          onPressed: _retry,
                          child: Text(tr('إعادة المحاولة')),
                        ),
                      ],
                    )
                  else if (same)
                    Text(tr('الرسالة بلغتك بالفعل'),
                        style: TextStyle(color: colors.textDim))
                  else ...[
                    Text(result ?? '', style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          Clipboard.setData(ClipboardData(text: result ?? ''));
                          Navigator.pop(context);
                          messenger.showSnackBar(
                            SnackBar(content: Text(tr('تم نسخ الترجمة'))),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: Text(tr('نسخ')),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

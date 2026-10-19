import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'sticker_data.dart';

import '../l10n.dart';

/// رابط صورة Twemoji الملوّنة (مفتوحة الترخيص CC-BY 4.0) للإيموجي [emoji].
/// تظهر بألوانها على كل الأجهزة والمتصفحات دون الاعتماد على خط النظام.
String stickerImageUrl(String emoji) {
  final hasZwj = emoji.runes.contains(0x200D);
  final cps = emoji.runes
      .where((r) => hasZwj || r != 0xFE0F)
      .map((r) => r.toRadixString(16))
      .join('-');
  return 'https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/72x72/$cps.png';
}

/// إيموجي ملوّن: صورة Twemoji (CC-BY 4.0) فتظهر بألوانها على كل الأجهزة.
/// (خط الإيموجي في canvaskit كان يظهر أبيض وأسود). يرجع إلى النص إن تعذر التحميل.
class StickerGlyph extends StatelessWidget {
  final String emoji;
  final double size;
  const StickerGlyph(this.emoji, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(emoji,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: size * 0.8, height: 1.1));
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        stickerImageUrl(emoji),
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(child: fallback),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const SizedBox.shrink(),
      ),
    );
  }
}

Set<String>? _stickerSet;
int _maxStickerLen = 1;

Set<String> get _allStickers {
  final cached = _stickerSet;
  if (cached != null) return cached;
  final all = <String>{
    for (final category in stickerCategories) ...category.items,
  };
  for (final s in all) {
    if (s.length > _maxStickerLen) _maxStickerLen = s.length;
  }
  return _stickerSet = all;
}

/// يقسّم [text] إلى ملصقات منفصلة، أو يرجع null إن كان فيه أي شيء غير الملصقات.
List<String>? parseStickers(String text) {
  final all = _allStickers;
  final t = text.replaceAll(RegExp(r'\s+'), '');
  if (t.isEmpty) return null;
  final out = <String>[];
  var i = 0;
  while (i < t.length) {
    String? found;
    final maxLen = _maxStickerLen < t.length - i ? _maxStickerLen : t.length - i;
    for (var len = maxLen; len >= 1; len--) {
      final part = t.substring(i, i + len);
      if (all.contains(part)) {
        found = part;
        break;
      }
    }
    if (found == null) return null;
    out.add(found);
    i += found.length;
  }
  return out;
}

/// هل الرسالة كلها ملصقات فقط (حتى 3 ملصقات)؟ فتُعرض كبيرة مثل واتساب.
/// الحد 24 حرفاً يطابق قواعد Firestore الحالية فلا تحتاج تعديلها.
bool isStickerOnly(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 24) return false;
  final list = parseStickers(t);
  return list != null && list.length <= 3;
}

/// يعرض رسالة الملصقات: واحد كبير، أو 2-3 بحجم أصغر قليلاً.
class StickerMessage extends StatelessWidget {
  final String text;
  final double base;
  const StickerMessage(this.text, {super.key, this.base = 56});

  @override
  Widget build(BuildContext context) {
    final list = parseStickers(text) ?? [text];
    final size = list.length == 1
        ? base
        : list.length == 2
            ? base * 0.85
            : base * 0.7;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [for (final s in list) StickerGlyph(s, size: size)],
    );
  }
}

/// يُدخل [insert] في موضع المؤشر داخل خانة الكتابة (ولا يرسله).
void insertAtCursor(TextEditingController controller, String insert) {
  final text = controller.text;
  final selection = controller.selection;
  final start = selection.isValid
      ? selection.start.clamp(0, text.length).toInt()
      : text.length;
  final end = selection.isValid
      ? selection.end.clamp(start, text.length).toInt()
      : start;
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

/// يحذف الملصق (أو المحرف) الذي قبل المؤشر، أو النص المحدد.
void deleteBeforeCursor(TextEditingController controller) {
  final text = controller.text;
  final sel = controller.selection;
  var start = sel.isValid ? sel.start.clamp(0, text.length).toInt() : text.length;
  final end = sel.isValid ? sel.end.clamp(0, text.length).toInt() : text.length;
  if (start == end) {
    if (end == 0) return;
    final before = text.substring(0, end);
    var cut = 1;
    final all = _allStickers;
    final maxLen = _maxStickerLen < end ? _maxStickerLen : end;
    var matched = false;
    for (var len = maxLen; len >= 1; len--) {
      if (all.contains(before.substring(end - len))) {
        cut = len;
        matched = true;
        break;
      }
    }
    if (!matched) {
      final last = before.codeUnitAt(end - 1);
      if (last >= 0xDC00 && last <= 0xDFFF && end >= 2) cut = 2;
    }
    start = end - cut;
  }
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, ''),
    selection: TextSelection.collapsed(offset: start),
  );
}

/// لوحة الملصقات بنمط واتساب/انستغرام: تظهر مكان الكيبورد تحت خانة الكتابة،
/// وتبقى مفتوحة، وكل نقرة تضيف ملصقاً في المحرر (يمكن اختيار عدة ملصقات).
class StickerPanel extends StatefulWidget {
  /// خانة الكتابة التي تُدخَل فيها الملصقات. اتركها null مع [onPick] لاختيار ملصق واحد
  /// (مثل التفاعل على رسالة): فيُرجَع الملصق عبر [onPick] ويُخفى زر الحذف.
  final TextEditingController? controller;
  final void Function(String sticker)? onPick;
  final double height;
  const StickerPanel(
      {super.key, this.controller, this.onPick, this.height = 280});

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  static const _prefsKey = 'recent_stickers';
  static List<String> _recents = [];
  static bool _recentsLoaded = false;

  int _index = 1;
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    if (_recents.isNotEmpty) _index = 0;
    _loadRecents();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    if (_recentsLoaded) return;
    _recentsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey) ?? const <String>[];
      if (saved.isNotEmpty && _recents.isEmpty) {
        _recents = saved;
        if (mounted) setState(() => _index = 0);
      }
    } catch (_) {}
  }

  Future<void> _saveRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _recents);
    } catch (_) {}
  }

  void _pick(String sticker) {
    HapticFeedback.selectionClick();
    final pick = widget.onPick;
    final controller = widget.controller;
    if (pick != null) {
      pick(sticker);
    } else if (controller != null) {
      insertAtCursor(controller, sticker);
    }
    _recents = [sticker, ..._recents.where((e) => e != sticker)].take(32).toList();
    _saveRecents();
  }

  void _backspace() {
    final controller = widget.controller;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    deleteBeforeCursor(controller);
  }

  void _startRepeat() {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) => _backspace());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // الفهرس 0 = الأحدث، وبعده فئات الملصقات.
    final tabCount = stickerCategories.length + 1;
    var items = _index == 0 ? _recents : stickerCategories[_index - 1].items;
    // التفاعل على رسالة محدود بـ 8 أحرف في قواعد Firestore، فنخفي الأطول.
    if (widget.onPick != null) {
      items = items.where((e) => e.length <= 8).toList();
    }
    final title = _index == 0 ? 'الأحدث' : stickerCategories[_index - 1].title;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.surfaceHigh)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: tabCount,
                    itemBuilder: (context, i) {
                      final selected = i == _index;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _index = i),
                        child: Container(
                          width: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: selected
                                    ? AppColors.brandPurple
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                          child: i == 0
                              ? Icon(Icons.access_time_rounded,
                                  size: 22,
                                  color: selected
                                      ? AppColors.brandPurple
                                      : colors.textDim)
                              : Opacity(
                                  opacity: selected ? 1 : 0.6,
                                  child: StickerGlyph(
                                      stickerCategories[i - 1].icon,
                                      size: 22),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.controller != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _backspace,
                  onLongPressStart: (_) => _startRepeat(),
                  onLongPressEnd: (_) => _stopRepeat(),
                  onLongPressCancel: _stopRepeat,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(Icons.backspace_outlined,
                        size: 22, color: colors.textDim),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                tr(title),
                style: TextStyle(
                  color: colors.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      tr('لا توجد ملصقات حديثة بعد'),
                      style: TextStyle(color: colors.textDim, fontSize: 13),
                    ),
                  )
                : GridView.builder(
                    key: ValueKey(_index),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 48,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final sticker = items[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _pick(sticker),
                        child: Center(child: StickerGlyph(sticker, size: 32)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

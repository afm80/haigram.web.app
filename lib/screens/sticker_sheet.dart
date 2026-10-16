import 'package:flutter/material.dart';

import '../theme.dart';
import 'sticker_data.dart';

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

/// ملصق/إيموجي ملوّن: صورة Twemoji، ويرجع إلى النص إن تعذر تحميلها.
class StickerGlyph extends StatelessWidget {
  final String emoji;
  final double size;
  const StickerGlyph(this.emoji, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.9));
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

/// نافذة الملصقات بنمط تيك توك: ورقة كبيرة تُسحب لأعلى، وتبويبات للفئات
/// وشبكة كبيرة بدل القائمة الصغيرة.
Future<void> showStickerSheet(
  BuildContext context, {
  required void Function(String sticker) onPick,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StickerSheet(onPick: onPick),
  );
}

class _StickerSheet extends StatefulWidget {
  final void Function(String sticker) onPick;
  const _StickerSheet({required this.onPick});

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final category = stickerCategories[_index];
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textDim.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: stickerCategories.length,
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () => setState(() => _index = i),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.textDim.withOpacity(0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: StickerGlyph(stickerCategories[i].icon, size: 26),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  category.title,
                  style: TextStyle(
                    color: colors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: ValueKey(_index),
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 52,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: category.items.length,
                itemBuilder: (context, i) {
                  final sticker = category.items[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPick(sticker);
                    },
                    child: Center(
                      child: StickerGlyph(sticker, size: 34),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
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

Set<String>? _allStickers;

/// هل النص كله ملصق واحد؟ (فيُرسل بشكل ملصق كبير بدل نص عادي).
bool isSingleSticker(String text) {
  final all = _allStickers ??= {
    for (final category in stickerCategories) ...category.items,
  };
  return text.length <= 24 && all.contains(text);
}

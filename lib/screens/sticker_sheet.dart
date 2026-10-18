import 'package:flutter/material.dart';

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
        filterQuality: FilterQuality.high,
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textDim.withOpacity(0.42),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('الملصقات'),
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: colors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: stickerCategories.length,
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () => setState(() => _index = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.brandPurple.withOpacity(0.12)
                            : colors.surfaceHigh,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.brandPurple.withOpacity(0.35)
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: StickerGlyph(stickerCategories[i].icon, size: 28),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tr(category.title),
                  style: TextStyle(
                    color: colors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: ValueKey(_index),
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 74,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: category.items.length,
                itemBuilder: (context, i) {
                  final sticker = category.items[i];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onPick(sticker);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: colors.textDim.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: StickerGlyph(sticker, size: 42),
                        ),
                      ),
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

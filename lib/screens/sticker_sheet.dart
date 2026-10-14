import 'package:flutter/material.dart';

import '../theme.dart';
import 'sticker_data.dart';

/// نافذة الملصقات بنمط تيك توك: ورقة كبيرة تُسحب لأعلى، وتبويبات للفئات
/// وشبكة كبيرة بدل القائمة الصغيرة.
Future<void> showStickerSheet(
  BuildContext context, {
  required void Function(String sticker) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
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
                      child: Text(stickerCategories[i].icon,
                          style: const TextStyle(fontSize: 22)),
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
                      child: Text(sticker,
                          style: const TextStyle(fontSize: 30)),
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

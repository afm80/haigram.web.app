import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import 'sticker_sheet.dart';

/// ملصق إيموجي موضوع فوق صورة القصة.
/// [dx] و[dy] موضع مركزه كنسبة (0 إلى 1) من عرض الصورة وارتفاعها.
class StoryStickerItem {
  final String emoji;
  double dx;
  double dy;
  double scale;
  double baseScale;
  StoryStickerItem(this.emoji,
      {this.dx = 0.5, this.dy = 0.45, this.scale = 1, this.baseScale = 1});
}

/// طبقة الملصقات فوق الصورة: سحب للتحريك، وإصبعان للتكبير،
/// والسحب إلى السلة (أسفل الصورة) للحذف.
/// يجب وضعها داخل Positioned.fill فوق الصورة تماماً.
class StickerLayer extends StatefulWidget {
  final List<StoryStickerItem> items;
  final bool enabled;
  final VoidCallback? onChanged;

  /// يُستدعى عند لمس ملصق (true) وعند رفع الإصبع (false)،
  /// ليوقف الشاشة التمرير أثناء تحريك الملصق.
  final ValueChanged<bool>? onTouching;
  const StickerLayer(
      {super.key,
      required this.items,
      this.enabled = true,
      this.onChanged,
      this.onTouching});

  @override
  State<StickerLayer> createState() => _StickerLayerState();
}

class _StickerLayerState extends State<StickerLayer> {
  static const _trashY = 0.86;
  StoryStickerItem? _active; // الملصق قيد السحب
  int _pointers = 0;

  void _down() {
    _pointers++;
    if (_pointers == 1) widget.onTouching?.call(true);
  }

  void _up() {
    if (_pointers == 0) return;
    _pointers--;
    if (_pointers == 0) widget.onTouching?.call(false);
  }

  Widget _sticker(StoryStickerItem it, double w, double h) {
    final size = w * 0.25 * it.scale;
    return Positioned(
      key: ObjectKey(it),
      left: it.dx * w - size / 2,
      top: it.dy * h - size / 2,
      width: size,
      height: size,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.enabled
            ? (_) {
                it.baseScale = it.scale;
                setState(() => _active = it);
              }
            : null,
        onScaleUpdate: widget.enabled
            ? (d) {
                setState(() {
                  it.dx = (it.dx + d.focalPointDelta.dx / w)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  it.dy = (it.dy + d.focalPointDelta.dy / h)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  it.scale =
                      (it.baseScale * d.scale).clamp(0.4, 3.0).toDouble();
                });
              }
            : null,
        onScaleEnd: widget.enabled
            ? (_) {
                final remove = it.dy > _trashY;
                setState(() {
                  _active = null;
                  if (remove) widget.items.remove(it);
                });
                if (remove) widget.onChanged?.call();
              }
            : null,
        child: StickerGlyph(it.emoji, size: size),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final over = _active != null && _active!.dy > _trashY;
        final trashSize = over ? 56.0 : 46.0;
        return Stack(
          children: [
            for (final it in widget.items) _sticker(it, w, h),
            if (_active != null)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: trashSize,
                    height: trashSize,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: over ? Colors.red : Colors.black54),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// يلتقط ما يعرضه [key] (الصورة مع ملصقاتها) ويعيده JPEG جاهزاً للرفع.
/// [original] هي الصورة الأصلية، ونأخذ منها العرض بالبكسل حتى لا تنخفض الجودة.
/// يعيد null إن تعذّر الالتقاط.
Future<Uint8List?> bakeStickers(GlobalKey key, Uint8List original,
    {required int maxBytes}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final src = await decodeImageFromList(original);
  final srcWidth = src.width;
  src.dispose();
  final ratio = (srcWidth / boundary.size.width).clamp(0.5, 4.0).toDouble();
  final snap = await boundary.toImage(pixelRatio: ratio);
  final png = await snap.toByteData(format: ui.ImageByteFormat.png);
  snap.dispose();
  if (png == null) return null;
  final decoded = img.decodePng(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
  if (decoded == null) return null;
  var out = img.encodeJpg(decoded, quality: 85);
  if (out.length > maxBytes) out = img.encodeJpg(decoded, quality: 65);
  return out;
}

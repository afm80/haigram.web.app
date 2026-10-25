import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import 'sticker_sheet.dart';
import 'story_text_editor.dart' show storyTextWidget;

/// ملصق إيموجي موضوع فوق صورة القصة.
/// [dx] و[dy] موضع مركزه كنسبة (0 إلى 1) من عرض الصورة وارتفاعها.
class StoryStickerItem {
  final String emoji;
  // نص مكتوب فوق الصورة (بدل الإيموجي): النص ولونه ونمطه (0 ظل، 1 مربع، 2 إطار).
  String? text;
  Color color;
  int style;
  double dx;
  double dy;
  double scale;
  double baseScale;
  StoryStickerItem(this.emoji,
      {this.dx = 0.5, this.dy = 0.45, this.scale = 1, this.baseScale = 1})
      : text = null,
        color = Colors.white,
        style = 0;
  StoryStickerItem.text(String this.text,
      {this.color = Colors.white,
      this.style = 0,
      this.dx = 0.5,
      this.dy = 0.45,
      this.scale = 1,
      this.baseScale = 1})
      : emoji = '';

  bool get isText => text != null;
}

/// طبقة الملصقات فوق الصورة: سحب للتحريك، وإصبعان للتكبير،
/// والسحب إلى السلة (أسفل الصورة) للحذف.
/// يجب وضعها داخل Positioned.fill فوق الصورة تماماً.
class StickerLayer extends StatefulWidget {
  final List<StoryStickerItem> items;
  final bool enabled;
  final VoidCallback? onChanged;

  /// يُستدعى عند الضغط على نص (لتعديله).
  final ValueChanged<StoryStickerItem>? onEditText;

  /// يُستدعى عند لمس ملصق (true) وعند رفع الإصبع (false)،
  /// ليوقف الشاشة التمرير أثناء تحريك الملصق.
  final ValueChanged<bool>? onTouching;
  const StickerLayer(
      {super.key,
      required this.items,
      this.enabled = true,
      this.onChanged,
      this.onEditText,
      this.onTouching});

  @override
  State<StickerLayer> createState() => _StickerLayerState();
}

class _StickerLayerState extends State<StickerLayer> {
  static const _trashY = 0.86;
  // مساحة لمس إضافية حول الملصق حتى يسهل وضع الإصبعين عليه عند التكبير.
  static const _hitPad = 36.0;
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
    final box = it.isText
        ? Positioned(
            key: ObjectKey(it),
            left: it.dx * w,
            top: it.dy * h,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w * 0.92),
                child: _gestures(
                  it,
                  w,
                  h,
                  Padding(
                    padding: const EdgeInsets.all(_hitPad),
                    child: storyTextWidget(
                        it.text!, it.color, it.style, w * 0.07 * it.scale),
                  ),
                ),
              ),
            ),
          )
        : null;
    if (box != null) return box;
    return Positioned(
      key: ObjectKey(it),
      left: it.dx * w - size / 2 - _hitPad,
      top: it.dy * h - size / 2 - _hitPad,
      width: size + 2 * _hitPad,
      height: size + 2 * _hitPad,
      child: _gestures(
        it,
        w,
        h,
        Padding(
          padding: const EdgeInsets.all(_hitPad),
          child: StickerGlyph(it.emoji, size: size),
        ),
      ),
    );
  }

  Widget _gestures(StoryStickerItem it, double w, double h, Widget child) {
    return Builder(builder: (context) {
      return Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        // عجلة الماوس (على الكمبيوتر) تكبّر وتصغّر الملصق.
        onPointerSignal: widget.enabled
            ? (e) {
                if (e is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(e,
                      (ev) {
                    final dy = (ev as PointerScrollEvent).scrollDelta.dy;
                    setState(() {
                      it.scale =
                          (it.scale - dy * 0.002).clamp(0.4, 3.0).toDouble();
                    });
                  });
                }
              }
            : null,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.enabled
            ? (_) {
                it.baseScale = it.scale;
                if (_active != it) setState(() => _active = it);
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
            ? (e) {
                // رفع أحد الإصبعين فقط لا ينهي التحريك (كان يسبّب وميض السلة
                // وحذفاً غير مقصود)؛ ننهي عند رفع آخر إصبع.
                if (e.pointerCount > 0) return;
                final remove = it.dy > _trashY;
                setState(() {
                  _active = null;
                  if (remove) widget.items.remove(it);
                });
                if (remove) widget.onChanged?.call();
              }
            : null,
        onTap: widget.enabled && it.isText
            ? () => widget.onEditText?.call(it)
            : null,
        child: child,
        ),
      );
    });
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

/// يلتقط طبقة النص والملصقات والرسم فقط (PNG بخلفية شفافة) لقصة الفيديو.
/// [targetWidth] عرض الناتج بالبكسل (يطابق عرض الفيديو بحدّ أقصى 1080).
Future<Uint8List?> bakeOverlayPng(GlobalKey key, {required int targetWidth}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final ratio =
      (targetWidth.clamp(360, 1080) / boundary.size.width).clamp(0.5, 4.0).toDouble();
  final snap = await boundary.toImage(pixelRatio: ratio);
  final png = await snap.toByteData(format: ui.ImageByteFormat.png);
  snap.dispose();
  if (png == null) return null;
  return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
}

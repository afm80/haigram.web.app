import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../l10n.dart';
import '../net_error.dart';
import '../theme.dart';

/// يفتح محرر صورة القصة: قص بنسب جاهزة (9:16 و4:5 و1:1 والأصلية)،
/// تدوير 90°، وقلب أفقي. يعيد JPEG جاهزاً، أو null عند الإلغاء.
Future<Uint8List?> editStoryPhoto(BuildContext context, Uint8List bytes,
        {required int maxBytes}) =>
    Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StoryPhotoEditor(bytes: bytes, maxBytes: maxBytes),
      ),
    );

class _Ratio {
  final String label;
  final double? ratio; // العرض ÷ الارتفاع، وnull = نسبة الصورة الأصلية
  const _Ratio(this.label, this.ratio);
}

class _StoryPhotoEditor extends StatefulWidget {
  final Uint8List bytes;
  final int maxBytes;
  const _StoryPhotoEditor({required this.bytes, required this.maxBytes});

  @override
  State<_StoryPhotoEditor> createState() => _StoryPhotoEditorState();
}

class _StoryPhotoEditorState extends State<_StoryPhotoEditor> {
  static const _ratios = [
    _Ratio('9:16', 9 / 16),
    _Ratio('4:5', 4 / 5),
    _Ratio('1:1', 1),
    _Ratio('الأصلية', null),
  ];

  late Uint8List _bytes = widget.bytes;
  final _controller = TransformationController();
  Size? _imageSize;
  int _ratioIndex = 0;
  bool _needsCentering = true;
  bool _busy = false;
  bool _changed = false; // تدوير أو قلب (يتطلب إعادة ترميز)
  Size _boxSize = const Size(300, 300);
  String? _error;

  @override
  void initState() {
    super.initState();
    _decodeSize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decodeSize() async {
    try {
      final codec = await ui.instantiateImageCodec(_bytes);
      final frame = await codec.getNextFrame();
      final size =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _needsCentering = true;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = tr('تعذر قراءة الصورة'));
    }
  }

  Future<void> _transform(String op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await compute(_transformJob, <Object>[_bytes, op]);
      if (out == null) throw StateError(tr('صيغة غير مدعومة'));
      _bytes = out;
      _changed = true;
      _imageSize = null;
      _controller.value = Matrix4.identity();
      await _decodeSize();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = friendlyError(e, fallback: tr('تعذر تعديل الصورة')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setRatio(int i) {
    if (i == _ratioIndex || _busy) return;
    setState(() {
      _ratioIndex = i;
      _needsCentering = true;
      _controller.value = Matrix4.identity();
    });
  }

  /// أبعاد صندوق القص داخل المساحة المتاحة بحسب النسبة المختارة.
  Size _fitBox(double maxW, double maxH, Size image) {
    final a = _ratios[_ratioIndex].ratio ?? (image.width / image.height);
    var w = maxW;
    var h = w / a;
    if (h > maxH) {
      h = maxH;
      w = h * a;
    }
    return Size(w, h);
  }

  Future<void> _done() async {
    if (_busy) return;
    final size = _imageSize;
    if (size == null) return;
    setState(() => _busy = true);
    try {
      final box = _boxSize;
      // القص يُحسب من موضع الصورة وتكبيرها (بدون التقاط الشاشة).
      final scale0 = math.max(box.width / size.width, box.height / size.height);
      final childW = size.width * scale0;
      final childH = size.height * scale0;
      final m = _controller.value;
      final s = m.getMaxScaleOnAxis();
      final fx = (-m.storage[12] / s) / childW;
      final fy = (-m.storage[13] / s) / childH;
      final fw = (box.width / s) / childW;
      final fh = (box.height / s) / childH;
      final out = await compute(_cropJob, <Object>[
        _bytes,
        fx,
        fy,
        fw,
        fh,
        widget.maxBytes,
      ]);
      if (out == null) throw StateError(tr('تعذر قص الصورة'));
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, fallback: tr('تعذر قص الصورة'));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('تعديل الصورة')),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: _busy || _imageSize == null ? null : _done,
              child: Text(tr('تم'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final size = _imageSize;
                if (size == null) {
                  return Center(
                    child: _error != null
                        ? Text(_error!,
                            style: const TextStyle(color: Colors.white))
                        : const CircularProgressIndicator(),
                  );
                }
                final box = _fitBox(c.maxWidth - 24, c.maxHeight - 16, size);
                _boxSize = box;
                final scale =
                    math.max(box.width / size.width, box.height / size.height);
                final w = size.width * scale;
                final h = size.height * scale;
                if (_needsCentering) {
                  _needsCentering = false;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _controller.value = Matrix4.translationValues(
                        -(w - box.width) / 2, -(h - box.height) / 2, 0);
                  });
                }
                return Center(
                  child: SizedBox(
                    width: box.width,
                    height: box.height,
                    child: Stack(
                      children: [
                        ClipRect(
                          child: InteractiveViewer(
                            key: ValueKey('$_ratioIndex-${_bytes.length}'),
                            transformationController: _controller,
                            constrained: false,
                            minScale: 1,
                            maxScale: 6,
                            boundaryMargin: EdgeInsets.zero,
                            child: SizedBox(
                              width: w,
                              height: h,
                              child: Image.memory(_bytes,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true),
                            ),
                          ),
                        ),
                        // إطار وخطوط ثلث للتوجيه (لا تدخل في الصورة الناتجة).
                        IgnorePointer(
                          child: CustomPaint(
                            size: box,
                            painter: _GridPainter(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            if (_error != null && _imageSize != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.accent2)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  for (var i = 0; i < _ratios.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setRatio(i),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: i == _ratioIndex
                                ? AppColors.brandPurple
                                : Colors.white12,
                          ),
                          child: Text(
                            _ratios[i].ratio == null
                                ? tr(_ratios[i].label)
                                : _ratios[i].label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: tr('تدوير'),
                    onPressed:
                        _busy || _imageSize == null ? null : () => _transform('rot'),
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    tooltip: tr('قلب'),
                    onPressed: _busy || _imageSize == null
                        ? null
                        : () => _transform('flip'),
                    icon: const Icon(Icons.flip_rounded,
                        color: Colors.white, size: 28),
                  ),
                  if (_busy) ...[
                    const SizedBox(width: 24),
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// تدوير 90° أو قلب أفقي، ويعيد JPEG (يُثبّت اتجاه EXIF).
Uint8List? _transformJob(List<Object> a) {
  final decoded = img.decodeImage(a[0] as Uint8List);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  im = (a[1] as String) == 'rot'
      ? img.copyRotate(im, angle: 90)
      : img.flipHorizontal(im);
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

/// يقص الجزء المحدد (كنسب من الصورة) ويصغّره إن لزم حتى يدخل في [maxBytes].
Uint8List? _cropJob(List<Object> a) {
  final decoded = img.decodeImage(a[0] as Uint8List);
  if (decoded == null) return null;
  final im = img.bakeOrientation(decoded);
  final fx = a[1] as double, fy = a[2] as double;
  final fw = a[3] as double, fh = a[4] as double;
  final maxBytes = a[5] as int;
  final cw = (fw * im.width).round().clamp(1, im.width);
  final ch = (fh * im.height).round().clamp(1, im.height);
  final cx = (fx * im.width).round().clamp(0, im.width - cw);
  final cy = (fy * im.height).round().clamp(0, im.height - ch);
  var cropped = img.copyCrop(im, x: cx, y: cy, width: cw, height: ch);
  var side = 1920;
  var quality = 85;
  for (var i = 0; i < 6; i++) {
    final longest = math.max(cropped.width, cropped.height);
    final out = longest > side
        ? (cropped.height >= cropped.width
            ? img.copyResize(cropped, height: side)
            : img.copyResize(cropped, width: side))
        : cropped;
    final bytes = Uint8List.fromList(img.encodeJpg(out, quality: quality));
    if (bytes.length <= maxBytes) return bytes;
    side = (side * 0.85).round();
    quality = math.max(50, quality - 7);
  }
  return null;
}

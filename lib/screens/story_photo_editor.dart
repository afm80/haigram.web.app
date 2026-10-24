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

// ---------- مصفوفات الألوان (4×5 كما في ColorFilter.matrix، القيم 0..255) ----------
const List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> _saturation(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return [
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// تباين [c] حول الرمادي المتوسط، وسطوع [b] (-1..1) كإزاحة.
List<double> _brightContrast(double b, double c) {
  final o = 128 * (1 - c) + b * 255;
  return [
    c, 0, 0, 0, o, //
    0, c, 0, 0, o,
    0, 0, c, 0, o,
    0, 0, 0, 1, 0,
  ];
}

/// يطبّق [a] بعد [b] (ناتج الضرب a·b على مصفوفات 5×5 ضمنية).
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + c];
      }
      if (c == 4) v += a[r * 5 + 4];
      out[r * 5 + c] = v;
    }
  }
  return out;
}

class _Filter {
  final String label;
  final List<double> matrix;
  const _Filter(this.label, this.matrix);
}

final List<_Filter> _filters = [
  const _Filter('أصلي', _identity),
  _Filter('زاهٍ', _mul(_brightContrast(0, 1.1), _saturation(1.35))),
  const _Filter('دافئ', [
    1.08, 0, 0, 0, 8, //
    0, 1.0, 0, 0, 2,
    0, 0, 0.9, 0, -6,
    0, 0, 0, 1, 0,
  ]),
  const _Filter('بارد', [
    0.93, 0, 0, 0, -4, //
    0, 1.0, 0, 0, 0,
    0, 0, 1.1, 0, 8,
    0, 0, 0, 1, 0,
  ]),
  _Filter('أبيض وأسود', _saturation(0)),
  const _Filter('بني قديم', [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Filter('باهت', _mul(_brightContrast(0.06, 0.85), _saturation(0.8))),
  _Filter('درامي', _mul(_brightContrast(-0.02, 1.3), _saturation(0.85))),
];

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
  int _tab = 0; // 0 قص، 1 فلاتر، 2 ضبط
  int _filter = 0;
  double _bright = 0; // -0.3..0.3
  double _contrast = 1; // 0.7..1.4
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

  /// المصفوفة النهائية: الفلتر ثم السطوع والتباين.
  List<double> get _matrix => _mul(
      _brightContrast(_bright, _contrast), _filters[_filter].matrix);

  bool get _hasColor => _filter != 0 || _bright != 0 || _contrast != 1;

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
        _hasColor ? _matrix : const <double>[],
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
                              child: ColorFiltered(
                                colorFilter: ColorFilter.matrix(
                                    _hasColor ? _matrix : _identity),
                                child: Image.memory(_bytes,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true),
                              ),
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
            if (_tab == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _ratios.length; i++)
                      Expanded(child: _chip(
                        _ratios[i].ratio == null
                            ? tr(_ratios[i].label)
                            : _ratios[i].label,
                        i == _ratioIndex,
                        () => _setRatio(i),
                      )),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: tr('تدوير'),
                      onPressed: _busy || _imageSize == null
                          ? null
                          : () => _transform('rot'),
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
            if (_tab == 1)
              SizedBox(
                height: 78,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filters.length,
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => setState(() => _filter = i),
                    child: Container(
                      width: 70,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: i == _filter
                            ? AppColors.brandPurple
                            : Colors.white12,
                      ),
                      child: Text(
                        tr(_filters[i].label),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            if (_tab == 2)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _slider(Icons.light_mode_outlined, _bright, -0.3, 0.3,
                        (v) => setState(() => _bright = v)),
                    _slider(Icons.contrast_rounded, _contrast, 0.7, 1.4,
                        (v) => setState(() => _contrast = v)),
                    TextButton(
                      onPressed: () => setState(() {
                        _bright = 0;
                        _contrast = 1;
                      }),
                      child: Text(tr('إعادة الضبط'),
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  _tabButton(0, Icons.crop_rotate_rounded, tr('قص')),
                  _tabButton(1, Icons.filter_vintage_outlined, tr('فلاتر')),
                  _tabButton(2, Icons.tune_rounded, tr('ضبط')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected ? AppColors.brandPurple : Colors.white12,
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _slider(IconData icon, double v, double min, double max,
          ValueChanged<double> onChanged) =>
      Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              activeColor: AppColors.brandPurple,
              onChanged: onChanged,
            ),
          ),
        ],
      );

  Widget _tabButton(int i, IconData icon, String label) => Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Icon(icon,
                    color: _tab == i ? AppColors.brandPurple : Colors.white70),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            _tab == i ? AppColors.brandPurple : Colors.white70,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
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

/// يقص الجزء المحدد (كنسب من الصورة)، يطبّق الفلتر إن وُجد، ويصغّر حتى يدخل في [maxBytes].
Uint8List? _cropJob(List<Object> a) {
  final decoded = img.decodeImage(a[0] as Uint8List);
  if (decoded == null) return null;
  final im = img.bakeOrientation(decoded);
  final fx = a[1] as double, fy = a[2] as double;
  final fw = a[3] as double, fh = a[4] as double;
  final maxBytes = a[5] as int;
  final m = a[6] as List<double>;
  final cw = (fw * im.width).round().clamp(1, im.width);
  final ch = (fh * im.height).round().clamp(1, im.height);
  final cx = (fx * im.width).round().clamp(0, im.width - cw);
  final cy = (fy * im.height).round().clamp(0, im.height - ch);
  var cropped = img.copyCrop(im, x: cx, y: cy, width: cw, height: ch);
  // نصغّر أولاً (حتى 1920) ليكون تطبيق الفلتر على بكسلات أقل.
  var side = 1920;
  img.Image fit(img.Image src, int side) {
    final longest = math.max(src.width, src.height);
    if (longest <= side) return src;
    return src.height >= src.width
        ? img.copyResize(src, height: side)
        : img.copyResize(src, width: side);
  }

  cropped = fit(cropped, side);
  if (m.length == 20) {
    num clamp255(double v) => v < 0 ? 0 : (v > 255 ? 255 : v);
    for (final p in cropped) {
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      p.r = clamp255(m[0] * r + m[1] * g + m[2] * b + m[4]);
      p.g = clamp255(m[5] * r + m[6] * g + m[7] * b + m[9]);
      p.b = clamp255(m[10] * r + m[11] * g + m[12] * b + m[14]);
    }
  }
  var quality = 85;
  for (var i = 0; i < 6; i++) {
    final out = fit(cropped, side);
    final bytes = Uint8List.fromList(img.encodeJpg(out, quality: quality));
    if (bytes.length <= maxBytes) return bytes;
    side = (side * 0.85).round();
    quality = math.max(50, quality - 7);
  }
  return null;
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../services/user_service.dart';
import '../theme.dart';

import '../l10n.dart';
import '../net_error.dart';
/// يفتح شاشة تعديل وتحجيم الصورة الشخصية (تحريك + تكبير بإصبعين/عجلة الفأرة + تدوير)
/// ويعيد صورة JPEG مربّعة مصغّرة جاهزة للحفظ، أو null عند الإلغاء.
Future<Uint8List?> cropProfilePhoto(BuildContext context, Uint8List bytes) =>
    Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CropScreen(bytes: bytes),
      ),
    );

/// يعرض الصورة الشخصية بالحجم الكامل (عند الضغط المطوّل على الصورة).
void showProfilePhoto(BuildContext context, AppUser user) {
  final image = user.avatarImage;
  if (image == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('لا توجد صورة شخصية لهذا الحساب'))),
    );
    return;
  }
  Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _PhotoViewer(user: user, image: image),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _PhotoViewer extends StatelessWidget {
  final AppUser user;
  final ImageProvider image;

  const _PhotoViewer({required this.user, required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipOval(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Image(image: image, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 28),
                    ),
                    Text(
                      '@${user.username}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropScreen extends StatefulWidget {
  final Uint8List bytes;

  const _CropScreen({required this.bytes});

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  double _cropBoxSize = 300;
  static const _outputSize = 360;
  static const _maxBytes = 140 * 1024;

  late Uint8List _bytes = widget.bytes;
  final _controller = TransformationController();
  final _boundary = GlobalKey();
  Size? _imageSize;
  bool _needsCentering = true;
  bool _busy = false;
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

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final decoded = img.decodeImage(_bytes);
      if (decoded == null) throw StateError(tr('صيغة غير مدعومة'));
      final rotated = img.copyRotate(decoded, angle: 90);
      _bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
      _imageSize = null;
      _controller.value = Matrix4.identity();
      await _decodeSize();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, fallback: tr('تعذر تدوير الصورة')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(double box) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // القص يتم حسابياً من موضع الصورة وتكبيرها، دون التقاط الشاشة،
      // لأن التقاط الشاشة (toImage) لا يعمل في متصفح الجوال/الآيباد.
      final size = _imageSize;
      if (size == null) throw StateError(tr('الصورة لم تُحمّل بعد'));
      final decoded = img.decodeImage(_bytes);
      if (decoded == null) throw StateError(tr('صيغة غير مدعومة'));
      final baked = img.bakeOrientation(decoded);
      final scale0 =
          box / (size.width < size.height ? size.width : size.height);
      final childW = size.width * scale0;
      final childH = size.height * scale0;
      final m = _controller.value;
      final s = m.getMaxScaleOnAxis();
      final tx = m.storage[12];
      final ty = m.storage[13];
      final fx = (-tx / s) / childW;
      final fy = (-ty / s) / childH;
      final fw = (box / s) / childW;
      final fh = (box / s) / childH;
      var cw = (fw * baked.width).round().clamp(1, baked.width);
      var ch = (fh * baked.height).round().clamp(1, baked.height);
      final side = cw < ch ? cw : ch;
      cw = side;
      ch = side;
      final cx = (fx * baked.width).round().clamp(0, baked.width - cw);
      final cy = (fy * baked.height).round().clamp(0, baked.height - ch);
      final cropped =
          img.copyCrop(baked, x: cx, y: cy, width: cw, height: ch);
      final rgba = img.copyResize(cropped,
          width: _outputSize,
          height: _outputSize,
          interpolation: img.Interpolation.average);
      var quality = 88;
      late Uint8List out;
      do {
        out = Uint8List.fromList(img.encodeJpg(rgba, quality: quality));
        quality -= 10;
      } while (out.length > _maxBytes && quality >= 30);
      if (out.length > _maxBytes) throw StateError(tr('الصورة كبيرة جداً'));
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
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: _busy || _imageSize == null
                  ? null
                  : () => _done(_cropBoxSize),
              child: Text(tr('تم'),
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = (constraints.maxWidth < constraints.maxHeight - 240
                    ? constraints.maxWidth
                    : constraints.maxHeight - 240)
                .clamp(160.0, 600.0);
            _cropBoxSize = box;
            final size = _imageSize;
            Widget cropArea;
            if (size == null) {
              cropArea = SizedBox(
                width: box,
                height: box,
                child: Center(
                  child: _error != null
                      ? Text(_error!,
                          style: const TextStyle(color: Colors.white))
                      : const CircularProgressIndicator(),
                ),
              );
            } else {
              final scale = box / (size.width < size.height ? size.width : size.height);
              final w = size.width * scale;
              final h = size.height * scale;
              if (_needsCentering) {
                _needsCentering = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _controller.value = Matrix4.translationValues(
                      -(w - box) / 2, -(h - box) / 2, 0);
                });
              }
              cropArea = SizedBox(
                width: box,
                height: box,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      key: _boundary,
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: _controller,
                          constrained: false,
                          minScale: 1,
                          maxScale: 6,
                          boundaryMargin: EdgeInsets.zero,
                          child: SizedBox(
                            width: w,
                            height: h,
                            child: Image.memory(
                              _bytes,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // دليل القص الدائري (لا يدخل في الصورة الناتجة).
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(box, box),
                        painter: _CircleGuidePainter(),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                Expanded(child: Center(child: cropArea)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Text(
                    tr('حرّك الصورة بإصبعك، وكبّرها بإصبعين أو بعجلة الفأرة'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                if (_error != null && size != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.accent2)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: tr('تدوير'),
                        onPressed: _busy || size == null ? null : _rotate,
                        icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _busy ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: Text(tr('إلغاء')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              _busy || size == null ? null : () => _done(box),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(tr('تم')),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect.deflate(2));
    final mask = Path.combine(
        PathOperation.difference, Path()..addRect(rect), circle);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

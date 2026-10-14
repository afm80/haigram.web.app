import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../services/user_service.dart';
import '../theme.dart';

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
      const SnackBar(content: Text('لا توجد صورة شخصية لهذا الحساب')),
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
      if (mounted) setState(() => _error = 'تعذر قراءة الصورة');
    }
  }

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final decoded = img.decodeImage(_bytes);
      if (decoded == null) throw StateError('صيغة غير مدعومة');
      final rotated = img.copyRotate(decoded, angle: 90);
      _bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
      _imageSize = null;
      _controller.value = Matrix4.identity();
      await _decodeSize();
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تدوير الصورة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(double box) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final captured = await boundary.toImage(pixelRatio: _outputSize / box);
      final data =
          await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('تعذر معالجة الصورة');
      final rgba = img.Image.fromBytes(
        width: captured.width,
        height: captured.height,
        bytes: data.buffer,
        numChannels: 4,
      );
      var quality = 88;
      late Uint8List out;
      do {
        out = Uint8List.fromList(img.encodeJpg(rgba, quality: quality));
        quality -= 10;
      } while (out.length > _maxBytes && quality >= 30);
      if (out.length > _maxBytes) throw StateError('الصورة كبيرة جداً');
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر قص الصورة: $e';
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
        title: const Text('تعديل الصورة'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = (constraints.maxWidth < constraints.maxHeight - 170
                    ? constraints.maxWidth
                    : constraints.maxHeight - 170)
                .clamp(200.0, 600.0);
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Text(
                    'حرّك الصورة بإصبعك، وكبّرها بإصبعين أو بعجلة الفأرة',
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'تدوير',
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
                          child: const Text('إلغاء'),
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
                              : const Text('تم'),
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

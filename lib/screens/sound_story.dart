import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';
import '../theme.dart';

/// معاينة الفيديو صاحب الصوت قبل نشره كقصة: تحريك وتكبير داخل إطار 9:16
/// (تعديل غير مدمّر يُحفظ مع القصة)، مع نص اختياري.
class SoundStoryEditor extends StatefulWidget {
  final Post sound;

  const SoundStoryEditor({super.key, required this.sound});

  @override
  State<SoundStoryEditor> createState() => _SoundStoryEditorState();
}

class _SoundStoryEditorState extends State<SoundStoryEditor> {
  final _controller = TransformationController();
  final _caption = TextEditingController();
  VideoPlayerController? _vc;
  bool _needsCentering = true;
  bool _busy = false;
  bool _failed = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final url = await PostService.videoUrl(widget.sound);
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      await vc.setLooping(true);
      if (!mounted) {
        await vc.dispose();
        return;
      }
      await vc.play();
      setState(() => _vc = vc);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _caption.dispose();
    _vc?.dispose();
    super.dispose();
  }

  Future<void> _publish(double frameW, double frameH) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final matrix = _controller.value;
      final t = matrix.getTranslation();
      final bytes = await PostService.videoBytes(widget.sound);
      final mime = widget.sound.mime;
      await PostService.publishMedia(
        PostType.story,
        bytes,
        mime: mime,
        ext: mime.split('/').last.split(';').first,
        caption: _caption.text.trim(),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        extra: {
          'cropScale': matrix.getMaxScaleOnAxis(),
          'cropDx': t.x / frameW,
          'cropDy': t.y / frameH,
          'soundUsername': widget.sound.username,
        },
      );
      navigator.popUntil((route) => route.isFirst);
      messenger
          .showSnackBar(const SnackBar(content: Text('تمت إضافة القصة')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر نشر القصة: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('قصة بالصوت الأصلي'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // إطار 9:16 يتّسع للمساحة المتاحة فوق أدوات النشر.
            final maxH = constraints.maxHeight - 130;
            var fw = constraints.maxWidth;
            var fh = fw * 16 / 9;
            if (fh > maxH) {
              fh = maxH;
              fw = fh * 9 / 16;
            }
            final vc = _vc;
            Widget frame;
            if (_failed) {
              frame = const Center(
                  child: Text('تعذر تشغيل الفيديو',
                      style: TextStyle(color: Colors.white)));
            } else if (vc == null) {
              frame = const Center(child: CircularProgressIndicator());
            } else {
              final a = vc.value.aspectRatio;
              final double w;
              final double h;
              if (a > fw / fh) {
                h = fh;
                w = fh * a;
              } else {
                w = fw;
                h = fw / a;
              }
              if (_needsCentering) {
                _needsCentering = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _controller.value = Matrix4.translationValues(
                      -(w - fw) / 2, -(h - fh) / 2, 0);
                });
              }
              frame = ClipRect(
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: 1,
                  maxScale: 4,
                  boundaryMargin: EdgeInsets.zero,
                  child: SizedBox(width: w, height: h, child: VideoPlayer(vc)),
                ),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: fw,
                        height: fh,
                        child: ColoredBox(color: Colors.black, child: frame),
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.accent2)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          enabled: !_busy,
                          maxLength: 120,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'أضف نصاً للقصة (اختياري)',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed:
                            _busy || vc == null ? null : () => _publish(fw, fh),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(96, 48),
                        ),
                        child: _busy
                            ? Text('${(_progress * 100).round()}%')
                            : const Text('نشر القصة'),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';

/// يسمح بتحميل عدد قليل من المصغّرات في نفس الوقت، حتى لا تُحمَّل عشرات
/// الفيديوهات دفعة واحدة عند فتح شبكة (الملف الشخصي / الاستكشاف) فيتجمّد الجهاز.
class _ThumbnailQueue {
  static const _maxConcurrent = 2;
  static int _running = 0;
  static final _waiting = <Completer<void>>[];

  static Future<void> acquire() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  static void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(); // ينتقل الدور للتالي مباشرة
    } else {
      _running--;
    }
  }
}

class VideoThumbnail extends StatefulWidget {
  final Post post;

  const VideoThumbnail({super.key, required this.post});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // إن وُجدت صورة مصغّرة محفوظة فلا حاجة لتحميل الفيديو إطلاقاً.
    if (widget.post.thumb == null) _load();
  }

  Future<void> _load() async {
    await _ThumbnailQueue.acquire();
    try {
      // إن غادر المستخدم الشبكة أثناء الانتظار لا نحمّل شيئاً.
      if (!mounted) return;
      final url = await PostService.videoUrl(widget.post);
      if (!mounted) return;
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = controller;
      await controller.initialize();
      await controller.pause();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _ThumbnailQueue.release();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.post.thumb;
    if (thumb != null) {
      return Image.memory(thumb,
          fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low);
    }
    final controller = _controller;
    if (_failed) {
      return const ColoredBox(
        color: Color(0xFF431407),
        child: Center(
          child: Icon(Icons.videocam_off_outlined,
              color: Colors.white54, size: 30),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF431407),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
        ),
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

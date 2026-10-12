import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';

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
    _load();
  }

  Future<void> _load() async {
    try {
      final url = await PostService.videoUrl(widget.post);
      if (!mounted) return;
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = controller;
      await controller.initialize();
      await controller.pause();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

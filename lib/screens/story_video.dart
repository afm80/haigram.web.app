// تشغيل فيديو القصص: في العارض (بالصوت، يتحكم به العارض) وفي محرر القصة (معاينة).
import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'story_photo_editor.dart' show storyFilterMatrix;

/// مشغّل لرابط (https) أو ملف محلي (مسار على الأندرويد، رابط blob على الويب).
VideoPlayerController storyVideoController(String src, {bool local = false}) {
  final o = VideoPlayerOptions(mixWithOthers: true);
  if (local && !kIsWeb) {
    return VideoPlayerController.file(File(src), videoPlayerOptions: o);
  }
  return VideoPlayerController.networkUrl(Uri.parse(src), videoPlayerOptions: o);
}

Widget _filtered(int filter, Widget child) => filter == 0
    ? child
    : ColorFiltered(
        colorFilter: ColorFilter.matrix(storyFilterMatrix(filter)), child: child);

/// فيديو القصة داخل العارض. العارض هو الساعة (شريط التقدّم)، وهذا الودجت
/// يشغّل الفيديو ويتبع حالته: نشط، موقوف، صوت، إعادة من البداية.
class StoryVideoView extends StatefulWidget {
  final String url;
  final String? overlayUrl;
  final int filter;
  final bool active; // الصفحة المعروضة الآن
  final bool paused; // العارض موقوف (ضغط مطوّل، كتابة، نافذة...)
  final bool muted;
  final int restartSeq; // تغيّره = إعادة من البداية
  final void Function(Duration) onReady;
  final void Function(bool) onBuffering;
  final VoidCallback onAutoplayBlocked; // المتصفح منع التشغيل بالصوت
  final VoidCallback onFailed;

  const StoryVideoView({
    super.key,
    required this.url,
    required this.overlayUrl,
    required this.filter,
    required this.active,
    required this.paused,
    required this.muted,
    required this.restartSeq,
    required this.onReady,
    required this.onBuffering,
    required this.onAutoplayBlocked,
    required this.onFailed,
  });

  @override
  State<StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends State<StoryVideoView> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _buffering = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _init();
  }

  Future<void> _init() async {
    if (_c != null) return;
    final c = storyVideoController(widget.url);
    _c = c;
    try {
      await c.initialize();
      if (!mounted || _c != c) return;
      await c.setLooping(false);
      await c.setVolume(widget.muted ? 0 : 1);
      c.addListener(_onTick);
      setState(() => _ready = true);
      var d = c.value.duration;
      if (d <= Duration.zero) d = const Duration(seconds: 5);
      widget.onReady(d);
      if (widget.active && !widget.paused) await _play();
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (!mounted || _failed) return;
    _failed = true;
    // لا نترك العارض معلّقاً: نبدأ عدّاد قصير ليتابع إلى القصة التالية.
    widget.onReady(const Duration(seconds: 5));
    widget.onFailed();
  }

  Future<void> _play() async {
    final c = _c;
    if (c == null || !_ready) return;
    try {
      await c.play();
    } catch (_) {
      // المتصفح يمنع التشغيل بالصوت دون تفاعل: نكتم ونعيد المحاولة.
      try {
        await c.setVolume(0);
        widget.onAutoplayBlocked();
        await c.play();
      } catch (_) {}
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    if (c.value.hasError) {
      _fail();
      return;
    }
    final b = c.value.isBuffering;
    if (b != _buffering) {
      _buffering = b;
      widget.onBuffering(b);
    }
  }

  @override
  void didUpdateWidget(covariant StoryVideoView old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (!old.active && widget.active) {
      if (c == null) {
        _init();
      } else {
        c.seekTo(Duration.zero);
        if (_ready) widget.onReady(c.value.duration);
        if (!widget.paused) _play();
      }
    } else if (old.active && !widget.active) {
      c?.pause();
      c?.seekTo(Duration.zero);
    }
    if (c == null || !_ready) return;
    if (old.muted != widget.muted) c.setVolume(widget.muted ? 0 : 1);
    if (widget.active && old.paused != widget.paused) {
      widget.paused ? c.pause() : _play();
    }
    if (old.restartSeq != widget.restartSeq) {
      c.seekTo(Duration.zero);
      if (!widget.paused) _play();
    }
  }

  @override
  void dispose() {
    final c = _c;
    c?.removeListener(_onTick);
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !_ready || _failed) return const SizedBox.shrink();
    final ar = c.value.aspectRatio > 0 ? c.value.aspectRatio : 9 / 16;
    return Center(
      child: AspectRatio(
        aspectRatio: ar,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _filtered(widget.filter, VideoPlayer(c)),
            if (widget.overlayUrl != null)
              IgnorePointer(
                child: CachedNetworkImage(
                    imageUrl: widget.overlayUrl!,
                    fit: BoxFit.fill,
                    fadeInDuration: Duration.zero),
              ),
          ],
        ),
      ),
    );
  }
}

/// معاينة الفيديو في محرر القصة: مكتومة وتتكرر، تحت طبقة الملصقات.
class EditorVideo extends StatefulWidget {
  final String path;
  final int filter;
  const EditorVideo({super.key, required this.path, this.filter = 0});

  @override
  State<EditorVideo> createState() => _EditorVideoState();
}

class _EditorVideoState extends State<EditorVideo> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = storyVideoController(widget.path, local: true);
    _c = c;
    try {
      await c.initialize();
      if (!mounted || _c != c) return;
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !_ready) return const SizedBox.shrink();
    return _filtered(widget.filter, VideoPlayer(c));
  }
}

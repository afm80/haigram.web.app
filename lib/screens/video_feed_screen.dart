import 'dart:async';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'create_flow.dart';
import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'profile_screen.dart';
import 'social_screens.dart' show ChatScreen;

const _shadow = [Shadow(blurRadius: 6, color: Colors.black54)];

/// تبويب الفيديوهات القصيرة: تجربة تيك توك (تبويبات "أتابعهم | لك" + تمرير عمودي لا نهائي).
class VideoFeedScreen extends StatefulWidget {
  final bool active;
  final VoidCallback? onSearch;
  const VideoFeedScreen({super.key, required this.active, this.onSearch});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  bool _following = false;
  late final Stream<List<Post>> _videos = PostService.stream(PostType.video);
  late final Stream<List<String>> _follow = PostService.followingIds();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _body()),
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: _topBar())),
      ],
    );
  }

  Widget _body() {
    return StreamBuilder<List<String>>(
      stream: _follow,
      builder: (context, followSnap) {
        return StreamBuilder<List<Post>>(
          stream: _videos,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: Text('تعذر تحميل الفيديوهات\n${snap.error}',
                      textAlign: TextAlign.center));
            }
            if (!snap.hasData)
              return const AppLoading(message: 'نحضّر لك الفيديوهات...');
            var posts = snap.data!;
            if (_following) {
              final ids = followSnap.data ?? const <String>[];
              posts = posts.where((p) => ids.contains(p.uid)).toList();
            }
            if (posts.isEmpty) {
              return EmptyState(
                icon: Icons.play_arrow_rounded,
                title: _following
                    ? 'لا توجد فيديوهات في المتابعة'
                    : 'ابدأ المشاهدة',
                message: _following
                    ? 'تابع صُنّاع المحتوى لتظهر فيديوهاتهم هنا.'
                    : 'لا توجد فيديوهات بعد. كن أول من يشارك لحظته!',
              );
            }
            return VideoPager(
                key: ValueKey(_following), posts: posts, active: widget.active);
          },
        );
      },
    );
  }

  Widget _topBar() {
    Widget tab(String label, bool selected, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: selected
                ? BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14))
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? Colors.white : Colors.white70,
                      shadows: _shadow),
                ),
                const SizedBox(height: 4),
                Container(
                    width: 20,
                    height: 3,
                    decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(3))),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black.withOpacity(0.55), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tab('أتابعهم', _following,
                    () => setState(() => _following = true)),
                tab('لك', !_following,
                    () => setState(() => _following = false)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12)),
            child: IconButton(
                onPressed: widget.onSearch,
                icon: const Icon(Icons.search_rounded,
                    size: 24, shadows: _shadow)),
          ),
        ],
      ),
    );
  }
}

/// عارض فيديوهات بملء الشاشة يبدأ من فيديو محدد (عند الضغط على فيديو في ملف شخصي).
class VideoViewerScreen extends StatelessWidget {
  final List<Post> posts;
  final int initialIndex;
  const VideoViewerScreen(
      {super.key, required this.posts, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
              child: VideoPager(
                  posts: posts,
                  active: true,
                  initialIndex: initialIndex,
                  bottomBase: 90)),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, shadows: _shadow)),
            ),
          ),
        ],
      ),
    );
  }
}

class SoundScreen extends StatelessWidget {
  final Post sound;

  const SoundScreen({super.key, required this.sound});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('الصوت')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.accent2,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الصوت الأصلي',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '@${sound.username}',
                        style: TextStyle(color: colors.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    startCreate(context, CreateKind.reel, sound: sound),
                icon: const Icon(Icons.video_call_rounded),
                label: const Text('استخدام هذا الصوت'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandRed,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Post>>(
              stream: PostService.videosWithSound(sound),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'تعذر تحميل الفيديوهات\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final videos = snapshot.data!;
                if (videos.isEmpty) {
                  return Center(
                    child: Text(
                      'لا توجد فيديوهات بهذا الصوت بعد.',
                      style: TextStyle(color: colors.textDim),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return Material(
                      color: colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoViewerScreen(
                              posts: videos,
                              initialIndex: index,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: colors.textDim,
                                    size: 44,
                                  ),
                                ),
                              ),
                              Text(
                                video.caption.isEmpty
                                    ? 'فيديو @${video.username}'
                                    : video.caption,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@${video.username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textDim,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoScrubber extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoScrubber({required this.controller});

  @override
  State<_VideoScrubber> createState() => _VideoScrubberState();
}

class _VideoScrubberState extends State<_VideoScrubber> {
  bool _dragging = false;
  double? _scrubProgress;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideoChanged);
  }

  @override
  void didUpdateWidget(covariant _VideoScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideoChanged);
      widget.controller.addListener(_onVideoChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideoChanged);
    super.dispose();
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  double _progress(Duration value, Duration duration) {
    if (duration.inMicroseconds <= 0) return 0;
    return (value.inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _seekTo(double localX, double width, {bool dragging = false}) {
    if (width <= 0) return;
    final duration = widget.controller.value.duration;
    if (duration.inMicroseconds <= 0) return;
    final ratio = (localX / width).clamp(0.0, 1.0);
    if (dragging) {
      setState(() {
        _dragging = true;
        _scrubProgress = ratio;
      });
    }
    unawaited(widget.controller.seekTo(
      Duration(microseconds: (duration.inMicroseconds * ratio).round()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final played = _progress(value.position, value.duration);
    final displayProgress = _scrubProgress ?? played;
    final buffered = value.buffered.fold<double>(
      displayProgress,
      (furthest, range) => _progress(range.end, value.duration) > furthest
          ? _progress(range.end, value.duration)
          : furthest,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _seekTo(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragStart: (details) {
            _seekTo(details.localPosition.dx, constraints.maxWidth,
                dragging: true);
          },
          onHorizontalDragUpdate: (details) => _seekTo(
              details.localPosition.dx, constraints.maxWidth,
              dragging: true),
          onHorizontalDragEnd: (_) => setState(() {
            _dragging = false;
            _scrubProgress = null;
          }),
          onHorizontalDragCancel: () => setState(() {
            _dragging = false;
            _scrubProgress = null;
          }),
          child: SizedBox(
            height: 30,
            child: Center(
              child: SizedBox(
                height: 18,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          height: _dragging ? 5 : 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.38),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: buffered,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.52),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: displayProgress,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: _dragging ? 5 : 3,
                          decoration: BoxDecoration(
                            color: AppColors.brandRed,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment(displayProgress * 2 - 1, 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: _dragging ? 12 : 8,
                        height: _dragging ? 12 : 8,
                        decoration: BoxDecoration(
                          color: AppColors.brandRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// تمرير عمودي لا نهائي مع تشغيل تلقائي.
class VideoPager extends StatefulWidget {
  final List<Post> posts;
  final bool active;
  final int initialIndex;
  final double bottomBase;
  const VideoPager(
      {super.key,
      required this.posts,
      required this.active,
      this.initialIndex = 0,
      this.bottomBase = 78});

  @override
  State<VideoPager> createState() => _VideoPagerState();
}

class _VideoPagerState extends State<VideoPager> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.posts.length;
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      onPageChanged: (i) => setState(() => _page = i),
      // itemCount غير محدد => تمرير لا نهائي يعيد الفيديوهات بالتناوب
      itemBuilder: (context, i) => _VideoPage(
        key: ValueKey('$i-${widget.posts[i % n].id}'),
        post: widget.posts[i % n],
        playing: widget.active && i == _page,
        bottomBase: widget.bottomBase,
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool playing;
  final double bottomBase;
  const _VideoPage(
      {super.key,
      required this.post,
      required this.playing,
      required this.bottomBase});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _vc;
  VideoPlayerController? _soundVc;
  late final AnimationController _disc =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _ready = false;
  bool _failed = false;
  bool _appResumed = true;
  bool _resumeAfterLifecycle = false;
  bool _showLikeFeedback = false;
  bool _likeInProgress = false;
  bool _mainMutedBySound = false;
  double _profileDragDistance = 0;
  String? _soundError;
  Timer? _likeFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _appResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    try {
      final url = await PostService.videoUrl(widget.post);
      if (!mounted) return;
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _vc = vc;
      await vc.setLooping(true);
      await vc.initialize();
      await vc.setVolume(1);
      if (!mounted) return;
      setState(() => _ready = true);
      _sync();
      final soundPostId = widget.post.soundPostId;
      if (soundPostId != null) _openSoundTrack(soundPostId);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _openSoundTrack(String postId) async {
    VideoPlayerController? soundController;
    try {
      final source = await PostService.postById(postId);
      if (source == null || source.type != PostType.video) {
        throw StateError('مصدر الصوت غير متاح');
      }
      final url = await PostService.videoUrl(source);
      soundController = VideoPlayerController.networkUrl(Uri.parse(url));
      await soundController.setLooping(true);
      await soundController.initialize();
      await soundController.setVolume(1);
      if (!mounted) {
        await soundController.dispose();
        return;
      }
      _soundVc = soundController;
      soundController.addListener(_syncMainVideoVolume);
      if (widget.playing && _appResumed) await soundController.play();
      _syncMainVideoVolume();
      setState(() {});
    } catch (error) {
      await soundController?.dispose();
      if (mounted) setState(() => _soundError = '$error');
    }
  }

  void _syncMainVideoVolume() {
    final video = _vc;
    if (video == null) return;
    final muteMain = _soundVc?.value.isPlaying == true;
    if (muteMain == _mainMutedBySound) return;
    _mainMutedBySound = muteMain;
    unawaited(_setMainVideoVolume(video, muteMain ? 0 : 1));
  }

  Future<void> _setMainVideoVolume(
    VideoPlayerController video,
    double volume,
  ) async {
    try {
      await video.setVolume(volume);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر ضبط صوت الفيديو: $error')),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (!_ready) return;
    if (widget.playing && _appResumed) {
      _vc!.play();
      if (_soundVc != null) _soundVc!.play();
      _disc.repeat();
    } else {
      _vc!.pause();
      _soundVc?.pause();
      _disc.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _appResumed = resumed;
    if (!resumed) {
      _resumeAfterLifecycle =
          _vc?.value.isPlaying == true || _soundVc?.value.isPlaying == true;
      _vc?.pause();
      _soundVc?.pause();
      _disc.stop();
    } else {
      if (_resumeAfterLifecycle && widget.playing) _sync();
      _resumeAfterLifecycle = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _soundVc?.removeListener(_syncMainVideoVolume);
    _vc?.dispose();
    _soundVc?.dispose();
    _likeFeedbackTimer?.cancel();
    _disc.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_ready) return;
    final shouldPlay = !_vc!.value.isPlaying;
    setState(() {
      if (shouldPlay) {
        _vc!.play();
        _soundVc?.play();
        _disc.repeat();
      } else {
        _vc!.pause();
        _soundVc?.pause();
        _disc.stop();
      }
    });
  }

  Future<void> _likeOnDoubleTap() async {
    if (!_ready || _likeInProgress) return;
    _likeFeedbackTimer?.cancel();
    setState(() {
      _likeInProgress = true;
      _showLikeFeedback = true;
    });
    _likeFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showLikeFeedback = false);
    });

    try {
      final alreadyLiked = await PostService.isLiked(widget.post.id).first;
      if (!alreadyLiked) {
        await PostService.toggleLike(widget.post.id, false);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تسجيل الإعجاب: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _likeInProgress = false);
    }
  }

  /// يفتح ملف صاحب الفيديو ويوقف التشغيل أثناء غيابه.
  Future<void> _goProfile(String uid) async {
    _vc?.pause();
    _soundVc?.pause();
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)));
    if (mounted && widget.playing) _sync();
  }

  Future<void> _openSound() async {
    final soundId = widget.post.soundPostId;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sound =
          soundId == null ? widget.post : await PostService.postById(soundId);
      if (sound == null || sound.type != PostType.video) {
        throw StateError('الصوت الأصلي غير متاح');
      }
      if (!mounted) return;
      _vc?.pause();
      _soundVc?.pause();
      await navigator.push<void>(
        MaterialPageRoute(builder: (_) => SoundScreen(sound: sound)),
      );
      if (mounted && widget.playing) _sync();
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('تعذر فتح الصوت: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return GestureDetector(
      onTap: _togglePlay,
      onDoubleTap: () => unawaited(_likeOnDoubleTap()),
      onHorizontalDragStart: (_) => _profileDragDistance = 0,
      onHorizontalDragUpdate: (details) =>
          _profileDragDistance += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_profileDragDistance > 80) unawaited(_goProfile(p.uid));
        _profileDragDistance = 0;
      },
      onHorizontalDragCancel: () => _profileDragDistance = 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (_ready)
            LayoutBuilder(
              builder: (context, _) {
                final aspectRatio = _vc!.value.aspectRatio;
                if (!aspectRatio.isFinite || aspectRatio <= 0) {
                  return const SizedBox.shrink();
                }
                return ClipRect(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: VideoPlayer(_vc!),
                    ),
                  ),
                );
              },
            )
          else if (_failed)
            const EmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'تعذر تشغيل الفيديو',
              message: 'قد يكون الملف غير متاح أو بصيغة غير مدعومة.',
            )
          else
            const AppLoading(message: 'جارٍ تحميل الفيديو...'),
          if (_ready && !_vc!.value.isPlaying)
            const Center(
                child: Icon(Icons.play_arrow_rounded,
                    size: 90, color: Colors.white70)),
          IgnorePointer(
            child: Center(
              child: AnimatedScale(
                scale: _showLikeFeedback ? 1 : 0.45,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _showLikeFeedback ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.videoLike,
                    size: 112,
                    shadows: _shadow,
                  ),
                ),
              ),
            ),
          ),
          if (_soundVc != null)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0,
                  child: VideoPlayer(_soundVc!),
                ),
              ),
            ),
          // تدرّج أسفل الشاشة لتحسين قراءة النص
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [const Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          if (_ready)
            Positioned(
              left: 12,
              right: 12,
              bottom: widget.bottomBase - 3,
              child: _VideoScrubber(
                controller: _vc!,
              ),
            ),
          _bottomInfo(p),
          // أعداد الإعجاب والتعليقات تتحدّث مباشرة
          StreamBuilder<Post?>(
            stream: PostService.postStream(p.id),
            initialData: p,
            builder: (context, s) => _sideActions(s.data ?? p),
          ),
        ],
      ),
    );
  }

  Widget _bottomInfo(Post p) {
    const labelColor = Colors.white;
    const labelShadow = Shadow(color: Colors.black87, blurRadius: 4);
    return Positioned(
      right: 14,
      left: 84,
      bottom: widget.bottomBase + 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _goProfile(p.uid),
            child: Text(
              '@${p.username}',
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                shadows: [labelShadow],
              ),
            ),
          ),
          if (p.caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              p.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: labelColor, shadows: [labelShadow]),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openSound,
            child: Row(children: [
              Icon(
                _soundError == null
                    ? Icons.music_note_rounded
                    : Icons.music_off_rounded,
                size: 16,
                color: labelColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _soundError != null
                      ? 'الصوت غير متاح'
                      : p.soundPostId == null
                          ? 'الصوت الأصلي - ${p.username}'
                          : 'الصوت الأصلي - ${p.soundUsername ?? 'مستخدم'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 13,
                    shadows: [labelShadow],
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sideActions(Post p) {
    final actionScale =
        (MediaQuery.sizeOf(context).height / 700).clamp(0.72, 1.0).toDouble();
    return Positioned(
      left: 10,
      bottom: widget.bottomBase * actionScale - 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: actionScale,
            child: _avatarWithPlus(p),
          ),
          SizedBox(height: 18 * actionScale),
          StreamBuilder<bool>(
            stream: PostService.isLiked(p.id),
            builder: (context, s) {
              final liked = s.data ?? false;
              return _action(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                '${p.likes}',
                color: liked ? AppColors.videoLike : Colors.white,
                onTap: () => PostService.toggleLike(p.id, liked),
                scale: actionScale,
              );
            },
          ),
          _action(Icons.chat_bubble_outline_rounded, '${p.comments}',
              onTap: () => showCommentsSheet(context, p), scale: actionScale),
          StreamBuilder<bool>(
            stream: PostService.isSaved(p.id),
            builder: (context, s) {
              final saved = s.data ?? false;
              return _action(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                'حفظ',
                color: saved ? const Color(0xFFFFD54F) : Colors.white,
                onTap: () => PostService.toggleSave(p.id, saved),
                scale: actionScale,
              );
            },
          ),
          _action(
            Icons.reply_rounded,
            'مشاركة',
            flip: true,
            onTap: () => _showShareOptions(p),
            scale: actionScale,
          ),
          _soundDisc(),
          SizedBox(height: 8 * actionScale),
        ],
      ),
    );
  }

  Widget _soundDisc() {
    final actionScale =
        (MediaQuery.sizeOf(context).height / 700).clamp(0.72, 1.0).toDouble();
    return Tooltip(
      message: 'فتح صفحة الصوت',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openSound,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Transform.scale(
              scale: actionScale,
              child: RotationTransition(
                turns: _disc,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(colors: [
                      AppColors.accent,
                      AppColors.accent2,
                      AppColors.accent
                    ]),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.85), width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.music_note_rounded,
                      size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showShareOptions(Post post) {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        void runAction(
          Future<void> Function() action, {
          String successMessage = 'تمت العملية بنجاح',
        }) {
          Navigator.pop(sheetContext);
          unawaited(_runShareAction(action, successMessage));
        }

        return SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.fromSTEB(20, 18, 20, 10),
                child: Text(
                  'مشاركة الفيديو',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('إرسال إلى صديق'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showVideoFriends(post);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_photos_outlined),
                title: const Text('إضافة إلى قصتي'),
                onTap: () => runAction(
                  () => PostService.addVideoToStory(post),
                  successMessage: 'تمت إضافة الفيديو إلى قصتك',
                ),
              ),
              StreamBuilder<bool>(
                stream: PostService.isSaved(post.id),
                builder: (context, snapshot) {
                  final saved = snapshot.data ?? false;
                  return ListTile(
                    leading: Icon(saved
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined),
                    title: Text(saved ? 'إزالة من المحفوظات' : 'حفظ الفيديو'),
                    onTap: () => runAction(
                      () => PostService.toggleSave(post.id, saved),
                      successMessage: saved
                          ? 'تمت إزالة الفيديو من المحفوظات'
                          : 'تم حفظ الفيديو',
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('تنزيل الفيديو'),
                onTap: () => runAction(
                  () async {
                    final bytes = await PostService.videoBytes(post);
                    final extension = _videoExtension(post.mime);
                    await FileSaver.instance.saveFile(
                      name: 'haigram_${post.id}',
                      bytes: bytes,
                      ext: extension,
                      mimeType: post.mime == 'video/mp4'
                          ? MimeType.mp4Video
                          : MimeType.custom,
                      customMimeType:
                          post.mime == 'video/mp4' ? null : post.mime,
                    );
                  },
                  successMessage: 'تم تنزيل الفيديو',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('مشاركة عبر التطبيقات'),
                onTap: () => runAction(() async {
                  await Share.share(
                    '${post.caption.isEmpty ? 'فيديو على Haigram' : post.caption}\n'
                    '${_videoLink(post)}',
                    subject: 'فيديو على Haigram',
                  );
                }, successMessage: 'تم فتح خيارات المشاركة'),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('نسخ الرابط'),
                onTap: () => runAction(
                  () async {
                    await Clipboard.setData(
                      ClipboardData(text: _videoLink(post)),
                    );
                  },
                  successMessage: 'تم نسخ رابط الفيديو',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runShareAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ العملية: $error')),
        );
      }
    }
  }

  void _showVideoFriends(Post post) {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: FutureBuilder<List<AppUser>>(
            future: _loadVideoFriends(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'تعذر تحميل الأصدقاء\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final friends = snapshot.data!;
              if (friends.isEmpty) {
                return const Center(
                  child: Text('لا يوجد أصدقاء متبادلون لمشاركة الفيديو معهم.'),
                );
              }
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'إرسال الفيديو إلى صديق',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return ListTile(
                          leading: UserAvatar(
                            uid: friend.uid,
                            fallbackName: friend.username,
                            radius: 23,
                          ),
                          title: Text(friend.displayName),
                          subtitle: Text('@${friend.username}'),
                          trailing: const Icon(Icons.send_rounded),
                          onTap: () => _sendVideoToFriend(
                            sheetContext,
                            friend,
                            post,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<AppUser>> _loadVideoFriends() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  Future<void> _sendVideoToFriend(
      BuildContext sheetContext, AppUser friend, Post post) async {
    final navigator = Navigator.of(sheetContext);
    navigator.pop();
    try {
      final conversationId = await SocialService.startConversation(friend.uid);
      await SocialService.sendMessage(
        conversationId,
        'شاهد هذا الفيديو من @${post.username}\n${_videoLink(post)}',
      );
      if (!mounted) return;
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUid: friend.uid,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الفيديو: $error')),
        );
      }
    }
  }

  String _videoLink(Post post) =>
      Uri.base.replace(path: '/', queryParameters: {'v': post.id}).toString();

  String _videoExtension(String mime) {
    if (mime == 'video/quicktime') return 'mov';
    final subtype = mime.split('/').last.split(';').first;
    return subtype.startsWith('x-') ? subtype.substring(2) : subtype;
  }

  Widget _avatarWithPlus(Post p) {
    final isMine = p.uid == PostService.uidOrEmpty;
    return StreamBuilder<bool>(
      stream: PostService.isFollowing(p.uid),
      builder: (context, s) {
        final following = s.data ?? false;
        return SizedBox(
          width: 52,
          height: 62,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
                child: UserAvatar(
                    uid: p.uid,
                    fallbackName: p.username,
                    radius: 24,
                    showOnline: true,
                    onTap: () => _goProfile(p.uid)),
              ),
              if (!isMine && !following)
                Positioned(
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => PostService.toggleFollow(p.uid, false),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: AppColors.brandRed),
                      child: const Icon(Icons.add, size: 16),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _action(IconData icon, String label,
      {Color color = Colors.white,
      bool flip = false,
      VoidCallback? onTap,
      double scale = 1}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * scale),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Transform.scale(
                scaleX: flip ? -1 : 1,
                child: Icon(icon,
                    size: 34 * scale, color: color, shadows: _shadow)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    shadows: _shadow)),
          ],
        ),
      ),
    );
  }
}

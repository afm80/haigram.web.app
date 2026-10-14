import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'create_flow.dart';
import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'profile_screen.dart';
import 'share_sheet.dart';
import 'sound_story.dart';
import 'video_thumbnail.dart';
import '../route_state.dart';

const _shadow = [Shadow(blurRadius: 6, color: Colors.black54)];

/// تبويب الفيديوهات القصيرة: تجربة تيك توك (تبويبات "أتابعهم | لك" + تمرير عمودي لا نهائي).
class VideoFeedScreen extends StatefulWidget {
  final bool active;
  final VoidCallback? onSearch;

  /// يُزاد عند النقر على تبويب الرئيسية وأنت فيه: يحدّث الفيديوهات.
  final ValueListenable<int>? refreshRequest;
  const VideoFeedScreen(
      {super.key, required this.active, this.onSearch, this.refreshRequest});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  bool _following = false;
  // نحمّل 10 فيديوهات في كل مرة (كان 40) ونزيد 10 كلما اقترب المستخدم من النهاية.
  static const _pageSize = 10;
  static const _maxLimit = 40;
  int _limit = _pageSize;
  int _loaded = 0; // عدد الفيديوهات التي وصلت آخر مرة
  Stream<List<Post>> _videos =
      PostService.stream(PostType.video, limit: _pageSize);
  late final Stream<List<String>> _follow = PostService.followingIds();
  int _refreshCount = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshRequest?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant VideoFeedScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshRequest != widget.refreshRequest) {
      old.refreshRequest?.removeListener(_refresh);
      widget.refreshRequest?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.refreshRequest?.removeListener(_refresh);
    super.dispose();
  }

  /// تحديث: اشتراك جديد بالفيديوهات وإعادة بناء المشغّل من أول فيديو.
  void _refresh() {
    if (!mounted) return;
    setState(() {
      _limit = _pageSize;
      _loaded = 0;
      _videos = PostService.stream(PostType.video, limit: _pageSize);
      _refreshCount++;
    });
  }

  /// يزيد الدفعة بمقدار 10 إن كانت الدفعة الحالية ممتلئة (يوجد المزيد).
  void _loadMore() {
    if (!mounted || _loaded < _limit || _limit >= _maxLimit) return;
    setState(() {
      _limit += _pageSize;
      _videos = PostService.stream(PostType.video, limit: _limit);
    });
  }

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
            // لا نعرض شاشة التحميل عند طلب دفعة جديدة (تبقى القائمة الحالية).
            if (!snap.hasData) {
              return const AppLoading(message: 'نحضّر لك الفيديوهات...');
            }
            var posts = snap.data!;
            _loaded = posts.length;
            if (_following) {
              final ids = followSnap.data ?? const <String>[];
              posts = posts.where((p) => ids.contains(p.uid)).toList();
              // قليل من فيديوهات المتابَعين بين الأحدث: نحمّل دفعة إضافية.
              if (posts.length < 3 && _loaded >= _limit && _limit < _maxLimit) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _loadMore());
              }
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
                key: ValueKey('$_following-$_refreshCount'),
                posts: posts,
                active: widget.active,
                onNearEnd: _loadMore);
          },
        );
      },
    );
  }

  /// زر البث المباشر (واجهة مبدئية): يظهر أعلى اليمين كما في تيك توك،
  /// وعند الضغط يعرض رسالة "قريباً" فقط حتى تتوفر خدمة البث.
  Widget _liveButton() {
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text('البث المباشر قريباً',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ctx.appColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        alignment: Alignment.center,
        child: const Icon(Icons.live_tv_rounded,
            size: 26, color: Colors.white, shadows: _shadow),
      ),
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
          _liveButton(),
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

/// صفحة الصوت (بأسلوب تيك توك): صاحب الصوت + عدد الاستخدامات + حفظ،
/// شبكة الفيديوهات، وبالأسفل «نشر إلى قصة» و«استخدام الصوت».
class SoundScreen extends StatelessWidget {
  final Post sound;

  const SoundScreen({super.key, required this.sound});

  /// نشر إلى قصة: معاينة فيديو الصوت الأصلي مع إمكانية التحريك والتكبير.
  void _shareToStory(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SoundStoryEditor(sound: sound),
        ),
      );

  /// استخدام الصوت: اختيار فيديو (ريلز) أو صورة (قصة بالصوت) ثم التعديل.
  void _useSound(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('إضافة فيديو'),
              subtitle: const Text('ريلز جديد بهذا الصوت (مع القص والتعديل)'),
              onTap: () {
                Navigator.pop(sheetContext);
                startCreate(context, CreateKind.reel, sound: sound);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('إضافة صورة'),
              subtitle: const Text('تُنشر كقصة يُشغَّل خلفها هذا الصوت'),
              onTap: () {
                Navigator.pop(sheetContext);
                startCreate(context, CreateKind.story, sound: sound);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSaved(BuildContext context, bool saved) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.setSoundSaved(sound, !saved);
      messenger.showSnackBar(SnackBar(
          content: Text(saved ? 'تمت إزالة الصوت من المحفوظات' : 'تم حفظ الصوت')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر حفظ الصوت: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        title: const Text('الصوت'),
      ),
      body: StreamBuilder<List<Post>>(
        stream: PostService.videosWithSound(sound),
        builder: (context, snapshot) {
          final videos = snapshot.data ?? const <Post>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // صورة صاحب الصوت
                    UserAvatar(
                      uid: sound.uid,
                      fallbackName: sound.username,
                      radius: 46,
                      onTap: () => openProfile(context, sound.uid),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الصوت الأصلي',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          GestureDetector(
                            onTap: () => openProfile(context, sound.uid),
                            child: Text(
                              '@${sound.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: colors.textDim, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            snapshot.hasData
                                ? '${videos.length} منشور'
                                : '... منشور',
                            style:
                                TextStyle(color: colors.textDim, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<bool>(
                            stream: PostService.isSoundSaved(sound.id),
                            builder: (context, savedSnap) {
                              final saved = savedSnap.data ?? false;
                              return OutlinedButton.icon(
                                onPressed: savedSnap.hasData
                                    ? () => _toggleSaved(context, saved)
                                    : null,
                                icon: Icon(
                                  saved
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 18,
                                ),
                                label: Text(saved ? 'تم الحفظ' : 'حفظ'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.text,
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(
                                      color: colors.text.withOpacity(0.25)),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(builder: (context) {
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
                  if (videos.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد فيديوهات بهذا الصوت بعد.',
                        style: TextStyle(color: colors.textDim),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: videos.length,
                    itemBuilder: (context, index) {
                      final video = videos[index];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          appRoute(
                            'video',
                            {'id': video.id},
                            (_) => VideoViewerScreen(
                              posts: videos,
                              initialIndex: index,
                            ),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: colors.surfaceHigh,
                              child: VideoThumbnail(post: video),
                            ),
                            Positioned(
                              left: 6,
                              bottom: 5,
                              child: Row(
                                children: [
                                  const Icon(Icons.play_arrow_outlined,
                                      size: 16, color: Colors.white),
                                  Text(
                                    '${video.views}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 4,
                                            color: Colors.black54),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          );
        },
      ),
      // زرّان بالأسفل كما في تيك توك.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _shareToStory(context),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('نشر إلى قصة'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.surfaceHigh,
                    foregroundColor: colors.text,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _useSound(context),
                  icon: const Icon(Icons.videocam_rounded),
                  label: const Text('استخدام الصوت'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
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

  /// تُستدعى حين يقترب المستخدم من آخر الفيديوهات المحمّلة (لتحميل دفعة أخرى).
  final VoidCallback? onNearEnd;
  const VideoPager(
      {super.key,
      required this.posts,
      required this.active,
      this.initialIndex = 0,
      this.bottomBase = 78,
      this.onNearEnd});

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
      // يبني الصفحة المجاورة مسبقاً لنحمّل الفيديو التالي قبل الوصول إليه.
      allowImplicitScrolling: true,
      onPageChanged: (i) {
        setState(() => _page = i);
        if (i >= n - 3) widget.onNearEnd?.call();
      },
      // itemCount غير محدد => تمرير لا نهائي يعيد الفيديوهات بالتناوب
      itemBuilder: (context, i) => _VideoPage(
        key: ValueKey('$i-${widget.posts[i % n].id}'),
        post: widget.posts[i % n],
        playing: widget.active && i == _page,
        // نحمّل الفيديو الحالي والتالي فقط (وليس السابق) لتوفير الذاكرة.
        load: i == _page || (n > 1 && i == _page + 1),
        bottomBase: widget.bottomBase,
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool playing;
  final bool load;
  final double bottomBase;
  const _VideoPage(
      {super.key,
      required this.post,
      required this.playing,
      this.load = true,
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
  bool _opening = false;
  bool _soundStarted = false;
  bool _appResumed = true;
  bool _resumeAfterLifecycle = false;
  bool _userPaused = false; // أوقفه المستخدم يدوياً بالنقر
  bool _viewCounted = false;
  Timer? _viewTimer;
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
    if (widget.load) _open();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
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
      _ensureSoundTrack();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// مسار الصوت المنفصل يُحمَّل فقط عندما يصبح الفيديو هو المعروض (لا مسبقاً).
  void _ensureSoundTrack() {
    final soundPostId = widget.post.soundPostId;
    if (soundPostId == null || _soundStarted || !_ready || !widget.playing) {
      return;
    }
    _soundStarted = true;
    _openSoundTrack(soundPostId);
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
    if (old.playing != widget.playing) _userPaused = false;
    if (widget.load && _vc == null && !_opening && !_failed) _open();
    _sync();
    _ensureSoundTrack();
  }

  /// تُحسب مشاهدة بعد ثانيتين من التشغيل الفعلي (مرة واحدة لكل مستخدم).
  void _scheduleView(bool playingNow) {
    if (_viewCounted) return;
    _viewTimer?.cancel();
    if (!playingNow) return;
    _viewTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _viewCounted) return;
      _viewCounted = true;
      unawaited(PostService.registerView(widget.post));
    });
  }

  void _sync() {
    if (!_ready) return;
    _scheduleView(widget.playing && _appResumed && !_userPaused);
    if (widget.playing && _appResumed && !_userPaused) {
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
    _viewTimer?.cancel();
    _disc.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_ready) return;
    final shouldPlay = !_vc!.value.isPlaying;
    _scheduleView(shouldPlay);
    setState(() {
      _userPaused = !shouldPlay;
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
    await Navigator.of(context).push(appRoute(
        'user', {'uid': uid}, (_) => UserProfileScreen(uid: uid)));
    if (mounted && widget.playing) _sync();
  }

  Future<void> _openSound() async {
    final soundId = widget.post.soundPostId;
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
      // فوق الشريط السفلي (Navigator الجذر) كما في تيك توك.
      await Navigator.of(context, rootNavigator: true).push<void>(
        appRoute<void>(
            'sound', {'id': sound.id}, (_) => SoundScreen(sound: sound)),
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
      behavior: HitTestBehavior.opaque,
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
              builder: (context, constraints) {
                final aspectRatio = _vc!.value.aspectRatio;
                if (!aspectRatio.isFinite || aspectRatio <= 0) {
                  return const SizedBox.shrink();
                }
                // على غرار تيك توك: الفيديو الطولي يملأ الشاشة عمودياً (قص بسيط
                // من الجوانب)، أما الأفقي أو المربّع أو إن كان القص سيكون كبيراً
                // (مثل شاشات الحاسوب) فيُعرض كاملاً بدون قص.
                final boxW = constraints.maxWidth;
                final boxH = constraints.maxHeight;
                var fit = BoxFit.contain;
                if (boxW.isFinite &&
                    boxH.isFinite &&
                    boxW > 0 &&
                    boxH > 0 &&
                    aspectRatio < 1 &&
                    boxH > boxW) {
                  final screenAspect = boxW / boxH;
                  final ratio = screenAspect < aspectRatio
                      ? screenAspect / aspectRatio
                      : aspectRatio / screenAspect;
                  if (ratio >= 0.7) fit = BoxFit.cover;
                }
                return ClipRect(
                  child: SizedBox.expand(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: FittedBox(
                        fit: fit,
                        child: SizedBox(
                          width: 1000 * aspectRatio,
                          height: 1000,
                          child: IgnorePointer(child: VideoPlayer(_vc!)),
                        ),
                      ),
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
            const IgnorePointer(
              child: Center(
                  child: Icon(Icons.play_arrow_rounded,
                      size: 90, color: Colors.white70)),
            ),
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
      // فوق مسار تقدم الفيديو حتى لا يغطيه قرص الصوت.
      bottom: widget.bottomBase * actionScale + 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: actionScale,
            child: _avatarWithPlus(p),
          ),
          SizedBox(height: 18 * actionScale),
          LikeBuilder(
            post: p,
            builder: (context, liked, count, toggle) => _action(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              '$count',
              color: liked ? AppColors.videoLike : Colors.white,
              onTap: toggle,
              scale: actionScale,
            ),
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
            onTap: () => showPostShareSheet(context, p),
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

  Widget _avatarWithPlus(Post p) {
    final isMine = p.uid == PostService.uidOrEmpty;
    return StreamBuilder<FollowState>(
      stream: PostService.followState(p.uid),
      builder: (context, s) {
        // يُخفى زر + إذا كنت أتابعه أو أرسلت له طلباً معلّقاً.
        final following = (s.data ?? FollowState.none) != FollowState.none;
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
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final r = await PostService.follow(p.uid);
                        if (r == FollowState.requested) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text(
                                  'تم إرسال طلب المتابعة، بانتظار الموافقة')));
                        }
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text('تعذر المتابعة: $e')));
                      }
                    },
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

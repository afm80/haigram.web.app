import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'profile_screen.dart';

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
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: _topBar())),
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
              return Center(child: Text('تعذر تحميل الفيديوهات\n${snap.error}', textAlign: TextAlign.center));
            }
            if (!snap.hasData) return const AppLoading(message: 'نحضّر لك الفيديوهات...');
            var posts = snap.data!;
            if (_following) {
              final ids = followSnap.data ?? const <String>[];
              posts = posts.where((p) => ids.contains(p.uid)).toList();
            }
            if (posts.isEmpty) {
              return EmptyState(
                icon: Icons.play_arrow_rounded,
                title: _following ? 'لا توجد فيديوهات في المتابعة' : 'ابدأ المشاهدة',
                message: _following ? 'تابع صُنّاع المحتوى لتظهر فيديوهاتهم هنا.' : 'لا توجد فيديوهات بعد. كن أول من يشارك لحظته!',
              );
            }
            return VideoPager(key: ValueKey(_following), posts: posts, active: widget.active);
          },
        );
      },
    );
  }

  Widget _topBar() {
    Widget tab(String label, bool selected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: selected ? BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(14)) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : Colors.white70, shadows: _shadow),
                ),
                const SizedBox(height: 4),
                Container(width: 20, height: 3, decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(3))),
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
                tab('أتابعهم', _following, () => setState(() => _following = true)),
                tab('لك', !_following, () => setState(() => _following = false)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: IconButton(onPressed: widget.onSearch, icon: const Icon(Icons.search_rounded, size: 24, shadows: _shadow)),
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
  const VideoViewerScreen({super.key, required this.posts, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: VideoPager(posts: posts, active: true, initialIndex: initialIndex, bottomBase: 28)),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded, shadows: _shadow)),
            ),
          ),
        ],
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
  const VideoPager({super.key, required this.posts, required this.active, this.initialIndex = 0, this.bottomBase = 78});

  @override
  State<VideoPager> createState() => _VideoPagerState();
}

class _VideoPagerState extends State<VideoPager> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
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
  const _VideoPage({super.key, required this.post, required this.playing, required this.bottomBase});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> with SingleTickerProviderStateMixin {
  VideoPlayerController? _vc;
  late final AnimationController _disc = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
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
      if (!mounted) return;
      setState(() => _ready = true);
      _sync();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (!_ready) return;
    if (widget.playing) {
      _vc!.play();
      _disc.repeat();
    } else {
      _vc!.pause();
      _disc.stop();
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    _disc.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_ready) return;
    setState(() => _vc!.value.isPlaying ? _vc!.pause() : _vc!.play());
  }

  /// يفتح ملف صاحب الفيديو ويوقف التشغيل أثناء غيابه.
  Future<void> _goProfile(String uid) async {
    _vc?.pause();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)));
    if (mounted && widget.playing) _vc?.play();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _vc!.value.size.width,
                height: _vc!.value.size.height,
                child: VideoPlayer(_vc!),
              ),
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
            const Center(child: Icon(Icons.play_arrow_rounded, size: 90, color: Colors.white70)),
          // تدرّج أسفل الشاشة لتحسين قراءة النص
          const Positioned(
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
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
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
    return Positioned(
      right: 14,
      left: 84,
      bottom: widget.bottomBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _goProfile(p.uid),
            child: Text('@${p.username}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, shadows: _shadow)),
          ),
          if (p.caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.caption, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(shadows: _shadow)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.music_note_rounded, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text('الصوت الأصلي - ${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, shadows: _shadow))),
          ]),
        ],
      ),
    );
  }

  Widget _sideActions(Post p) {
    return Positioned(
      left: 10,
      bottom: widget.bottomBase - 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatarWithPlus(p),
          const SizedBox(height: 18),
          StreamBuilder<bool>(
            stream: PostService.isLiked(p.id),
            builder: (context, s) {
              final liked = s.data ?? false;
              return _action(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                '${p.likes}',
                color: liked ? AppColors.videoLike : Colors.white,
                onTap: () => PostService.toggleLike(p.id, liked),
              );
            },
          ),
          _action(Icons.chat_bubble_outline_rounded, '${p.comments}', onTap: () => showCommentsSheet(context, p)),
          StreamBuilder<bool>(
            stream: PostService.isSaved(p.id),
            builder: (context, s) {
              final saved = s.data ?? false;
              return _action(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                'حفظ',
                color: saved ? AppColors.accent : Colors.white,
                onTap: () => PostService.toggleSave(p.id, saved),
              );
            },
          ),
          _action(Icons.reply_rounded, 'مشاركة', flip: true, onTap: () async {
            await Clipboard.setData(ClipboardData(text: UserService.linkFor(p.username)));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ رابط حساب @${p.username}')));
          }),
          const SizedBox(height: 8),
          RotationTransition(
            turns: _disc,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [AppColors.accent, AppColors.accent2, AppColors.accent]),
              ),
              child: const Icon(Icons.music_note_rounded, size: 22),
            ),
          ),
        ],
      ),
    );
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
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                child: UserAvatar(uid: p.uid, fallbackName: p.username, radius: 24, onTap: () => _goProfile(p.uid)),
              ),
              if (!isMine && !following)
                Positioned(
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => PostService.toggleFollow(p.uid, false),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent2),
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

  Widget _action(IconData icon, String label, {Color color = Colors.white, bool flip = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Transform.scale(scaleX: flip ? -1 : 1, child: Icon(icon, size: 34, color: color, shadows: _shadow)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, shadows: _shadow)),
          ],
        ),
      ),
    );
  }
}

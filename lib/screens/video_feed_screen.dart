import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';
import '../theme.dart';

/// شاشة الفيديوهات العمودية: تمرير لا نهائي لأعلى/أسفل مع تشغيل تلقائي.
class VideoFeedScreen extends StatelessWidget {
  final bool active;
  const VideoFeedScreen({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.video),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('تعذر تحميل الفيديوهات\n${snap.error}', textAlign: TextAlign.center));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final posts = snap.data!;
        if (posts.isEmpty) {
          return const Center(
            child: Text('لا توجد فيديوهات بعد.\nاضغط + وكن أول من ينشر!', textAlign: TextAlign.center),
          );
        }
        return _FeedPager(posts: posts, active: active);
      },
    );
  }
}

class _FeedPager extends StatefulWidget {
  final List<Post> posts;
  final bool active;
  const _FeedPager({required this.posts, required this.active});

  @override
  State<_FeedPager> createState() => _FeedPagerState();
}

class _FeedPagerState extends State<_FeedPager> {
  final _controller = PageController();
  int _page = 0;

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
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool playing;
  const _VideoPage({super.key, required this.post, required this.playing});

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
            const Center(child: Text('تعذر تشغيل الفيديو'))
          else
            const Center(child: CircularProgressIndicator()),
          if (_ready && !_vc!.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow_rounded, size: 90, color: Colors.white70)),
          // تدرّج أسفل الشاشة لتحسين قراءة النص
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
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
          _bottomInfo(p),
          _sideActions(p),
        ],
      ),
    );
  }

  Widget _bottomInfo(Post p) {
    return Positioned(
      right: 14,
      left: 84,
      bottom: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('@${p.username}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text(p.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.music_note_rounded, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text('الصوت الأصلي - ${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ]),
        ],
      ),
    );
  }

  Widget _sideActions(Post p) {
    final me = PostService.username;
    return Positioned(
      left: 10,
      bottom: 70,
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
                color: liked ? AppColors.accent2 : Colors.white,
                onTap: () => PostService.toggleLike(p.id, liked),
              );
            },
          ),
          _action(Icons.chat_bubble_outline_rounded, 'تعليق', onTap: () => _comingSoon('التعليقات')),
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
          _action(Icons.reply_rounded, 'مشاركة', flip: true, onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ رابط فيديو $me')));
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

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what: قريباً')));
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
                  color: AppColors.surfaceHigh,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(child: Text(p.username.isNotEmpty ? p.username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
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
            Transform.scale(scaleX: flip ? -1 : 1, child: Icon(icon, size: 34, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

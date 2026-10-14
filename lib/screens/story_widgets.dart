import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'create_flow.dart';
import 'post_widgets.dart';
import 'profile_screen.dart';
import '../route_state.dart';

/// يتذكر القصص التي شوهدت خلال الجلسة (لتحويل الحلقة إلى رمادية).
class StoryViewed {
  static final Set<String> _seen = {};
  static void mark(String id) => _seen.add(id);
  static bool isSeen(String id) => _seen.contains(id);
  static bool allSeen(StoryGroup g) =>
      g.stories.every((s) => _seen.contains(s.id));
}

/// شريط القصص أعلى صفحة المنشورات (مثل إنستغرام).
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key});

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  Future<void> _open(List<StoryGroup> ordered, int index) async {
    await rootNavigatorOf(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) =>
            StoryViewer(groups: ordered, initial: index),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final me = PostService.uidOrEmpty;
    return SizedBox(
      height: 106,
      child: StreamBuilder<List<StoryGroup>>(
        stream: PostService.storyGroups(),
        builder: (context, snap) {
          final groups = snap.data ?? const <StoryGroup>[];
          return StreamBuilder<List<String>>(
            stream: PostService.followingIds(),
            builder: (context, fs) {
              final following = fs.data ?? const <String>[];
              final mine = groups.where((g) => g.uid == me).toList();
              final rest = groups.where((g) => g.uid != me).toList()
                ..sort((a, b) {
                  final fa = following.contains(a.uid) ? 0 : 1;
                  final fb = following.contains(b.uid) ? 0 : 1;
                  return fa.compareTo(fb);
                });
              final ordered = [...mine, ...rest];
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  _myItem(mine.isEmpty ? null : mine.first,
                      () => _open(ordered, 0)),
                  for (var i = 0; i < rest.length; i++)
                    _item(
                      uid: rest[i].uid,
                      label: rest[i].username,
                      seen: StoryViewed.allSeen(rest[i]),
                      onTap: () => _open(ordered, mine.length + i),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _myItem(StoryGroup? mine, VoidCallback open) {
    final me = PostService.uidOrEmpty;
    return _cell(
      label: 'قصتك',
      child: GestureDetector(
        onTap:
            mine == null ? () => startCreate(context, CreateKind.story) : open,
        child: SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            children: [
              Center(
                  child: _ring(me, PostService.username,
                      seen: mine != null && StoryViewed.allSeen(mine),
                      active: mine != null)),
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () => startCreate(context, CreateKind.story),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandPurple,
                        border:
                            Border.all(color: context.appColors.bg, width: 2)),
                    child: const Icon(Icons.add, size: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
      {required String uid,
      required String label,
      required bool seen,
      required VoidCallback onTap}) {
    return _cell(
      label: label,
      child: GestureDetector(
          onTap: onTap, child: _ring(uid, label, seen: seen, active: true)),
    );
  }

  Widget _cell({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            child,
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _ring(String uid, String name,
      {required bool seen, required bool active}) {
    return Container(
      width: 66,
      height: 66,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active && !seen
            ? const LinearGradient(
                colors: [
                  Color(0xFFE9D5FF),
                  Color(0xFFC084FC),
                  Color(0xFFA855F7),
                  Color(0xFF7C3AED),
                  Color(0xFF5B21B6),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              )
            : null,
        color: active && !seen
            ? null
            : (active ? const Color(0x55FFFFFF) : Colors.transparent),
      ),
      child: Container(
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: context.appColors.bg),
        padding: const EdgeInsets.all(2),
        child: UserAvatar(
            uid: uid, fallbackName: name, radius: 28, showOnline: true),
      ),
    );
  }
}

/// عارض القصص بملء الشاشة: أشرطة تقدّم، نقر للتنقل، ضغط مطوّل للإيقاف، سحب للأسفل للإغلاق.
class StoryViewer extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initial;
  const StoryViewer({super.key, required this.groups, required this.initial});

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  late int _g = widget.initial;
  late int _s;
  bool _paused = false;
  bool _ready = false;
  late final AnimationController _t;

  @override
  void initState() {
    super.initState();
    _s = _firstUnseen(widget.groups[_g]);
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _next();
      });
    StoryViewed.mark(_story.id);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  int _firstUnseen(StoryGroup g) {
    final i = g.stories.indexWhere((s) => !StoryViewed.isSeen(s.id));
    return i < 0 ? 0 : i;
  }

  StoryGroup get _group => widget.groups[_g];
  Post get _story => _group.stories[_s];

  void _go(int g, int s) {
    _t.stop();
    _t.value = 0;
    _ready = false;
    setState(() {
      _g = g;
      _s = s;
    });
    StoryViewed.mark(_story.id);
  }

  void _next() {
    if (!mounted) return;
    if (_s < _group.stories.length - 1) {
      _go(_g, _s + 1);
    } else if (_g < widget.groups.length - 1) {
      _go(_g + 1, 0);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_s > 0) {
      _go(_g, _s - 1);
    } else if (_g > 0) {
      _go(_g - 1, 0);
    } else {
      _t.forward(from: 0);
    }
  }

  void _onReady(Duration d) {
    if (!mounted) return;
    _ready = true;
    _t.duration = d;
    if (_paused) {
      _t.value = 0;
    } else {
      _t.forward(from: 0);
    }
  }

  void _pause() {
    _t.stop();
    setState(() => _paused = true);
  }

  void _resume() {
    setState(() => _paused = false);
    if (_ready) _t.forward();
  }

  Future<void> _openAuthor() async {
    _pause();
    await Navigator.of(context).push(appRoute('user', {'uid': _group.uid},
        (_) => UserProfileScreen(uid: _group.uid)));
    if (mounted) _resume();
  }

  Future<void> _delete() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القصة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await PostService.deletePost(_story);
      if (mounted) Navigator.of(context).pop();
    } else if (mounted) {
      _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final mine = _group.uid == PostService.uidOrEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final left = d.localPosition.dx < w / 2;
          (rtl ? left : !left) ? _next() : _prev();
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StoryMedia(
                key: ValueKey(story.id),
                story: story,
                paused: _paused,
                onReady: _onReady),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
              child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x99000000), Colors.transparent]))),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: AnimatedBuilder(
                      animation: _t,
                      builder: (_, __) => Row(
                        children: [
                          for (var i = 0; i < _group.stories.length; i++)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value:
                                        i < _s ? 1 : (i == _s ? _t.value : 0),
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white30,
                                    valueColor: const AlwaysStoppedAnimation(
                                        Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openAuthor,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              UserAvatar(
                                  uid: _group.uid,
                                  fallbackName: _group.username,
                                  radius: 17),
                              const SizedBox(width: 10),
                              Text(_group.username,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text(timeAgo(story.createdAt),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (mine)
                          IconButton(
                              onPressed: _delete,
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.white)),
                        IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (story.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: const Color(0x99000000),
                            borderRadius: BorderRadius.circular(14)),
                        child: Text(story.caption,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.4)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryMedia extends StatefulWidget {
  final Post story;
  final bool paused;
  final void Function(Duration) onReady;
  const _StoryMedia(
      {super.key,
      required this.story,
      required this.paused,
      required this.onReady});

  @override
  State<_StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends State<_StoryMedia> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onReady(const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: PostImage(post: widget.story, fit: BoxFit.contain)),
    );
  }
}

// صفحة الفيديو العمودي المرفوع بتصميم تيك توك (للأندرويد/آيفون):
// فيديو بملء الإطار، عمود أزرار جانبي (صورة صاحب الفيديو مع زر المتابعة،
// إعجاب، تعليقات، حفظ، مشاركة، قرص الصوت) على اليسار، والوصف أسفل اليمين.
// نقرة = إيقاف/تشغيل، سحب عمودي = التنقل بين المقاطع (يتولاه العارض).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import '../theme.dart';
import '../video_source.dart';
import 'common_widgets.dart';
import 'sound_screen.dart';
import 'video_cover.dart';
import 'video_embed_stub.dart' if (dart.library.html) 'video_embed_web.dart';

const _shadow = [Shadow(blurRadius: 8, color: Colors.black87)];

/// عدد مختصر مثل تيك توك: 950 ، 1.2K ، 15K ، 2.4M
String _fmt(int n) {
  String t(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceFirst(
        RegExp(r'\.0$'),
        '',
      );
  if (n < 1000) return '$n';
  if (n < 1000000) return '${t(n / 1000)}K';
  return '${t(n / 1000000)}M';
}

class _Burst {
  final int id;
  final Offset at;
  const _Burst(this.id, this.at);
}

class TikTokShortPage extends StatefulWidget {
  final Post post;

  /// الصفحة الظاهرة الآن (فقط لها مشغّل حيّ؛ غيرها يعرض الغلاف).
  final bool active;
  final VoidCallback onComments;
  final VoidCallback onShare;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const TikTokShortPage({
    super.key,
    required this.post,
    required this.active,
    required this.onComments,
    required this.onShare,
    required this.onNext,
    required this.onPrev,
  });

  @override
  State<TikTokShortPage> createState() => _TikTokShortPageState();
}

class _TikTokShortPageState extends State<TikTokShortPage>
    with SingleTickerProviderStateMixin {
  final _handle = VideoHandle();
  bool _paused = false;
  bool _followBusy = false;
  double _dy = 0;

  // الإعجاب بالنقر المزدوج: يُعيَّن من زر القلب (يعرف حالة الإعجاب الحالية).
  VoidCallback? _likeIfNeeded;
  Offset _tapAt = Offset.zero;
  final _bursts = <_Burst>[];
  int _burstSeq = 0;

  // قرص الصوت يدور أثناء التشغيل ويتوقف عند الإيقاف.
  late final AnimationController _disc =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  late final Stream<Post?> _live = PostService.postStream(widget.post.id);
  late final Stream<FollowState> _follow =
      PostService.followState(widget.post.uid);
  late final Stream<bool> _saved = PostService.isSaved(widget.post.id);

  @override
  void initState() {
    super.initState();
    if (widget.active) _disc.repeat();
  }

  @override
  void didUpdateWidget(covariant TikTokShortPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        // يعود المشغّل من جديد (تشغيل تلقائي).
        _paused = false;
        _disc.repeat();
      } else {
        _disc.stop();
      }
    }
  }

  @override
  void dispose() {
    _disc.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.active) return;
    _handle.send('toggle');
    setState(() => _paused = !_paused);
    if (_paused) {
      _disc.stop();
    } else {
      _disc.repeat();
    }
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -150 || _dy < -40) {
      widget.onNext();
    } else if (v > 150 || _dy > 40) {
      widget.onPrev();
    }
    _dy = 0;
  }

  /// نقرتان: إعجاب (لا يُلغى بالنقر المزدوج مثل تيك توك) مع قلب يتطاير.
  void _doubleTapLike() {
    if (!widget.active) return;
    _likeIfNeeded?.call();
    final b = _Burst(++_burstSeq, _tapAt);
    setState(() => _bursts.add(b));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _bursts.remove(b));
    });
  }

  /// لمس قادم من مشغّل الويب (iframe يلتقط اللمس بنفسه ويرسله لنا).
  void _onGesture(String g) {
    if (!widget.active || !mounted) return;
    if (g == 'next') {
      widget.onNext();
    } else if (g == 'prev') {
      widget.onPrev();
    } else if (g == 'paused' || g == 'playing') {
      setState(() => _paused = g == 'paused');
      if (_paused) {
        _disc.stop();
      } else {
        _disc.repeat();
      }
    } else if (g.startsWith('dbl:')) {
      final xy = g.substring(4).split(',');
      if (xy.length == 2) {
        _tapAt = Offset(double.tryParse(xy[0]) ?? 0, double.tryParse(xy[1]) ?? 0);
      }
      _doubleTapLike();
    }
  }

  Future<void> _doFollow() async {
    if (_followBusy || needsLogin(context)) return;
    _followBusy = true;
    try {
      await PostService.follow(widget.post.uid);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(friendlyError(error, fallback: tr('تعذرت المتابعة')))));
      }
    } finally {
      _followBusy = false;
    }
  }

  // ───────────────────────── العناصر ─────────────────────────

  Widget _action(Widget icon, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: _shadow)),
          ],
        ),
      ),
    );
  }

  Icon _icon(IconData i, {Color color = Colors.white}) =>
      Icon(i, size: 35, color: color, shadows: _shadow);

  /// صورة صاحب الفيديو مع شارة + للمتابعة (تختفي بعد المتابعة).
  Widget _avatar(bool mine) {
    final p = widget.post;
    return SizedBox(
      width: 56,
      height: 68,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => openProfile(context, p.uid),
            child: Container(
              padding: const EdgeInsets.all(1.8),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white),
              child: UserAvatar(uid: p.uid, fallbackName: p.name, radius: 24),
            ),
          ),
          if (!mine)
            Positioned(
              bottom: 0,
              child: StreamBuilder<FollowState>(
                stream: _follow,
                builder: (context, s) {
                  final st = s.data ?? FollowState.none;
                  if (st == FollowState.following) {
                    return const SizedBox.shrink();
                  }
                  final canFollow = st == FollowState.none;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canFollow ? _doFollow : null,
                    child: Container(
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canFollow
                            ? AppColors.likeRed
                            : const Color(0xFF8E929C),
                      ),
                      child: Icon(
                          canFollow
                              ? Icons.add_rounded
                              : Icons.schedule_rounded,
                          size: 16,
                          color: Colors.white),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _heart() {
    return LikeBuilder(
      post: widget.post,
      builder: (context, liked, count, toggle) {
        _likeIfNeeded = () {
          if (!liked) toggle();
        };
        return _action(
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1).animate(
                  CurvedAnimation(parent: anim, curve: Curves.elasticOut)),
              child: child),
          child: Icon(
            Icons.favorite_rounded,
            key: ValueKey(liked),
            size: 38,
            color: liked ? AppColors.likeRed : Colors.white,
            shadows: _shadow,
          ),
        ),
        _fmt(count),
        toggle,
      );
      },
    );
  }

  Widget _comments() {
    final p = widget.post;
    return StreamBuilder<Post?>(
      stream: _live,
      initialData: p,
      builder: (context, s) {
        final n = s.data?.comments ?? p.comments;
        return _action(_icon(Icons.mode_comment_rounded), _fmt(n),
            widget.onComments);
      },
    );
  }

  Widget _save() {
    final p = widget.post;
    return StreamBuilder<bool>(
      stream: _saved,
      builder: (context, s) {
        final saved = s.data ?? false;
        return _action(
          _icon(Icons.bookmark_rounded,
              color: saved ? const Color(0xFFFFC83D) : Colors.white),
          saved ? tr('محفوظ') : tr('حفظ'),
          () {
            if (needsLogin(context)) return;
            PostService.toggleSave(p.id, saved);
          },
        );
      },
    );
  }

  /// قرص الصوت الدوّار (صورة صاحب الفيديو داخل قرص أسطواني).
  Widget _discWidget() {
    final p = widget.post;
    return RotationTransition(
      turns: _disc,
      child: Container(
        width: 46,
        height: 46,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
              colors: [Color(0xFF3A3A3A), Color(0xFF0B0B0B)]),
          border: Border.all(color: Colors.white24, width: 1.2),
        ),
        child: ClipOval(
          child: UserAvatar(uid: p.uid, fallbackName: p.name, radius: 13),
        ),
      ),
    );
  }

  /// سطر اسم الصوت تحت اسم الحساب: يفتح صفحة الصوت.
  Widget _soundLine(PostSound s) {
    return PointerInterceptor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openSound(context, s, root: true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note_rounded,
                size: 15, color: Colors.white, shadows: _shadow),
            const SizedBox(width: 4),
            Flexible(
              child: Text('${soundTitle(s)} · @${s.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: _shadow)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption() {
    final p = widget.post;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PointerInterceptor(
          child: GestureDetector(
            onTap: () => openProfile(context, p.uid),
            child: Text('@${p.username}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: _shadow)),
          ),
        ),
        if (p.soundRef != null) ...[
          const SizedBox(height: 6),
          _soundLine(p.soundRef!),
        ],
        if (p.caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          IgnorePointer(
            child: Text(p.caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                    shadows: _shadow)),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mine = p.uid == PostService.uidOrEmpty;
    final source = p.video!;
    final isFile = source.provider == VideoProvider.file;
    // ملف مرفوع: على الأندرويد/آيفون تلتقط طبقة فلتر اللمس، وعلى الويب يلتقطه
    // مشغّل الصفحة نفسه (iframe). يوتيوب وغيره: مشغّل المنصة يلتقط اللمس.
    final flutterTouch = isFile && !kIsWeb;
    final pad = MediaQuery.of(context).padding;
    return LayoutBuilder(builder: (context, c) {
      // الفيديو يملأ الشاشة كاملة؛ على الشاشات العريضة فقط يبقى بنسبة 9:16 في الوسط.
      final maxW = c.maxHeight * 9 / 16;
      final w = c.maxWidth < maxW ? c.maxWidth : maxW;
      return Center(
        child: SizedBox(
          width: w,
          height: c.maxHeight,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // الفيديو بملء الشاشة
                widget.active
                    ? buildVideoEmbed(source,
                        key: ValueKey('short-${p.id}'),
                        handle: _handle,
                        onGesture: _onGesture,
                        aspect: 9 / 16,
                        tiktok: isFile)
                    : VideoCover(source: source),
                // تدرّجات لقراءة النص والأيقونات
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 110,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 260,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xB3000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                if (flutterTouch)
                  // طبقة اللمس: نقرة للإيقاف/التشغيل، نقرتان إعجاب، سحب عمودي للتنقل
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      onDoubleTapDown: (d) => _tapAt = d.localPosition,
                      onDoubleTap: _doubleTapLike,
                      onVerticalDragStart: (_) => _dy = 0,
                      onVerticalDragUpdate: (d) => _dy += d.delta.dy,
                      onVerticalDragEnd: _dragEnd,
                    ),
                  )
                else if (!isFile)
                  // مشغّل المنصة يلتقط اللمس: شريط سحب جانبي (جهة اليمين لأن الأزرار يسار)
                  Positioned(
                    right: 0,
                    top: c.maxHeight * 0.4,
                    bottom: 0,
                    width: (w * 0.2).clamp(36.0, 120.0).toDouble(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _dy = 0,
                      onVerticalDragUpdate: (d) => _dy += d.delta.dy,
                      onVerticalDragEnd: _dragEnd,
                    ),
                  ),
                // قلوب النقر المزدوج
                for (final b in _bursts)
                  Positioned(
                    key: ValueKey('burst-${b.id}'),
                    left: b.at.dx - 55,
                    top: b.at.dy - 55,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 750),
                        builder: (context, t, _) => Opacity(
                          opacity: (1 - t * t).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, -60 * t),
                            child: Transform.scale(
                              scale: 0.5 + 0.9 * Curves.easeOutBack.transform(
                                  t < 0.4 ? t / 0.4 : 1),
                              child: const Icon(Icons.favorite_rounded,
                                  size: 110,
                                  color: AppColors.likeRed,
                                  shadows: _shadow),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // أيقونة الإيقاف في الوسط
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _paused ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(Icons.play_arrow_rounded,
                            size: 88, color: Colors.white70, shadows: _shadow),
                      ),
                    ),
                  ),
                ),
                // الوصف أسفل اليمين (يترك مكان عمود الأزرار على اليسار)
                Positioned(
                  left: 76,
                  right: 12,
                  bottom: 16 + pad.bottom,
                  child: _caption(),
                ),
                // عمود الأزرار على اليسار
                Positioned(
                  left: 6,
                  bottom: 12 + pad.bottom,
                  // PointerInterceptor: على الويب يلتقط الـ iframe النقرات فوقه،
                  // فهذا يجعل الأزرار تصل لفلتر بدل المشغّل.
                  child: PointerInterceptor(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(mine),
                      const SizedBox(height: 6),
                      _heart(),
                      _comments(),
                      _save(),
                      _action(
                          // أيقونة المشاركة مثل تيك توك: سهم منحنٍ نحو اليمين.
                          Transform.flip(
                            flipX: true,
                            child: _icon(Icons.reply_rounded),
                          ),
                          p.shares > 0 ? _fmt(p.shares) : tr('مشاركة'),
                          widget.onShare),
                      const SizedBox(height: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final s = p.soundRef;
                          if (s != null) openSound(context, s, root: true);
                        },
                        child: _discWidget(),
                      ),
                    ],
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

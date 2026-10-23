import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../auth_gate.dart';
import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'create_flow.dart';
import 'post_widgets.dart';
import 'profile_screen.dart';
import 'story_backgrounds.dart';
import 'story_poll.dart';
import '../route_state.dart';

import '../l10n.dart';
import 'install_stub.dart' if (dart.library.html) 'install_web.dart';
/// يتذكر القصص التي شوهدت خلال الجلسة (لتحويل الحلقة إلى رمادية).
class StoryViewed {
  static final Set<String> _seen = {};
  static String? _loadedFor;
  static const _maxStored = 400;

  static String get _key => 'seen_stories_${PostService.uidOrEmpty}';

  /// يحمّل القصص المشاهَدة المحفوظة على الجهاز (تبقى رمادية بعد إعادة فتح التطبيق).
  static Future<void> load() async {
    final uid = PostService.uidOrEmpty;
    if (_loadedFor == uid) return;
    _loadedFor = uid;
    _seen.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen.addAll(prefs.getStringList(_key) ?? const <String>[]);
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = _seen.toList();
      // القصص تنتهي بعد 24 ساعة: نحتفظ بأحدث العناصر فقط.
      if (list.length > _maxStored) {
        list = list.sublist(list.length - _maxStored);
        _seen
          ..clear()
          ..addAll(list);
      }
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static void mark(String id) {
    if (_seen.add(id)) _persist();
  }

  /// يعلّم القصة كمشاهدة ويسجّل المشاهدة في الخادم (مرة واحدة فقط).
  static void markAndRecord(Post story) {
    if (_seen.add(story.id)) {
      _persist();
      _record(story);
    } else if (_failed.contains(story.id)) {
      // فشل تسجيل المشاهدة سابقاً (انقطاع مثلاً): نعيد المحاولة عند فتحها ثانية.
      _record(story);
    }
  }

  /// قصص فشل إرسال مشاهدتها للخادم (في الذاكرة فقط).
  static final Set<String> _failed = {};

  static void _record(Post story) {
    PostService.recordStoryView(story).then((_) {
      _failed.remove(story.id);
    }).catchError((_) {
      _failed.add(story.id);
    });
  }

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
  @override
  void initState() {
    super.initState();
    StoryViewed.load().then((_) {
      if (mounted) setState(() {});
    });
  }

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
                  // الزائر لا قصة له: بدل خلية «قصتك» نعرض «تثبيت التطبيق».
                  if (isLoggedIn)
                    _myItem(mine.isEmpty ? null : mine.first,
                        () => _open(ordered, 0))
                  else
                    _installItem(),
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

  /// خلية «تثبيت التطبيق» للزوار فقط (تظهر حيث تظهر «قصتك» للمسجَّلين).
  /// تختفي إذا كان التطبيق مثبَّتاً أو المتصفح لا يدعم التثبيت.
  Widget _installItem() {
    return ValueListenableBuilder<String>(
      valueListenable: installState,
      builder: (context, state, _) {
        if (state != 'prompt' && state != 'ios') return const SizedBox.shrink();
        // زر أفقي متناسق: الشعار + أيقونة التثبيت + نص «تثبيت التطبيق» بجانبها.
        final colors = context.appColors;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              // يتمركز رأسياً مع حلقات القصص (ارتفاعها 66).
              padding: const EdgeInsets.only(top: 9),
              child: GestureDetector(
                onTap: () => _installTapped(state),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: AppColors.storyGradient,
                  ),
                  child: Container(
                    padding: const EdgeInsetsDirectional.only(
                        start: 10, end: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: colors.bg,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HaigramLogo(size: 28),
                        const SizedBox(width: 8),
                        Text(
                          tr('تثبيت التطبيق'),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brandPurple),
                          child: const Icon(Icons.download_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _installTapped(String state) async {
    if (state == 'prompt') {
      await promptInstall();
      return;
    }
    // آيفون/سفاري: لا يوجد حدث تثبيت، نعرض الخطوات.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('تثبيت التطبيق')),
        content: Text(tr(
            'اضغط زر المشاركة في سفاري ثم اختر «إضافة إلى الشاشة الرئيسية».')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('حسناً'))),
        ],
      ),
    );
  }

  Widget _myItem(StoryGroup? mine, VoidCallback open) {
    final me = PostService.uidOrEmpty;
    return _cell(
      label: tr('قصتك'),
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
            ? AppColors.storyGradient
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

/// عارض القصص بملء الشاشة على طريقة إنستغرام:
/// - أشرطة تقدّم، نقر على الثلث الأول للرجوع وعلى الباقي للتالي.
/// - ضغط مطوّل للإيقاف مع إخفاء الواجهة، سحب للأسفل للإغلاق.
/// - سحب أفقي للانتقال بين أصحاب القصص بتأثير مكعّب ثلاثي الأبعاد.
/// - شريط سفلي: ردّ على القصة (رسالة خاصة) + قلب إعجاب.
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
  bool _ready = false;
  bool _hideUi = false; // أثناء الضغط المطوّل
  double _dragDy = 0; // سحب للأسفل للإغلاق
  final Set<String> _pauseReasons = {};
  late final AnimationController _t;
  late final PageController _pc = PageController(initialPage: widget.initial);
  final TextEditingController _reply = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _s = _firstUnseen(widget.groups[_g]);
    StoryViewed.load();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _next();
      });
    _replyFocus.addListener(() => _setPause('typing', _replyFocus.hasFocus));
    StoryViewed.markAndRecord(_story);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheNext());
  }

  @override
  void dispose() {
    _t.dispose();
    _pc.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  int _firstUnseen(StoryGroup g) {
    final i = g.stories.indexWhere((s) => !StoryViewed.isSeen(s.id));
    return i < 0 ? 0 : i;
  }

  StoryGroup get _group => widget.groups[_g];
  Post get _story => _group.stories[_s];
  bool get _paused => _pauseReasons.isNotEmpty;

  // ---- الإيقاف المؤقت بأسباب متعددة (ضغط مطوّل، كتابة، سحب، نافذة...) ----
  void _setPause(String reason, bool on) {
    if (!mounted) return;
    final before = _paused;
    on ? _pauseReasons.add(reason) : _pauseReasons.remove(reason);
    if (before == _paused) return;
    if (_paused) {
      _t.stop();
    } else if (_ready) {
      _t.forward();
    }
    setState(() {});
  }

  void _precacheNext() {
    if (!mounted) return;
    Post? next;
    if (_s < _group.stories.length - 1) {
      next = _group.stories[_s + 1];
    } else if (_g < widget.groups.length - 1) {
      final ng = widget.groups[_g + 1];
      next = ng.stories[_firstUnseen(ng)];
    }
    final url = next?.mediaUrl;
    if (url == null) return;
    precacheImage(
            CachedNetworkImageProvider(PostService.optimizedImageUrl(url, 1080)),
            context)
        .catchError((_) {});
  }

  void _go(int g, int s) {
    _t.stop();
    _t.value = 0;
    _ready = false;
    setState(() {
      _g = g;
      _s = s;
    });
    StoryViewed.markAndRecord(_story);
    _precacheNext();
  }

  void _next() {
    if (!mounted) return;
    if (_s < _group.stories.length - 1) {
      _go(_g, _s + 1);
    } else if (_g < widget.groups.length - 1) {
      _pc.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_s > 0) {
      _go(_g, _s - 1);
    } else if (_g > 0) {
      _pc.previousPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      _t.forward(from: 0);
    }
  }

  void _onPageChanged(int i) {
    if (i == _g) return;
    _go(i, _firstUnseen(widget.groups[i]));
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

  Future<void> _openAuthor() async {
    _setPause('nav', true);
    await Navigator.of(context).push(appRoute('user', {'uid': _group.uid},
        (_) => UserProfileScreen(uid: _group.uid)));
    _setPause('nav', false);
  }

  Future<void> _delete() async {
    _setPause('dialog', true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف القصة؟')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف'))),
        ],
      ),
    );
    if (ok == true) {
      final st = _story;
      await PostService.deletePost(st);
      if (!mounted) return;
      final list = _group.stories;
      if (list.length > 1) {
        // نبقى في العارض وننتقل لقصة صاحبها التالية بدل إغلاقه كله.
        list.remove(st);
        _go(_g, _s.clamp(0, list.length - 1).toInt());
        _setPause('dialog', false);
      } else {
        Navigator.of(context).pop();
      }
    } else {
      _setPause('dialog', false);
    }
  }

  Future<void> _showViewers(Post story) async {
    _setPause('viewers', true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: EdgeInsets.all(14),
              child: Text(tr('المشاهدون'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Expanded(
              child: StreamBuilder<List<StoryViewEntry>>(
                stream: PostService.storyViewers(story.id),
                builder: (_, snap) {
                  final list = snap.data ?? const <StoryViewEntry>[];
                  if (list.isEmpty) {
                    return Center(
                        child: Text(
                            snap.connectionState == ConnectionState.waiting
                                ? ''
                                : tr('لا توجد مشاهدات بعد'),
                            style:
                                TextStyle(color: context.appColors.textDim)));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ViewerTile(entry: list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    _setPause('viewers', false);
  }

  Future<void> _sendReply() async {
    if (needsLogin(context)) return;
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _reply.clear();
    _replyFocus.unfocus();
    try {
      final id = await SocialService.startConversation(_group.uid);
      await SocialService.sendMessage(id, trf('ردّ على القصة: {0}', [text]));
      messenger.showSnackBar(SnackBar(
          content: Text(tr('تم إرسال ردّك')), duration: Duration(seconds: 2)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('تعذّر إرسال الردّ')), duration: Duration(seconds: 2)));
    }
  }

  /// تفاعل سريع بإيموجي (كإنستغرام): يُرسل كرسالة لصاحب القصة.
  static const _quickReactions = ['😂', '😮', '😍', '😢', '👏', '🔥'];

  Future<void> _sendReaction(String emoji) async {
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await SocialService.startConversation(_group.uid);
      await SocialService.sendMessage(
          id, trf('تفاعل على القصة: {0}', [emoji]));
      messenger.showSnackBar(SnackBar(
          content: Text(emoji, style: const TextStyle(fontSize: 22)),
          duration: const Duration(seconds: 1)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('تعذّر إرسال الردّ')),
          duration: const Duration(seconds: 2)));
    }
  }

  Widget _reactionsRow() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final e in _quickReactions)
              GestureDetector(
                onTap: () => _sendReaction(e),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
              ),
          ],
        ),
      );

  // ---- تأثير المكعّب بين الصفحات ----
  Widget _cube(int i, Widget child) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _pc,
      child: child,
      builder: (ctx, c) {
        var page = _g.toDouble();
        if (_pc.hasClients && _pc.position.haveDimensions) {
          page = _pc.page ?? page;
        }
        final d = (i - page).clamp(-1.0, 1.0).toDouble();
        final angle = (rtl ? -1 : 1) * d * 1.5707963;
        final fwdIsLeftPivot = (d > 0) == !rtl;
        return Transform(
          alignment:
              fwdIsLeftPivot ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: c,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = (1 - (_dragDy / 1200)).clamp(0.85, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_replyFocus.hasFocus) {
            _replyFocus.unfocus();
            return;
          }
          final w = MediaQuery.of(context).size.width;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final inPrevZone =
              rtl ? d.localPosition.dx > w * 2 / 3 : d.localPosition.dx < w / 3;
          inPrevZone ? _prev() : _next();
        },
        onLongPressStart: (_) {
          _hideUi = true;
          _setPause('hold', true);
        },
        onLongPressEnd: (_) {
          _hideUi = false;
          _setPause('hold', false);
        },
        onVerticalDragStart: (_) => _setPause('drag', true),
        onVerticalDragUpdate: (d) {
          setState(() =>
              _dragDy = (_dragDy + d.delta.dy).clamp(0.0, 600.0).toDouble());
        },
        onVerticalDragEnd: (d) {
          if (_dragDy > 120 || (d.primaryVelocity ?? 0) > 700) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragDy = 0);
            _setPause('drag', false);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: Transform.scale(
            scale: scale,
            child: PageView.builder(
              controller: _pc,
              itemCount: widget.groups.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) => _cube(i, _page(i)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(int gi) {
    final group = widget.groups[gi];
    final active = gi == _g;
    final si = active ? _s : _firstUnseen(group);
    final story = group.stories[si];
    final mine = group.uid == PostService.uidOrEmpty;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _StoryMedia(
                          key: ValueKey(story.id),
                          story: story,
                          active: active,
                          onReady: _onReady),
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: const [
                                Color(0x99000000),
                                Colors.transparent,
                                Colors.transparent,
                                Color(0x88000000),
                              ],
                              stops: const [0, 0.22, 0.75, 1],
                            ),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: (_hideUi && active) ? 0 : 1,
                        child: Column(
                          children: [
                            _progress(group, si, active),
                            _header(group, story, mine),
                            const Spacer(),
                            if (story.poll != null)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                child: StoryPollCard(
                                    key: ValueKey('poll-${story.id}'),
                                    story: story,
                                    poll: story.poll!,
                                    mine: mine),
                              ),
                            if (story.sharedFromUsername != null)
                              _sharedFrom(story),
                            if (story.caption.isNotEmpty && story.bg == null)
                              _caption(story),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: (_hideUi && active) ? 0 : 1,
              child: _bottomBar(story, mine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress(StoryGroup group, int si, bool active) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, __) => Row(
          children: [
            for (var i = 0; i < group.stories.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: i < si ? 1 : (i == si && active ? _t.value : 0),
                      minHeight: 2.5,
                      backgroundColor: Colors.white30,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(StoryGroup group, Post story, bool mine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openAuthor,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                UserAvatar(
                    uid: group.uid, fallbackName: group.username, radius: 17),
                const SizedBox(width: 10),
                Text(group.username,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(timeAgo(story.createdAt),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Spacer(),
          if (mine)
            IconButton(
                onPressed: () => _showStoryMenu(story),
                icon: const Icon(Icons.more_horiz, color: Colors.white)),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ],
      ),
    );
  }

  void _showStoryMenu(Post story) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.white),
              title: Text(tr('حذف القصة'),
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _delete();
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined, color: Colors.white),
              title: Text(tr('المشاهدون'),
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _showViewers(story);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white),
              title: Text(tr('إلغاء'),
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// «من @صاحب الصورة» للقصة المشاركة من منشور.
  Widget _sharedFrom(Post story) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(16)),
        child: Text(trf('من @{0}', [story.sharedFromUsername]),
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }

  Widget _caption(Post story) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(14)),
        child: Text(story.caption,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white, fontSize: 17, height: 1.4)),
      ),
    );
  }

  /// الشريط السفلي: لصاحب القصة عدد الإعجابات، ولغيره حقل ردّ + قلب.
  Widget _bottomBar(Post story, bool mine) {
    if (mine) {
      return InkWell(
        onTap: () => _showViewers(story),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: StreamBuilder<List<StoryViewEntry>>(
            stream: PostService.storyViewers(story.id),
            builder: (_, snap) => Row(
              children: [
                const Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 4),
                const Icon(Icons.visibility_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text('${snap.data?.length ?? 0}',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const Spacer(),
                StreamBuilder<int>(
                  stream: PostService.likeCount(story.id),
                  builder: (_, ls) => Row(
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: Color(0xFFFF3B5C), size: 20),
                      const SizedBox(width: 6),
                      Text('${ls.data ?? story.likes}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _reactionsRow(),
        _replyRow(story),
      ],
    );
  }

  Widget _replyRow(Post story) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller: _reply,
                focusNode: _replyFocus,
                readOnly: !isLoggedIn,
                onTap: () {
                  if (!isLoggedIn) needsLogin(context);
                },
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: Colors.white,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: tr('إرسال رسالة...'),
                  hintStyle: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                maxLength: 500,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          StreamBuilder<bool>(
            stream: PostService.isLiked(story.id),
            builder: (_, snap) {
              final liked = snap.data ?? false;
              return GestureDetector(
                onTap: () {
                  if (needsLogin(context)) return;
                  PostService.toggleLike(story.id, liked).catchError((_) {});
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key: ValueKey(liked),
                    color: liked ? const Color(0xFFFF3B5C) : Colors.white,
                    size: 30,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendReply,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF3385FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryMedia extends StatefulWidget {
  final Post story;
  final bool active;
  final void Function(Duration) onReady;
  const _StoryMedia(
      {super.key,
      required this.story,
      required this.active,
      required this.onReady});

  @override
  State<_StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends State<_StoryMedia> {
  bool _loaded = false; // ظهرت الصورة (أو فشل تحميلها)
  bool _notified = false; // أبلغنا العارض ليبدأ العدّاد

  @override
  void initState() {
    super.initState();
    // قصة نصية: لا صورة لتحميلها، فيبدأ العدّاد مباشرة.
    if (widget.story.bg != null) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNotify());
    }
  }

  /// يبدأ العدّاد فقط بعد تحميل الصورة وعندما تكون هذه الصفحة هي النشطة.
  void _maybeNotify() {
    if (!mounted || !_loaded || !widget.active || _notified) return;
    _notified = true;
    widget.onReady(const Duration(seconds: 5));
  }

  void _onLoaded() {
    _loaded = true;
    _maybeNotify();
  }

  @override
  void didUpdateWidget(covariant _StoryMedia old) {
    super.didUpdateWidget(old);
    // صارت الصفحة نشطة بعد أن حُمّلت صورتها وهي مخفية (سحب بين الأشخاص).
    if (old.active && !widget.active) _notified = false;
    if (!old.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeNotify());
    }
  }

  /// القصة النصية: نص في الوسط فوق تدرج لوني.
  Widget _textStory(int bg) => DecoratedBox(
        decoration: BoxDecoration(gradient: storyGradient(bg)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 90),
            child: Text(
              widget.story.caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.4,
                shadows: [Shadow(blurRadius: 6, color: Color(0x55000000))],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bg = widget.story.bg;
    if (bg != null) return _textStory(bg);
    // الصورة كاملة بدون قص (contain) مع خلفية مموّهة من الصورة نفسها.
    return LayoutBuilder(
      builder: (_, c) => ColoredBox(
        color: const Color(0xFF111111),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: PostImage(
                  post: widget.story, fit: BoxFit.cover, height: c.maxHeight),
            ),
            const ColoredBox(color: Color(0x66000000)),
            Center(
              child: PostImage(
                  post: widget.story,
                  fit: BoxFit.contain,
                  height: c.maxHeight,
                  onLoaded: _onLoaded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  final StoryViewEntry entry;
  const _ViewerTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: UserService.profileStream(entry.uid),
      builder: (_, snap) {
        final u = snap.data;
        final name = u?.username ?? '';
        return ListTile(
          leading:
              UserAvatar(uid: entry.uid, fallbackName: name, radius: 22, profile: u),
          title: Text(name.isEmpty ? '...' : name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(timeAgo(entry.at)),
          onTap: () {
            Navigator.of(context).push(appRoute('user', {'uid': entry.uid},
                (_) => UserProfileScreen(uid: entry.uid)));
          },
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'sound_screen.dart' show openSound, soundTitle;
import 'profile_screen.dart';
import 'story_backgrounds.dart';
import 'story_mentions.dart';
import 'story_movable.dart' show storyCardWidth;
import 'story_reaction_burst.dart';
import 'story_poll.dart';
import 'story_question.dart';
import 'story_info.dart';
import 'story_slider.dart';
import 'story_video.dart';
import '../route_state.dart';

import '../l10n.dart';
import 'close_friends_screen.dart';
import 'install_stub.dart' if (dart.library.html) 'install_web.dart';
/// يتذكر القصص التي شوهدت (لتحويل الحلقة إلى رمادية): على الجهاز، ويُزامَن مع
/// حسابي في Firestore (storySeen) فتبقى رمادية على كل أجهزتي.
class StoryViewed {
  static final Set<String> _seen = {};
  static final Map<String, int> _pending = {}; // مشاهدات لم تُرفع للخادم بعد
  static String? _loadedFor;
  static Future<void>? _loading;
  static Timer? _syncTimer;
  static const _maxStored = 400;
  static const _keepMs = 25 * 3600 * 1000; // القصة تنتهي بعد 24 ساعة

  static String get _key => 'seen_stories_${PostService.uidOrEmpty}';

  /// يحمّل المشاهدات المحفوظة على الجهاز ثم يدمج مشاهدات أجهزتي الأخرى
  /// (بحد أقصى 3 ثوانٍ كي لا يتأخر الشريط عند ضعف الشبكة).
  static Future<void> load() {
    final uid = PostService.uidOrEmpty;
    if (_loadedFor == uid && _loading != null) return _loading!;
    _loadedFor = uid;
    _loading = _doLoad();
    return _loading!;
  }

  static Future<void> _doLoad() async {
    _seen.clear();
    _pending.clear();
    _syncTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen.addAll(prefs.getStringList(_key) ?? const <String>[]);
    } catch (_) {}
    try {
      await _loadRemote().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  static Future<void> _loadRemote() async {
    if (PostService.isGuest) return;
    final remote = await PostService.seenStoriesRemote();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _keepMs;
    final fresh = <String, int>{};
    var stale = 0;
    remote.forEach((id, at) {
      if (at >= cutoff) {
        fresh[id] = at;
      } else {
        stale++;
      }
    });
    _seen.addAll(fresh.keys);
    // مشاهدات محلية لم تصل للخادم بعد (مثلاً قبل تفعيل المزامنة).
    for (final id in _seen) {
      if (!fresh.containsKey(id)) _pending[id] = now;
    }
    if (stale > 50) {
      // تنظيف المستند من المشاهدات المنتهية (قصصها حُذفت).
      await PostService.saveSeenStories({...fresh, ..._pending}, replace: true);
      _pending.clear();
    } else if (_pending.isNotEmpty) {
      _scheduleSync();
    }
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

  static void _scheduleSync() {
    if (PostService.isGuest) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 4), _syncNow);
  }

  /// يرفع المشاهدات الجديدة دفعة واحدة (كتابة واحدة مهما كثرت القصص).
  static Future<void> _syncNow() async {
    if (_pending.isEmpty || PostService.isGuest) return;
    final batch = Map<String, int>.from(_pending);
    try {
      await PostService.saveSeenStories(batch);
      for (final id in batch.keys) {
        _pending.remove(id);
      }
    } catch (_) {
      // تبقى معلّقة وتُرفع مع المشاهدة التالية.
    }
  }

  static bool _add(String id) {
    if (!_seen.add(id)) return false;
    _pending[id] = DateTime.now().millisecondsSinceEpoch;
    _persist();
    _scheduleSync();
    return true;
  }

  static void mark(String id) {
    _add(id);
  }

  /// يعلّم القصة كمشاهدة ويسجّل المشاهدة في الخادم (مرة واحدة فقط).
  static void markAndRecord(Post story) {
    if (_add(story.id)) {
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

  /// هل في المجموعة قصة أصدقاء مقربين لم تُشاهد بعد؟ (حلقة خضراء)
  static bool hasUnseenClose(StoryGroup g) =>
      g.stories.any((s) => s.closeFriends && !_seen.contains(s.id));
}

/// شريط القصص أعلى صفحة المنشورات (مثل إنستغرام).
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key});

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  Stream<List<StoryGroup>>? _groupsStream;
  String? _groupsUid;

  /// تدفّق واحد يُعاد استخدامه بين إعادات البناء (يُنشأ من جديد عند تغيّر
  /// الحساب). يستثني قصص المحظورين والمكتومين ومن أخفوا قصصهم عني.
  Stream<List<StoryGroup>> get _groups {
    final uid = PostService.uidOrEmpty;
    if (_groupsStream == null || _groupsUid != uid) {
      _groupsUid = uid;
      _groupsStream = PostService.storyGroups(applyMutes: true);
    }
    return _groupsStream!;
  }

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
        stream: _groups,
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
                      close: StoryViewed.hasUnseenClose(rest[i]),
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
                      close: mine != null && StoryViewed.hasUnseenClose(mine),
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
      bool close = false,
      required VoidCallback onTap}) {
    return _cell(
      label: label,
      child: GestureDetector(
          onTap: onTap,
          child: _ring(uid, label, seen: seen, active: true, close: close)),
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
      {required bool seen, required bool active, bool close = false}) {
    return Container(
      width: 66,
      height: 66,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active && !seen
            ? (close ? closeFriendsGradient : AppColors.storyGradient)
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late int _g = widget.initial;
  late int _s;
  bool _ready = false;
  bool _hideUi = false; // أثناء الضغط المطوّل
  bool _muted = false; // صوت قصص الفيديو
  int _restartSeq = 0; // إعادة فيديو القصة من البداية
  double _dragDy = 0; // سحب للأسفل للإغلاق
  final Set<String> _pauseReasons = {};
  late final AnimationController _t;
  late final PageController _pc = PageController(initialPage: widget.initial);
  final TextEditingController _reply = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final FocusNode _keyFocus = FocusNode(debugLabel: 'storyKeys');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _s = _firstUnseen(widget.groups[_g]);
    StoryViewed.load();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _next();
      });
    _replyFocus.addListener(() => _setPause('typing', _replyFocus.hasFocus));
    StoryViewed.markAndRecord(_story);
    _archiveIfMine();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheNext());
  }

  /// قصتي الحية تُنسخ إلى أرشيفي إن لم تكن منسوخة (للقصص القديمة).
  void _archiveIfMine() {
    final s = _story;
    if (s.uid == PostService.uidOrEmpty) PostService.ensureArchived(s);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t.dispose();
    _pc.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  /// يوقف القصة عند خروج التطبيق من الواجهة (أو إخفاء تبويب المتصفح).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setPause('background', state != AppLifecycleState.resumed);
  }

  /// اختصارات لوحة المفاتيح (سطح المكتب): الأسهم للتنقل، Esc للإغلاق،
  /// المسافة للإيقاف/المتابعة. تُتجاهل أثناء الكتابة في خانة الردّ.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _replyFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      rtl ? _prev() : _next();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      rtl ? _next() : _prev();
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (k == LogicalKeyboardKey.space) {
      _setPause('key', !_pauseReasons.contains('key'));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
    if (!on && reason != 'key' && !_replyFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_replyFocus.hasFocus) _keyFocus.requestFocus();
      });
    }
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
    _archiveIfMine();
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
      _restartSeq++;
      _t.forward(from: 0);
      setState(() {});
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

  Future<void> _openUser(String uid) async {
    _setPause('nav', true);
    await Navigator.of(context).push(
        appRoute('user', {'uid': uid}, (_) => UserProfileScreen(uid: uid)));
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ViewersSheet(story: story),
      ),
    );
    _setPause('viewers', false);
  }

  Future<void> _sendReply() async {
    if (needsLogin(context)) return;
    final story = _story; // القصة وقت الإرسال (قد تتغير أثناء الانتظار)
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _reply.clear();
    _replyFocus.unfocus();
    try {
      final id = await SocialService.startConversation(story.uid);
      await SocialService.sendStoryReply(id, story, text);
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
    final story = _story;
    final messenger = ScaffoldMessenger.of(context);
    // أثر فوري: انفجار إيموجي واهتزاز خفيف (بدون انتظار الشبكة).
    showEmojiBurst(context, emoji);
    HapticFeedback.selectionClick();
    // يظهر التفاعل لصاحب القصة في قائمة المشاهدين (لا يمنع الرسالة إن فشل).
    PostService.reactToStory(story, emoji).catchError((_) {});
    try {
      final id = await SocialService.startConversation(story.uid);
      await SocialService.sendStoryReply(id, story, emoji);
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
      body: Focus(
        focusNode: _keyFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_replyFocus.hasFocus) {
            _replyFocus.unfocus();
            _keyFocus.requestFocus();
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
                          onReady: _onReady,
                          // التخزين المؤقت لا يوقف الفيديو (هو فقط يوقف العدّاد).
                          paused: _pauseReasons.any((r) => r != 'buffer'),
                          muted: _muted,
                          restartSeq: _restartSeq,
                          onBuffering: (b) => _setPause('buffer', b),
                          onAutoplayBlocked: () {
                            if (mounted) setState(() => _muted = true);
                          }),
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
                            if (story.mentions.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 10),
                                child: StoryMentionsRow(
                                    mentions: story.mentions,
                                    onOpen: _openUser),
                              ),
                            if (story.info != null)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                child: StoryInfoRow(
                                    info: story.info!,
                                    createdAt: story.createdAt),
                              ),
                            if (story.slider != null && !story.slider!.placed)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                child: StorySliderCard(
                                    key: ValueKey('slider-${story.id}'),
                                    story: story,
                                    slider: story.slider!,
                                    mine: mine),
                              ),
                            if (story.question != null &&
                                !story.question!.placed)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                child: StoryQuestionCard(
                                    key: ValueKey('question-${story.id}'),
                                    story: story,
                                    question: story.question!,
                                    mine: mine,
                                    onPause: (v) => _setPause('question', v)),
                              ),
                            if (story.poll != null && !story.poll!.placed)
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
                            if (story.sound != null) _soundPill(story.sound!),
                            if (story.caption.isNotEmpty && story.bg == null)
                              _caption(story),
                          ],
                        ),
                      ),
                      _placedCards(story, mine, active),
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

  /// مستطيل الوسائط داخل الإطار: الصورة تُعرض كاملة (contain) فنحسب مكانها من
  /// نسبتها [ar]؛ القصة النصية أو بدون نسبة = الإطار كله.
  Rect _mediaRect(Size frame, double? ar, bool textStory) {
    if (textStory || ar == null || frame.isEmpty) return Offset.zero & frame;
    final fa = frame.width / frame.height;
    if (ar >= fa) {
      final h = frame.width / ar;
      return Rect.fromLTWH(0, (frame.height - h) / 2, frame.width, h);
    }
    final w = frame.height * ar;
    return Rect.fromLTWH((frame.width - w) / 2, 0, w, frame.height);
  }

  /// الاستطلاع وصندوق الأسئلة وشريط الإيموجي التي وضعها صاحب القصة في مكان
  /// محدد (القصص القديمة بلا موضع تبقى أسفل الشاشة).
  Widget _placedCards(Post story, bool mine, bool active) {
    final poll = story.poll, q = story.question, sl = story.slider;
    final hasPoll = poll != null && poll.placed;
    final hasQ = q != null && q.placed;
    final hasSl = sl != null && sl.placed;
    if (!hasPoll && !hasQ && !hasSl) return const SizedBox.shrink();
    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: (_hideUi && active) ? 0 : 1,
        child: LayoutBuilder(builder: (context, c) {
          final frame = Size(c.maxWidth, c.maxHeight);
          final kb = MediaQuery.of(context).viewInsets.bottom;
          // يُكتب في صندوق الأسئلة: نرفعه فوق الكيبورد كي لا يختفي خلفه.
          final lift = kb > 0 && _pauseReasons.contains('question');
          Widget place(double x, double y, double s, double? ar, Widget card,
              {bool avoidKeyboard = false}) {
            final r = _mediaRect(frame, ar, story.bg != null);
            var cy = r.top + y * r.height;
            if (avoidKeyboard && lift) {
              cy = math.min(cy, frame.height - kb - 70 * s - 8);
            }
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 160),
              left: r.left + x * r.width,
              top: cy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: Transform.scale(
                  scale: s,
                  child: SizedBox(width: storyCardWidth(r.width), child: card),
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (hasSl)
                place(
                    sl!.x!,
                    sl.y!,
                    sl.s ?? 1,
                    sl.ar,
                    StorySliderCard(
                        key: ValueKey('slider-${story.id}'),
                        story: story,
                        slider: sl,
                        mine: mine)),
              if (hasQ)
                place(
                    q!.x!,
                    q.y!,
                    q.s ?? 1,
                    q.ar,
                    StoryQuestionCard(
                        key: ValueKey('question-${story.id}'),
                        story: story,
                        question: q,
                        mine: mine,
                        onPause: (v) => _setPause('question', v)),
                    avoidKeyboard: true),
              if (hasPoll)
                place(
                    poll!.x!,
                    poll.y!,
                    poll.s ?? 1,
                    poll.ar,
                    StoryPollCard(
                        key: ValueKey('poll-${story.id}'),
                        story: story,
                        poll: poll,
                        mine: mine)),
            ],
          );
        }),
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
                if (story.closeFriends) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: tr('الأصدقاء المقربون'),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: kCloseFriendsGreen),
                      child: const Icon(Icons.star_rounded,
                          size: 15, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (story.isVideoStory)
            IconButton(
                tooltip: _muted ? tr('تشغيل الصوت') : tr('كتم الصوت'),
                onPressed: () => setState(() => _muted = !_muted),
                icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white)),
          if (mine || isLoggedIn)
            IconButton(
                onPressed: () => mine
                    ? _showStoryMenu(story)
                    : _showOthersStoryMenu(group, story),
                icon: const Icon(Icons.more_horiz, color: Colors.white)),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _showStoryMenu(Post story) async {
    _setPause('menu', true);
    await showModalBottomSheet(
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
    _setPause('menu', false);
  }

  /// قائمة قصة غيري: إبلاغ، كتم قصص صاحبها، إخفاء قصصي عنه.
  Future<void> _showOthersStoryMenu(StoryGroup group, Post story) async {
    if (needsLogin(context)) return;
    _setPause('menu', true);
    var muted = false, hiding = false;
    try {
      final r = await Future.wait([
        PostService.isStoryMuted(group.uid),
        PostService.isHidingStoriesFrom(group.uid),
      ]);
      muted = r[0];
      hiding = r[1];
    } catch (_) {}
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget item(IconData icon, String label, String value,
                {Color color = Colors.white}) =>
            ListTile(
              leading: Icon(icon, color: color),
              title: Text(label, style: TextStyle(color: color, fontSize: 16)),
              onTap: () => Navigator.pop(ctx, value),
            );
        return SafeArea(
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
              item(Icons.flag_outlined, tr('إبلاغ عن القصة'), 'report',
                  color: const Color(0xFFFF6B6B)),
              item(
                  muted
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                  muted
                      ? trf('إلغاء كتم قصص @{0}', [group.username])
                      : trf('كتم قصص @{0}', [group.username]),
                  'mute'),
              item(
                  hiding
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  hiding
                      ? trf('إظهار قصصي لـ @{0}', [group.username])
                      : trf('إخفاء قصصي عن @{0}', [group.username]),
                  'hide'),
              item(Icons.close, tr('إلغاء'), 'cancel'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'report':
        await _reportStory(group, story);
      case 'mute':
        await _toggleMute(group, muted);
      case 'hide':
        await _toggleHide(group, hiding);
    }
    if (mounted) _setPause('menu', false);
  }

  Future<void> _reportStory(StoryGroup group, Post story) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(tr('إبلاغ عن هذه القصة'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.text)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                    tr('اختر السبب الأقرب. لن يعرف صاحب القصة أنك من أبلغ.'),
                    style: TextStyle(
                        fontSize: 12, color: context.appColors.textDim)),
              ),
            ),
            for (final r in SocialService.reportReasons.entries)
              ListTile(
                title: Text(tr(r.value)),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.pop(ctx, r.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await SocialService.reportStory(story.id, story.uid, reason);
      messenger.showSnackBar(
          SnackBar(content: Text(tr('تم إرسال البلاغ، شكراً لك'))));
      if (mounted) _next();
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(tr('تعذر إرسال البلاغ'))));
    }
  }

  Future<void> _toggleMute(StoryGroup group, bool wasMuted) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await PostService.setStoryMuted(group.uid, !wasMuted);
      messenger.showSnackBar(SnackBar(
          content: Text(wasMuted
              ? trf('أُلغي كتم قصص @{0}', [group.username])
              : trf('تم كتم قصص @{0}. تجدها دائماً من ملفه الشخصي',
                  [group.username]))));
      if (!wasMuted && mounted) nav.pop(); // تختفي من الشريط
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذّر تنفيذ الإجراء'))));
    }
  }

  Future<void> _toggleHide(StoryGroup group, bool wasHiding) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.setStoriesHiddenFrom(group.uid, !wasHiding);
      messenger.showSnackBar(SnackBar(
          content: Text(wasHiding
              ? trf('ستظهر قصصك لـ @{0}', [group.username])
              : trf('أُخفيت قصصك عن @{0}', [group.username]))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذّر تنفيذ الإجراء'))));
    }
  }

  /// شارة الصوت المستخدم في القصة: تفتح صفحة الصوت.
  Widget _soundPill(PostSound sound) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: () => openSound(context, sound, root: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0x99000000),
              borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note_rounded,
                  size: 15, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${soundTitle(sound)} · @${sound.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
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
          child: Builder(
            builder: (_) => Row(
              children: [
                const Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 4),
                const Icon(Icons.visibility_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 6),
                _ViewCount(key: ValueKey('vc-${story.id}'), storyId: story.id),
                const Spacer(),
                if (!story.closeFriends)
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
          if (!story.closeFriends) ...[
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
          ],
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
  final bool paused;
  final bool muted;
  final int restartSeq;
  final void Function(bool) onBuffering;
  final VoidCallback onAutoplayBlocked;
  const _StoryMedia(
      {super.key,
      required this.story,
      required this.active,
      required this.onReady,
      this.paused = false,
      this.muted = false,
      this.restartSeq = 0,
      required this.onBuffering,
      required this.onAutoplayBlocked});

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

  /// مدة العرض: 5 ثوانٍ للصورة، وللقصة النصية تزيد مع طول النص (حتى 14 ثانية).
  Duration _duration() {
    if (widget.story.bg == null) return const Duration(seconds: 5);
    final chars = widget.story.caption.trim().length;
    final ms = (4000 + chars * 60).clamp(5000, 14000).toInt();
    return Duration(milliseconds: ms);
  }

  /// يبدأ العدّاد فقط بعد تحميل الصورة وعندما تكون هذه الصفحة هي النشطة.
  void _maybeNotify() {
    if (!mounted || !_loaded || !widget.active || _notified) return;
    _notified = true;
    widget.onReady(_duration());
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
    final isVideo = widget.story.isVideoStory;
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
                  // قصة الفيديو: العدّاد يبدأ من الفيديو لا من صورة الغلاف.
                  onLoaded: isVideo ? null : _onLoaded),
            ),
            if (isVideo)
              StoryVideoView(
                url: widget.story.storyVideoUrl!,
                overlayUrl: widget.story.storyOverlayUrl,
                filter: widget.story.storyFilter,
                active: widget.active,
                paused: widget.paused,
                muted: widget.muted,
                restartSeq: widget.restartSeq,
                onReady: widget.onReady,
                onBuffering: widget.onBuffering,
                onAutoplayBlocked: widget.onAutoplayBlocked,
                onFailed: () {},
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
          trailing: entry.reaction == null
              ? null
              : Text(entry.reaction!, style: const TextStyle(fontSize: 26)),
          onTap: () {
            Navigator.of(context).push(appRoute('user', {'uid': entry.uid},
                (_) => UserProfileScreen(uid: entry.uid)));
          },
        );
      },
    );
  }
}

/// عدّاد مشاهدات قصتي: استعلام تجميعي (بلا حد 200) يتجدد كل 20 ثانية.
class _ViewCount extends StatefulWidget {
  final String storyId;
  const _ViewCount({super.key, required this.storyId});

  @override
  State<_ViewCount> createState() => _ViewCountState();
}

class _ViewCountState extends State<_ViewCount> {
  int? _n;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.storyId;
    try {
      final n = await PostService.storyViewCount(id);
      if (mounted && id == widget.storyId) setState(() => _n = n);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Text('${_n ?? 0}',
      style: const TextStyle(color: Colors.white, fontSize: 15));
}

/// قائمة المشاهدين: العدد الكلي، بحث بالاسم، تصفية التفاعلات، وتحميل المزيد.
class _ViewersSheet extends StatefulWidget {
  final Post story;
  const _ViewersSheet({required this.story});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  static const _step = 100;
  static const _maxLimit = 1000;
  int _limit = _step;
  late Stream<List<StoryViewEntry>> _stream =
      PostService.storyViewers(widget.story.id, limit: _limit);
  late final Future<int> _total = PostService.storyViewCount(widget.story.id);
  final TextEditingController _q = TextEditingController();
  String _query = '';
  bool _reactionsOnly = false;
  final Map<String, AppUser?> _users = {};
  final Set<String> _fetching = {};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _loadMore() {
    setState(() {
      _limit = math.min(_limit + _step, _maxLimit);
      _stream = PostService.storyViewers(widget.story.id, limit: _limit);
    });
  }

  /// يجلب ملفات المشاهدين عند البحث فقط (UserService يخزّنها مؤقتاً).
  Future<void> _resolve(List<StoryViewEntry> list) async {
    final missing = [
      for (final e in list)
        if (!_users.containsKey(e.uid) && _fetching.add(e.uid)) e.uid
    ];
    if (missing.isEmpty) return;
    final res = await Future.wait(
        missing.map((u) => UserService.profileOf(u).catchError((_) => null)));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < missing.length; i++) {
        _users[missing[i]] = res[i];
      }
    });
  }

  bool _matches(AppUser? u, String q) =>
      u != null &&
      (u.username.toLowerCase().contains(q) || u.name.toLowerCase().contains(q));

  List<StoryViewEntry> _filtered(List<StoryViewEntry> all) {
    var out = all;
    if (_reactionsOnly) {
      out = [
        for (final e in out)
          if (e.reaction != null) e
      ];
    }
    final q = _query.trim().toLowerCase().replaceAll('@', '');
    if (q.isEmpty) return out;
    return [
      for (final e in out)
        if (_matches(_users[e.uid], q)) e
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Text(tr('المشاهدون'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(width: 8),
                FutureBuilder<int>(
                  future: _total,
                  builder: (_, s) => Text(s.hasData ? '${s.data}' : '',
                      style: TextStyle(
                          color: c.textDim, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                FilterChip(
                  label: Text(tr('التفاعلات')),
                  selected: _reactionsOnly,
                  onSelected: (v) => setState(() => _reactionsOnly = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('ابحث في المشاهدين'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _q.clear();
                          setState(() => _query = '');
                        }),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<StoryViewEntry>>(
              stream: _stream,
              builder: (_, snap) {
                final all = snap.data ?? const <StoryViewEntry>[];
                if (all.isEmpty) {
                  return Center(
                      child: Text(
                          snap.connectionState == ConnectionState.waiting
                              ? ''
                              : tr('لا توجد مشاهدات بعد'),
                          style: TextStyle(color: c.textDim)));
                }
                if (_query.trim().isNotEmpty) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _resolve(all));
                }
                final list = _filtered(all);
                final more = all.length >= _limit && _limit < _maxLimit;
                if (list.isEmpty && !more) {
                  return Center(
                      child: Text(tr('لا نتائج'),
                          style: TextStyle(color: c.textDim)));
                }
                return ListView.builder(
                  itemCount: list.length + (more ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextButton(
                            onPressed: _loadMore,
                            child: Text(tr('عرض المزيد'))),
                      );
                    }
                    return _ViewerTile(entry: list[i]);
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

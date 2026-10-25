import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'post_widgets.dart';
import 'story_widgets.dart';

import '../l10n.dart';
/// يزداد عند الضغط على أيقونة الرئيسية وأنت فيها: تمرير للأعلى وتحديث.
final ValueNotifier<int> homeRefreshTick = ValueNotifier<int>(0);

/// الرئيسية: شريط القصص ثم منشورات المستخدمين بالأحدث، وتُحمَّل دفعات عند التمرير.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

enum _FeedMode { all, following }

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  late Stream<List<Post>> _shortsFeed = _allShorts();
  final ScrollController _scroll = ScrollController();

  // التحميل على دفعات: كل «مصدر» = نوع منشور (صور/نصوص) + مجموعة حسابات (حتى 30،
  // حد Firestore)، بمؤشره الخاص. في «المتابَعون» ننشئ مصدراً لكل 30 حساباً حتى
  // لا يُهمَل من يتابع أكثر من 30 حساباً.
  List<_Src> _srcs = const [];
  bool _loaded = false; // وصلت الدفعة الأولى للوضع الحالي
  bool _loading = false;
  Object? _error;
  _FeedMode _mode = _FeedMode.all;
  List<String>? _followIds;
  List<String> _privateIds = const []; // متابَعون حساباتهم خاصة: يُجلبون منفصلين
  final Map<String, DocumentSnapshot<Map<String, dynamic>>?> _privCursor = {};
  final Set<String> _privDone = {};
  List<Post> _privPosts = const [];
  bool get _morePrivate => _privateIds.any((id) => !_privDone.contains(id));
  bool _more() =>
      _srcs.any((s) => s.more) ||
      (_mode == _FeedMode.following && _morePrivate);
  // // حسابات أتابعها (تُجلب عند أول فتح لتبويب المتابَعين)
  Set<String> _hiddenBase = const {}; // مخفيّات وقت آخر تحديث (الجديدة تُعرض بشريط تراجع)
  int _gen = 0; // يُلغي نتائج طلب قديم إذا بدأ تحديث جديد

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_refresh);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_refresh);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 600) _load();
  }

  /// تمرير إلى الأعلى ثم إعادة التحميل من الدفعة الأولى (البيانات القديمة تبقى ظاهرة حتى تصل الجديدة).
  void _refresh() {
    if (!mounted) return;
    stopInlineVideos();
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    setState(() => _shortsFeed = _allShorts());
    _load(reset: true);
  }

  /// سحب للتحديث: ينتهي المؤشر عند وصول الدفعة الأولى.
  Future<void> _pullRefresh() {
    if (!mounted) return Future<void>.value();
    stopInlineVideos();
    setState(() => _shortsFeed = _allShorts());
    return _load(reset: true);
  }

  void _setMode(_FeedMode m) {
    if (m == _mode) return;
    // «المتابَعون» يحتاج حساباً: الزائر يرى «للجميع» فقط.
    if (m == _FeedMode.following && needsLogin(context)) return;
    stopInlineVideos();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _mode = m;
      _loaded = false;
      _srcs = const [];
    });
    _load(reset: true);
  }

  /// يجلب الدفعة الأولى ([reset]) أو التالية، ويضيفها إلى القائمة.
  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more())) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (reset) {
        await PostService.loadHiddenIds();
        _hiddenBase = {...PostService.hiddenIds.value};
      }
      if (_mode == _FeedMode.following) {
        if (reset || _followIds == null) {
          final ids =
              await PostService.followingIdsOnce(PostService.uidOrEmpty);
          // نفصل أصحاب الحسابات الخاصة: لا يمكن جلبهم مع البقية في طلب واحد.
          final profiles = await Future.wait(ids.map(UserService.profileOf));
          _followIds = ids;
          _privateIds = [
            for (var i = 0; i < ids.length; i++)
              if (profiles[i]?.isPrivate == true) ids[i]
          ];
          if (reset) {
            _privCursor.clear();
            _privDone.clear();
          }
        }
      }
      // المصادر: عند التحديث نبنيها من جديد، وإلا نكمل على الحالية.
      List<_Src> srcs = _srcs;
      if (reset) {
        srcs = <_Src>[];
        if (_mode == _FeedMode.all) {
          srcs.add(_Src(PostType.photo, null));
          srcs.add(_Src(PostType.text, null));
        } else {
          final pub = [
            for (final id in _followIds!)
              if (!_privateIds.contains(id)) id
          ];
          for (var i = 0; i < pub.length; i += 30) {
            final end = i + 30 > pub.length ? pub.length : i + 30;
            final chunk = pub.sublist(i, end);
            srcs.add(_Src(PostType.photo, chunk));
            srcs.add(_Src(PostType.text, chunk));
          }
        }
      }
      // الحسابات الخاصة: دفعة لكل حساب لم ينتهِ.
      final privIds = _mode != _FeedMode.following
          ? const <String>[]
          : [
              for (final id in _privateIds)
                if (!_privDone.contains(id)) id
            ];
      final privPages = await Future.wait([
        for (final id in privIds)
          PostService.userPage(id, after: reset ? null : _privCursor[id])
      ]);
      final todo = [
        for (final s in srcs)
          if (reset || s.more) s
      ];
      final pages = await Future.wait([
        for (final s in todo)
          PostService.page(s.type,
              after: reset ? null : s.cursor, uids: s.uids)
      ]);
      if (!mounted || gen != _gen) return;
      setState(() {
        for (var i = 0; i < todo.length; i++) {
          final s = todo[i], pg = pages[i];
          s.posts = _merge(reset ? null : s.posts, pg.posts);
          s.cursor = pg.cursor;
          s.more = pg.hasMore;
        }
        _srcs = srcs;
        _loaded = true;
        if (_mode == _FeedMode.following) {
          _privPosts = _merge(reset ? null : _privPosts, [
            for (final pg in privPages) ...pg.posts,
          ]);
          for (var i = 0; i < privIds.length; i++) {
            _privCursor[privIds[i]] = privPages[i].cursor;
            if (!privPages[i].hasMore) _privDone.add(privIds[i]);
          }
        } else {
          _privPosts = const [];
        }
        _loading = false;
      });
      // إن قلّ ما يظهر (بسبب الترتيب أو الفلترة) نكمل الجلب دون انتظار تمرير.
      if (_more() && _visible().length < 6) _load();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// المنشورات الظاهرة (غير الريلز) مرتبة بالأحدث.
  /// نعرض فقط ما هو أحدث من «حدّ الأمان»: أقدم منشور في كل مصدر لم ينتهِ بعد.
  /// وإلا قد تصل دفعة لاحقة بمنشور أحدث مما رأيته فتُدرج في وسط القائمة
  /// وتقفز الصفحة أثناء التمرير.
  List<Post> _visible() {
    DateTime? cutoff;
    void consider(Iterable<Post> list) {
      if (list.isEmpty) return;
      var oldest = list.first.createdAt;
      for (final p in list) {
        if (p.createdAt.isBefore(oldest)) oldest = p.createdAt;
      }
      if (cutoff == null || oldest.isAfter(cutoff!)) cutoff = oldest;
    }

    for (final s in _srcs) {
      if (s.more) consider(s.posts);
    }
    if (_mode == _FeedMode.following) {
      for (final id in _privateIds) {
        if (!_privDone.contains(id)) {
          consider(_privPosts.where((p) => p.uid == id));
        }
      }
    }
    final seen = <String>{};
    final all = [
      for (final s in _srcs) ...s.posts,
      ..._privPosts,
    ];
    final cut = cutoff;
    return [
      for (final p in all)
        if (!p.isShort &&
            !_hiddenBase.contains(p.id) &&
            seen.add(p.id) &&
            (cut == null || !p.createdAt.isBefore(cut)))
          p
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static List<Post> _merge(List<Post>? old, List<Post> add) {
    final ids = {for (final p in old ?? const <Post>[]) p.id};
    return [...?old, for (final p in add) if (!ids.contains(p.id)) p];
  }

  /// كل الشورتز (حتى 100 من الحسابات العامة) بالأحدث، مستقلة عن قائمة المنشورات
  /// كي يتنقل عارض شورتز بينها كلها وليس بما يظهر في الرئيسية فقط.
  /// نفس استعلام النصوص الحالي (فهرسه موجود) ثم نصفّي شورتز محلياً.
  Stream<List<Post>> _allShorts() =>
      PostService.stream(PostType.text, limit: 100)
          .map((list) => [for (final p in list) if (p.isShort) p]);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Post>>(
        stream: _shortsFeed,
        builder: (context, shortsSnap) {
          final following = _mode == _FeedMode.following;
          final followSet = {...?_followIds};
          final pubShorts = [
            for (final p in shortsSnap.data ?? const <Post>[])
              if (!following || followSet.contains(p.uid)) p
          ];
          // ريلز الحسابات الخاصة التي أتابعها: تأتي مع منشوراتها (لا مع الاستعلام العام).
          final privShorts = following
              ? [
                  for (final p in _privPosts)
                    if (p.isShort && !_hiddenBase.contains(p.id)) p
                ]
              : const <Post>[];
          final seenShorts = <String>{};
          final shorts = [
            for (final p in [...pubShorts, ...privShorts])
              if (seenShorts.add(p.id)) p
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          // شورتز تظهر في شريط أفقي، والبقية منشورات عادية.
          final posts = !_loaded ? null : _visible();
          final hasPosts = posts != null && posts.isNotEmpty;
          // شريط شورتز في الأعلى مباشرة تحت القصص ليعرف المستخدم بوجوده.
          const shortsAt = 0;
          final hasShorts = shorts.isNotEmpty;
          final rows = hasPosts ? posts.length + 1 : 2;
          final showFooter = hasPosts && _loading;
          final count = rows + (hasShorts ? 1 : 0) + (showFooter ? 1 : 0);
          return RefreshIndicator(
            onRefresh: _pullRefresh,
            child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: count,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Column(children: [
                  const StoriesBar(),
                  Divider(
                      height: 1,
                      color: context.appColors.text.withOpacity(0.12)),
                  _FeedModeBar(mode: _mode, onChanged: _setMode),
                ]);
              }
              if (showFooter && i == count - 1) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5))),
                );
              }
              if (hasShorts && i == shortsAt + 1) {
                return ShortsRow(shorts: shorts);
              }
              final idx = (hasShorts && i > shortsAt + 1) ? i - 1 : i;
              if (hasPosts) {
                final post = posts[idx - 1];
                return PostCard(key: ValueKey(post.id), post: post);
              }
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(trf('تعذر تحميل المنشورات\n{0}', [_error]),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _load(reset: true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr('إعادة المحاولة')),
                      ),
                    ],
                  ),
                );
              }
              // الدفعة الأولى لم تصل بعد: هياكل تحميل بدل شاشة فارغة.
              if (posts == null || _loading) return const _FeedSkeleton();
              return following
                  ? EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: tr('لا جديد من متابَعيك'),
                      message:
                          tr('تابع حسابات لترى منشوراتها هنا.'),
                    )
                  : EmptyState(
                      icon: Icons.photo_library_outlined,
                      title: tr('لا توجد منشورات بعد'),
                      message: tr('شارك أول صورة أو خاطرة مع مجتمعنا.'),
                    );
            },
          ));
        },
      ),
    );
  }
}

/// مفتاح بين "للجميع" و"المتابَعون" أعلى الرئيسية.
class _FeedModeBar extends StatelessWidget {
  final _FeedMode mode;
  final ValueChanged<_FeedMode> onChanged;
  const _FeedModeBar({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget item(String label, _FeedMode m) {
      final selected = mode == m;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(m),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.text : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? colors.text : colors.textDim,
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      item(tr('الكل'), _FeedMode.all),
      item(tr('أتابعه'), _FeedMode.following),
    ]);
  }
}


/// مصدر تحميل: نوع منشور + مجموعة حسابات (null = الجميع) بمؤشره الخاص.
class _Src {
  final PostType type;
  final List<String>? uids;
  DocumentSnapshot<Map<String, dynamic>>? cursor;
  bool more = true;
  List<Post> posts = const [];
  _Src(this.type, this.uids);
}

/// هياكل تحميل تظهر قبل وصول أول دفعة من المنشورات.
class _FeedSkeleton extends StatefulWidget {
  const _FeedSkeleton();

  @override
  State<_FeedSkeleton> createState() => _FeedSkeletonState();
}

class _FeedSkeletonState extends State<_FeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.appColors.text.withOpacity(0.08);
    Widget bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: base, borderRadius: BorderRadius.circular(6)));
    Widget card() => Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration:
                        BoxDecoration(color: base, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar(110, 12), const SizedBox(height: 6), bar(70, 10)]),
              ]),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                    decoration: BoxDecoration(
                        color: base, borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 12),
              bar(180, 12),
            ],
          ),
        );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
      child: Column(children: [card(), card()]),
    );
  }
}

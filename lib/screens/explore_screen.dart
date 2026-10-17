import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import '../route_state.dart';

import '../l10n.dart';
/// عدد أعمدة الشبكة حسب عرض الشاشة.
int _gridColumns(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 900 ? 5 : (width >= 600 ? 4 : 3);
}

/// شريحة اختيار موحّدة (تبويبات الاستكشاف والبحث).
Widget _choiceChip(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    selectedColor: AppColors.brandPurple,
    labelStyle: TextStyle(
      fontWeight: FontWeight.w600,
      color: selected ? Colors.white : context.appColors.text,
    ),
    onSelected: (_) => onTap(),
  );
}

/// مربع منشور في الشبكة: صورة، أو صورة فيديو مع أيقونة تشغيل، أو نص.
Widget _postTile(BuildContext context, Post post, {bool root = false}) {
  Widget child;
  if (post.hasVideo) {
    child = Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: post.videoThumb!,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: Colors.black),
        ),
        const Positioned(
          top: 6,
          right: 6,
          child: Icon(Icons.play_circle_fill_rounded,
              color: Colors.white, size: 22),
        ),
      ],
    );
  } else if (post.type == PostType.photo) {
    child = Stack(
      fit: StackFit.expand,
      children: [
        PostImage(post: post),
        if (post.isAlbum)
          const PositionedDirectional(
            top: 6,
            end: 6,
            child: Icon(Icons.collections_rounded,
                color: Colors.white,
                size: 18,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
          ),
      ],
    );
  } else {
    child = Container(
      color: context.appColors.surfaceHigh,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(
        post.caption,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
  return GestureDetector(
    onTap: () => (root ? rootNavigatorOf(context) : Navigator.of(context))
        .push(appRoute('post', {'id': post.id},
            (_) => PostDetailScreen(post: post))),
    child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
  );
}

/// استكشاف: حقل البحث، شريط الهاشتاقات الرائجة، تبويبات (الكل/صور/فيديوهات)
/// وشبكة موحّدة. عند الضغط على حقل البحث أو هاشتاق تُفتح صفحة البحث.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

enum _ExploreFilter { all, photos, videos }

class _ExploreScreenState extends State<ExploreScreen> {
  // قراءة واحدة (30 منشوراً) تغذّي الهاشتاقات والصور والفيديوهات معاً،
  // وتُخزَّن 5 دقائق؛ السحب للتحديث يفرض قراءة جديدة.
  late Future<List<Post>> _feed = PostService.exploreFeed();
  bool _searchOpen = false;
  _ExploreFilter _filter = _ExploreFilter.all;

  Future<void> _openSearch({String? query}) async {
    if (_searchOpen) return;
    _searchOpen = true;
    try {
      await rootNavigatorOf(context).push<void>(
        appRoute<void>('search', const {},
            (_) => ExploreSearchScreen(initialQuery: query)),
      );
    } finally {
      _searchOpen = false;
    }
  }

  Future<void> _refresh() async {
    final feed = PostService.exploreFeed(force: true);
    setState(() => _feed = feed);
    try {
      await feed;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              readOnly: true,
              showCursor: false,
              onTap: _openSearch,
              decoration: InputDecoration(
                hintText: tr('ابحث بالاسم أو اسم المستخدم أو هاشتاق'),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Post>>(
                future: _feed,
                builder: (context, snap) {
                  const listPadding = EdgeInsets.only(left: 12, right: 12);
                  if (snap.hasError) {
                    return ListView(
                      padding: listPadding,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(trf('تعذر تحميل الاستكشاف\n{0}', [snap.error]),
                              textAlign: TextAlign.center),
                        ),
                      ],
                    );
                  }
                  if (!snap.hasData) {
                    return ListView(
                      padding: listPadding,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: AppLoading(message: tr('جارٍ الاستكشاف...')),
                        ),
                      ],
                    );
                  }
                  return _content(snap.data!);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(List<Post> posts) {
    final shorts = [
      for (final p in posts)
        if (p.hasVideo && p.isShort) p
    ];
    final videos = [
      for (final p in posts)
        if (p.hasVideo && !p.isShort) p
    ];
    final photos = [
      for (final p in posts)
        if (!p.hasVideo && p.type == PostType.photo) p
    ];

    // الشبكة الموحّدة: «الكل» تحافظ على ترتيب الأحدث أولاً (صور + فيديوهات عادية).
    final List<Post> gridItems;
    switch (_filter) {
      case _ExploreFilter.photos:
        gridItems = photos;
      case _ExploreFilter.videos:
        gridItems = videos;
      case _ExploreFilter.all:
        gridItems = [
          for (final p in posts)
            if ((p.hasVideo && !p.isShort) ||
                (!p.hasVideo && p.type == PostType.photo))
              p
        ];
    }
    // الشورتز تظهر في تبويب «فيديوهات» فقط حتى لا تزدحم الصفحة الرئيسية.
    final showShorts = _filter == _ExploreFilter.videos && shorts.isNotEmpty;
    final isEmpty = gridItems.isEmpty && !showShorts;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _filterBar()),
        if (showShorts)
          SliverToBoxAdapter(
            child: ShortsRow(
                shorts: shorts,
                padding: const EdgeInsets.only(top: 4, bottom: 8)),
          ),
        if (isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: _filter == _ExploreFilter.videos
                  ? Icons.videocam_outlined
                  : Icons.photo_library_outlined,
              title: _filter == _ExploreFilter.videos
                  ? tr('لا توجد فيديوهات بعد')
                  : tr('لا توجد صور بعد'),
              message: tr('ستظهر هنا أحدث ما يشاركه المستخدمون.'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 80),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridColumns(context),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _postTile(context, gridItems[i]),
                childCount: gridItems.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterBar() {
    final labels = {
      _ExploreFilter.all: tr('الكل'),
      _ExploreFilter.photos: tr('صور'),
      _ExploreFilter.videos: tr('فيديوهات'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          for (final entry in labels.entries) ...[
            _choiceChip(
              context,
              label: entry.value,
              selected: _filter == entry.key,
              onTap: () => setState(() => _filter = entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// صفحة البحث: تُفتح فوق الشريط السفلي وفيها عمليات البحث السابقة والرائج
/// ونتائج البحث (حسابات / منشورات) مع بحث تلقائي أثناء الكتابة.
class ExploreSearchScreen extends StatefulWidget {
  /// نص يُبحث عنه فور فتح الصفحة (مثل هاشتاق ضغطت عليه).
  final String? initialQuery;

  const ExploreSearchScreen({super.key, this.initialQuery});

  @override
  State<ExploreSearchScreen> createState() => _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends State<ExploreSearchScreen> {
  static const _recentKey = 'explore_recent_searches';
  static const _recentMax = 8;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late Future<Map<String, int>> _trendingFuture = _loadTrending();
  Future<(List<AppUser>, List<Post>)>? _results;
  Timer? _debounce;
  List<String> _recent = const [];

  /// 0 = الحسابات، 1 = المنشورات، null = اختيار تلقائي حسب وجود نتائج.
  int? _resultTab;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _search.text = q;
      _results = _searchAll(q);
      _remember(q);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _loadTrending() => PostService.trendingTags();

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_recentKey) ?? const <String>[];
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _saveRecent(List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, list);
    } catch (_) {}
  }

  void _remember(String q) {
    final text = q.trim();
    if (text.isEmpty) return;
    final list = [text, ..._recent.where((e) => e != text)]
        .take(_recentMax)
        .toList();
    if (mounted) setState(() => _recent = list);
    _saveRecent(list);
  }

  void _forget(String q) {
    final list = _recent.where((e) => e != q).toList();
    setState(() => _recent = list);
    _saveRecent(list);
  }

  void _clearRecent() {
    setState(() => _recent = const []);
    _saveRecent(const []);
  }

  /// تشغيل البحث فوراً (زر البحث أو الضغط على هاشتاق/بحث سابق).
  void _run(String q, {bool remember = false}) {
    _debounce?.cancel();
    final text = q.trim();
    if (remember) _remember(text);
    setState(() {
      _resultTab = null;
      _results = text.isEmpty ? null : _searchAll(text);
    });
  }

  /// بحث تلقائي أثناء الكتابة بعد توقّف نصف ثانية.
  void _onChanged(String q) {
    setState(() {}); // لإظهار/إخفاء زر المسح
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _run(q);
    });
  }

  void _pick(String text) {
    _search.text = text;
    _search.selection = TextSelection.collapsed(offset: text.length);
    _searchFocus.unfocus();
    _run(text, remember: true);
  }

  Future<(List<AppUser>, List<Post>)> _searchAll(String text) async {
    final users = text.startsWith('#')
        ? Future.value(<AppUser>[])
        : UserService.search(text);
    final posts = PostService.search(text);
    return (await users, await posts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (q) => _run(q, remember: true),
                      decoration: InputDecoration(
                        hintText: tr('ابحث بالاسم أو اسم المستخدم أو هاشتاق'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  _run('');
                                },
                              ),
                      ),
                      onChanged: _onChanged,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(tr('إلغاء')),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _results == null ? _trending() : _resultsView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  /// الحالة الفارغة: عمليات البحث السابقة ثم الهاشتاقات الرائجة كشرائح.
  Widget _trending() {
    return RefreshIndicator(
      onRefresh: () async {
        final refresh = _loadTrending();
        setState(() => _trendingFuture = refresh);
        await refresh;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (_recent.isNotEmpty) ...[
            _sectionTitle(
              tr('عمليات البحث السابقة'),
              trailing: TextButton(
                onPressed: _clearRecent,
                child: Text(tr('مسح الكل')),
              ),
            ),
            for (final q in _recent)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.history_rounded,
                    color: context.appColors.textDim),
                title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: context.appColors.textDim),
                  onPressed: () => _forget(q),
                ),
                onTap: () => _pick(q),
              ),
          ],
          FutureBuilder<Map<String, int>>(
            future: _trendingFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(trf('تعذر تحميل المحتوى الرائج\n{0}', [snap.error]),
                      textAlign: TextAlign.center),
                );
              }
              if (!snap.hasData) {
                return Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: AppLoading(message: tr('جارٍ استكشاف المحتوى...')),
                );
              }
              final tags = snap.data!.keys.toList();
              if (tags.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(tr('الهاشتاقات الرائجة')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: [
                      for (final tag in tags)
                        ActionChip(
                          avatar: const Icon(
                              Icons.local_fire_department_rounded,
                              size: 16),
                          label: Text(tag),
                          onPressed: () => _pick(tag),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    return FutureBuilder<(List<AppUser>, List<Post>)>(
      future: _results,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text(trf('تعذر البحث\n{0}', [snap.error]),
                  textAlign: TextAlign.center));
        }
        if (!snap.hasData) return AppLoading(message: tr('جارٍ البحث...'));
        final (users, posts) = snap.data!;
        if (users.isEmpty && posts.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: tr('لم نعثر على نتائج'),
            message: tr('جرّب اسماً أو كلمة بحث مختلفة.'),
          );
        }
        // الاختيار التلقائي: الحسابات إن وُجدت وإلا المنشورات.
        final tab = _resultTab ?? (users.isNotEmpty ? 0 : 1);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  _choiceChip(
                    context,
                    label: trf('الحسابات ({0})', [users.length]),
                    selected: tab == 0,
                    onTap: () => setState(() => _resultTab = 0),
                  ),
                  const SizedBox(width: 8),
                  _choiceChip(
                    context,
                    label: trf('المنشورات ({0})', [posts.length]),
                    selected: tab == 1,
                    onTap: () => setState(() => _resultTab = 1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tab == 0 ? _usersList(users) : _postsGrid(posts),
            ),
          ],
        );
      },
    );
  }

  Widget _usersList(List<AppUser> users) {
    if (users.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: tr('لا توجد حسابات مطابقة'),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final u in users)
          ListTile(
            onTap: () => openProfile(context, u.uid),
            leading:
                UserAvatar(uid: u.uid, fallbackName: u.username, radius: 22),
            title: Text(u.username,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: u.name.isEmpty
                ? null
                : Text(u.name,
                    style: TextStyle(color: context.appColors.textDim)),
          ),
      ],
    );
  }

  /// المنشورات كشبكة مصغّرة (بدل بطاقات كاملة تطيل الصفحة).
  Widget _postsGrid(List<Post> posts) {
    if (posts.isEmpty) {
      return EmptyState(
        icon: Icons.image_search_outlined,
        title: tr('لا توجد منشورات مطابقة'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
      itemCount: posts.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns(context),
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, i) => _postTile(context, posts[i], root: true),
    );
  }
}

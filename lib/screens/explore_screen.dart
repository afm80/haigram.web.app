import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import '../route_state.dart';

/// استكشاف: البحث ومزاياه — حقل البحث، الهاشتاقات الرائجة، وأحدث الصور.
/// عند الضغط على حقل البحث أو هاشتاق تُفتح صفحة البحث فوق الشريط السفلي.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  // قراءة واحدة (30 منشوراً) تغذّي الهاشتاقات والصور والفيديوهات معاً،
  // وتُخزَّن 5 دقائق؛ السحب للتحديث يفرض قراءة جديدة.
  late Future<List<Post>> _feed = PostService.exploreFeed();
  bool _searchOpen = false;

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
    const listPadding = EdgeInsets.only(left: 12, right: 12, bottom: 80);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              readOnly: true,
              showCursor: false,
              onTap: _openSearch,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو اسم المستخدم أو هاشتاق',
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
                  if (snap.hasError) {
                    return ListView(
                      padding: listPadding,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text('تعذر تحميل الاستكشاف\n${snap.error}',
                              textAlign: TextAlign.center),
                        ),
                      ],
                    );
                  }
                  if (!snap.hasData) {
                    return ListView(
                      padding: listPadding,
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: AppLoading(message: 'جارٍ الاستكشاف...'),
                        ),
                      ],
                    );
                  }
                  final posts = snap.data!;
                  return ListView(
                    padding: listPadding,
                    children: [
                      _tagsSection(PostService.tagsOf(posts)),
                      _photosSection([
                        for (final p in posts)
                          if (p.type == PostType.photo) p
                      ]),
                      _videosSection([
                        for (final p in posts)
                          if (p.hasVideo) p
                      ]),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );

  Widget _tagsSection(Map<String, int> tagsMap) {
    final tags = tagsMap.entries.toList();
    if (tags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('الهاشتاقات الرائجة'),
        for (var i = 0; i < tags.length; i++)
          ListTile(
            leading: CircleAvatar(
                backgroundColor: context.appColors.surfaceHigh,
                child: Text('${i + 1}')),
            title: Text(tags[i].key,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${tags[i].value} منشور',
                style: TextStyle(color: context.appColors.textDim)),
            onTap: () => _openSearch(query: tags[i].key),
          ),
      ],
    );
  }

  Widget _photosSection(List<Post> photos) {
    if (photos.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'لا توجد صور بعد',
        message: 'ستظهر هنا أحدث الصور التي يشاركها المستخدمون.',
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 5 : (width >= 600 ? 4 : 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('أحدث الصور'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: photos.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
          ),
          itemBuilder: (context, i) {
            final post = photos[i];
            return GestureDetector(
              onTap: () => Navigator.of(context).push(appRoute('post',
                  {'id': post.id}, (_) => PostDetailScreen(post: post))),
              child: ClipRect(child: PostImage(post: post)),
            );
          },
        ),
      ],
    );
  }

  /// فيديوهات يوتيوب: العادية في شبكة، والشورتز في شريط أفقي. يختفي القسم إن لم توجد.
  Widget _videosSection(List<Post> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final shorts = [for (final p in all) if (p.isShort) p];
    final videos = [for (final p in all) if (!p.isShort) p];
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (videos.isNotEmpty) ...[
          _title('أحدث الفيديوهات'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: videos.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 16 / 9,
            ),
            itemBuilder: (context, i) {
              final post = videos[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(appRoute('post',
                    {'id': post.id}, (_) => PostDetailScreen(post: post))),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: post.videoThumb!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black),
                      ),
                      const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 36),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        if (shorts.isNotEmpty)
          ShortsRow(
              shorts: shorts,
              padding: const EdgeInsets.only(top: 12, bottom: 4)),
      ],
    );
  }
}

/// صفحة البحث: تُفتح فوق الشريط السفلي وفيها الرائج ونتائج البحث.
class ExploreSearchScreen extends StatefulWidget {
  /// نص يُبحث عنه فور فتح الصفحة (مثل هاشتاق ضغطت عليه).
  final String? initialQuery;

  const ExploreSearchScreen({super.key, this.initialQuery});

  @override
  State<ExploreSearchScreen> createState() => _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends State<ExploreSearchScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late Future<Map<String, int>> _trendingFuture = _loadTrending();
  Future<(List<AppUser>, List<Post>)>? _results;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _search.text = q;
      _results = _searchAll(q);
    }
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _loadTrending() => PostService.trendingTags();

  void _run(String q) {
    final text = q.trim();
    setState(() => _results = text.isEmpty ? null : _searchAll(text));
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
                      onSubmitted: _run,
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم أو اسم المستخدم أو هاشتاق',
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
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _results == null ? _trending() : _resultsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trending() {
    return RefreshIndicator(
      onRefresh: () async {
        final refresh = _loadTrending();
        setState(() => _trendingFuture = refresh);
        await refresh;
      },
      child: FutureBuilder<Map<String, int>>(
        future: _trendingFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('تعذر تحميل المحتوى الرائج\n${snap.error}',
                    textAlign: TextAlign.center));
          }
          if (!snap.hasData)
            return const AppLoading(message: 'جارٍ استكشاف المحتوى...');
          final tags = snap.data!.entries.toList();
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (tags.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('الهاشتاقات الرائجة',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (var i = 0; i < tags.length; i++)
                  ListTile(
                    leading: CircleAvatar(
                        backgroundColor: context.appColors.surfaceHigh,
                        child: Text('${i + 1}')),
                    title: Text(tags[i].key,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${tags[i].value} منشور',
                        style: TextStyle(color: context.appColors.textDim)),
                    onTap: () {
                      _search.text = tags[i].key;
                      _searchFocus.unfocus();
                      _run(tags[i].key);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _resultsList() {
    return FutureBuilder<(List<AppUser>, List<Post>)>(
      future: _results,
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
              child: Text('تعذر البحث\n${snap.error}',
                  textAlign: TextAlign.center));
        if (!snap.hasData) return const AppLoading(message: 'جارٍ البحث...');
        final (users, posts) = snap.data!;
        if (users.isEmpty && posts.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'لم نعثر على نتائج',
            message: 'جرّب اسماً أو كلمة بحث مختلفة.',
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            if (users.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('الحسابات',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final u in users)
                ListTile(
                  onTap: () => openProfile(context, u.uid),
                  leading: UserAvatar(
                      uid: u.uid, fallbackName: u.username, radius: 22),
                  title: Text(u.username,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: u.name.isEmpty
                      ? null
                      : Text(u.name,
                          style: TextStyle(color: context.appColors.textDim)),
                ),
              Divider(color: context.appColors.text.withOpacity(0.12)),
            ],
            if (posts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('المنشورات',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final p in posts) PostCard(post: p),
            ],
          ],
        );
      },
    );
  }
}

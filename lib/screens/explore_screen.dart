import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'story_widgets.dart';
import 'video_feed_screen.dart';
import 'video_thumbnail.dart';
import '../route_state.dart';

/// استكشاف: حقل البحث ثم شريط القصص ثم المنشورات بالأحدث.
/// عند الضغط على حقل البحث تُفتح صفحة البحث فوق الشريط السفلي.
class ExploreScreen extends StatefulWidget {
  /// يُزاد من الخارج لطلب فتح البحث مباشرة (زر البحث في تبويب الفيديو).
  final ValueListenable<int>? focusRequest;

  const ExploreScreen({super.key, this.focusRequest});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final Stream<List<Post>> _feed = _latestPosts();
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    widget.focusRequest?.addListener(_onFocusRequest);
  }

  @override
  void dispose() {
    widget.focusRequest?.removeListener(_onFocusRequest);
    super.dispose();
  }

  void _onFocusRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSearch();
    });
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    _searchOpen = true;
    try {
      await rootNavigatorOf(context).push<void>(
        appRoute<void>('search', const {}, (_) => const ExploreSearchScreen()),
      );
    } finally {
      _searchOpen = false;
    }
  }

  /// الصور والنصوص في قائمة واحدة مرتبة بالأحدث (بدون فيديو).
  Stream<List<Post>> _latestPosts() {
    late final StreamController<List<Post>> controller;
    final subs = <StreamSubscription<List<Post>>>[];
    List<Post>? photos;
    List<Post>? texts;

    void emit() {
      final p = photos;
      final t = texts;
      if (p == null || t == null) return;
      controller.add([...p, ...t]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }

    controller = StreamController<List<Post>>(
      onListen: () {
        subs.add(PostService.stream(PostType.photo, limit: 15).listen((v) {
          photos = v;
          emit();
        }, onError: controller.addError));
        subs.add(PostService.stream(PostType.text, limit: 15).listen((v) {
          texts = v;
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
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
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو اسم المستخدم أو هاشتاق',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(child: _feedView()),
        ],
      ),
    );
  }

  Widget _feedView() {
    return StreamBuilder<List<Post>>(
      stream: _feed,
      builder: (context, snap) {
        final posts = snap.data;
        final hasPosts = posts != null && posts.isNotEmpty;
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: hasPosts ? posts.length + 1 : 2,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Column(children: [
                const StoriesBar(),
                Divider(
                    height: 1, color: context.appColors.text.withOpacity(0.12)),
              ]);
            }
            if (hasPosts) return PostCard(post: posts[i - 1]);
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(28),
                child: Text('تعذر تحميل المنشورات\n${snap.error}',
                    textAlign: TextAlign.center),
              );
            }
            if (posts == null) {
              return const Padding(
                padding: EdgeInsets.only(top: 60),
                child: AppLoading(message: 'جارٍ تحميل المنشورات...'),
              );
            }
            return const EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'لا توجد منشورات بعد',
              message: 'شارك أول صورة أو خاطرة مع مجتمعنا.',
            );
          },
        );
      },
    );
  }
}

/// صفحة البحث: تُفتح فوق الشريط السفلي وفيها الرائج ونتائج البحث.
class ExploreSearchScreen extends StatefulWidget {
  const ExploreSearchScreen({super.key});

  @override
  State<ExploreSearchScreen> createState() => _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends State<ExploreSearchScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late Future<(Map<String, int>, List<Post>)> _trendingFuture =
      _loadTrending();
  Future<(List<AppUser>, List<Post>)>? _results;

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<(Map<String, int>, List<Post>)> _loadTrending() async =>
      (await PostService.trendingTags(), await PostService.trendingVideos());

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
      child: FutureBuilder<(Map<String, int>, List<Post>)>(
        future: _trendingFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('تعذر تحميل المحتوى الرائج\n${snap.error}',
                    textAlign: TextAlign.center));
          }
          if (!snap.hasData)
            return const AppLoading(message: 'جارٍ استكشاف المحتوى...');
          final (tagCounts, videos) = snap.data!;
          final tags = tagCounts.entries.toList();
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('الفيديوهات الأعلى رواجاً',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (videos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'ستظهر هنا الفيديوهات الأكثر تفاعلاً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.textDim),
                  ),
                )
              else
                _videoGrid(videos),
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

  Widget _videoGrid(List<Post> videos) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 4
        : width >= 600
            ? 3
            : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: videos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, index) {
        final video = videos[index];
        return _TrendingVideoTile(
          post: video,
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
        );
      },
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
        final videos =
            posts.where((post) => post.type == PostType.video).toList();
        final otherPosts =
            posts.where((post) => post.type != PostType.video).toList();
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
            if (videos.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('الفيديوهات',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _videoGrid(videos),
              ),
            ],
            if (otherPosts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('المنشورات',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final p in otherPosts) PostCard(post: p),
            ],
          ],
        );
      },
    );
  }
}

class _TrendingVideoTile extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const _TrendingVideoTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnail(post: post),
            // تدرّج أسود أسفل الصورة ليبقى النص مقروءاً فوق الفيديو.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 44, color: Colors.white),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${post.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                  if (post.caption.isNotEmpty)
                    Text(
                      post.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.favorite_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '${post.likes}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.mode_comment_outlined,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '${post.comments}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
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

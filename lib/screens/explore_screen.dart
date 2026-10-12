import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'video_feed_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  late Future<(Map<String, int>, List<Post>)> _trendingFuture =
      _loadTrending();
  Future<(List<AppUser>, List<Post>)>? _results;

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
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: _run,
              decoration: InputDecoration(
                hintText: 'ابحث عن مستخدم أو هاشتاق',
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
          Expanded(child: _results == null ? _trending() : _resultsList()),
        ],
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
            MaterialPageRoute(
              builder: (_) => VideoViewerScreen(
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
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    AppColors.brandCyan.withOpacity(0.3),
                    const Color(0xFF171A24),
                    AppColors.brandRed.withOpacity(0.3),
                  ],
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

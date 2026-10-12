import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  Future<Map<String, int>> _tags = PostService.trendingTags();
  Future<(List<AppUser>, List<Post>)>? _results;

  void _run(String q) {
    final text = q.trim();
    setState(() => _results = text.isEmpty ? null : _searchAll(text));
  }

  Future<(List<AppUser>, List<Post>)> _searchAll(String text) async {
    final users = text.startsWith('#') ? Future.value(<AppUser>[]) : UserService.search(text);
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
      onRefresh: () async => setState(() => _tags = PostService.trendingTags()),
      child: FutureBuilder<Map<String, int>>(
        future: _tags,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('تعذر تحميل الهاشتاقات\n${snap.error}', textAlign: TextAlign.center));
          }
          if (!snap.hasData) return const AppLoading(message: 'جارٍ استكشاف المحتوى...');
          final tags = snap.data!.entries.toList();
          if (tags.isEmpty) {
            return const EmptyState(
              icon: Icons.tag_rounded,
              title: 'لا توجد هاشتاقات رائجة بعد',
              message: 'ستظهر هنا الموضوعات الأكثر تداولاً عند نشر محتوى جديد.',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('الهاشتاقات الرائجة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (var i = 0; i < tags.length; i++)
                ListTile(
                  leading: CircleAvatar(backgroundColor: AppColors.surfaceHigh, child: Text('${i + 1}')),
                  title: Text(tags[i].key, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${tags[i].value} منشور', style: const TextStyle(color: AppColors.textDim)),
                  onTap: () {
                    _search.text = tags[i].key;
                    _run(tags[i].key);
                  },
                ),
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
        if (snap.hasError) return Center(child: Text('تعذر البحث\n${snap.error}', textAlign: TextAlign.center));
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
                child: Text('الحسابات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final u in users)
                ListTile(
                  onTap: () => openProfile(context, u.uid),
                  leading: UserAvatar(uid: u.uid, fallbackName: u.username, radius: 22),
                  title: Text(u.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: u.name.isEmpty ? null : Text(u.name, style: const TextStyle(color: AppColors.textDim)),
                ),
              const Divider(color: Color(0x22FFFFFF)),
            ],
            if (posts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('المنشورات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final p in posts) PostCard(post: p),
            ],
          ],
        );
      },
    );
  }
}

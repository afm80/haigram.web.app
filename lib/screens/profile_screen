import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'post_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = PostService.uidOrEmpty;
    return DefaultTabController(
      length: 3,
      child: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _Header(uid: uid)),
            const SliverPersistentHeader(
              pinned: true,
              delegate: _TabsDelegate(
                TabBar(
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(icon: Icon(Icons.grid_on_rounded)),
                    Tab(icon: Icon(Icons.photo_library_outlined)),
                    Tab(icon: Icon(Icons.notes_rounded)),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _VideoGrid(uid: uid),
              _PhotoGrid(uid: uid),
              _TextList(uid: uid),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabsDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: AppColors.bg, child: tabBar);
  @override
  bool shouldRebuild(covariant _TabsDelegate old) => false;
}

class _Header extends StatelessWidget {
  final String uid;
  const _Header({required this.uid});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final name = PostService.username;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'تسجيل الخروج',
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ),
          CircleAvatar(
            radius: 46,
            backgroundColor: AppColors.accent,
            backgroundImage: user.photoURL != null ? CachedNetworkImageProvider(user.photoURL!) : null,
            child: user.photoURL == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700)) : null,
          ),
          const SizedBox(height: 10),
          Text('@$name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat('أتابع', PostService.countFollowing(uid)),
              _divider(),
              _stat('المتابعون', PostService.countFollowers(uid), onTap: () => _showFollowers(context, uid)),
              _divider(),
              _stat('الإعجابات', PostService.totalLikes(uid)),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => _editName(context, user),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surfaceHigh,
              side: BorderSide.none,
              minimumSize: const Size(180, 42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('تعديل الملف الشخصي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 18), color: const Color(0x33FFFFFF));

  Widget _stat(String label, Future<int> value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          FutureBuilder<int>(
            future: value,
            builder: (_, s) => Text('${s.data ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, User user) async {
    final c = TextEditingController(text: user.displayName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الاسم'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'اسم المستخدم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await user.updateDisplayName(c.text.trim());
      await user.reload();
    }
  }

  void _showFollowers(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FollowersSheet(uid: uid),
    );
  }
}

/// قائمة المتابعين: بحث داخلي وزر حالة (متابعة / أصدقاء / إلغاء).
class _FollowersSheet extends StatefulWidget {
  final String uid;
  const _FollowersSheet({required this.uid});

  @override
  State<_FollowersSheet> createState() => _FollowersSheetState();
}

class _FollowersSheetState extends State<_FollowersSheet> {
  String _q = '';
  late final Future<Map<String, String>> _names = PostService.followerNames(widget.uid);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text('المتابعون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(hintText: 'بحث', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, String>>(
              future: _names,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final entries = snap.data!.entries.where((e) => e.value.toLowerCase().contains(_q)).toList();
                if (entries.isEmpty) return const Center(child: Text('لا يوجد متابعون'));
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _FollowerTile(uid: entries[i].key, name: entries[i].value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowerTile extends StatelessWidget {
  final String uid;
  final String name;
  const _FollowerTile({required this.uid, required this.name});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: AppColors.accent, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
      title: Text(name),
      trailing: StreamBuilder<bool>(
        stream: PostService.isFollowing(uid),
        builder: (context, s) {
          final following = s.data ?? false;
          // متابعة متبادلة = أصدقاء، لأن هذا الشخص يتابعني أصلاً (هو في قائمة متابعيني).
          return FilledButton(
            onPressed: () => PostService.toggleFollow(uid, following),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 36),
              backgroundColor: following ? AppColors.surfaceHigh : AppColors.accent,
            ),
            child: Text(following ? 'أصدقاء' : 'متابعة'),
          );
        },
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final String uid;
  const _VideoGrid({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.video, uid: uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لم تنشر فيديوهات بعد'));
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 9 / 14),
          itemCount: list.length,
          itemBuilder: (_, i) => Container(
            color: AppColors.surfaceHigh,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_outlined, size: 18),
                Text('${list[i].views}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final String uid;
  const _PhotoGrid({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.photo, uid: uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا توجد صور بعد'));
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: list.length,
          itemBuilder: (_, i) => PostImage(post: list[i], height: 140),
        );
      },
    );
  }
}

class _TextList extends StatelessWidget {
  final String uid;
  const _TextList({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Post>>(
      stream: PostService.stream(PostType.text, uid: uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا توجد منشورات نصية بعد'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (_, i) => PostCard(post: list[i]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme.dart';
import 'explore_screen.dart';
import 'posts_feed_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import 'video_feed_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openCreateMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textDim, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            _createTile(ctx, Icons.videocam_rounded, 'فيديو (حتى دقيقة)', UploadKind.video),
            _createTile(ctx, Icons.photo_library_rounded, 'ألبوم صور', UploadKind.photo),
            _createTile(ctx, Icons.edit_note_rounded, 'منشور نصي', UploadKind.text),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _createTile(BuildContext ctx, IconData icon, String title, UploadKind kind) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title),
      onTap: () {
        Navigator.pop(ctx);
        Navigator.push(context, MaterialPageRoute(builder: (_) => UploadScreen(kind: kind)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      VideoFeedScreen(active: _index == 0),
      const ExploreScreen(),
      const SizedBox.shrink(),
      const PostsFeedScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _index == 0 ? Colors.black.withOpacity(0.55) : AppColors.bg,
          border: const Border(top: BorderSide(color: Color(0x22FFFFFF))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _navItem(0, Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
                _navItem(1, Icons.search_rounded, Icons.search_rounded, 'استكشف'),
                Expanded(child: Center(child: _createButton())),
                _navItem(3, Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded, 'المنشورات'),
                _navItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, IconData activeIcon, String label) {
    final selected = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: selected ? Colors.white : AppColors.textDim, size: 26),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: selected ? Colors.white : AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _createButton() {
    return GestureDetector(
      onTap: _openCreateMenu,
      child: Container(
        width: 50,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accent2]),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'create_flow.dart';
import 'explore_screen.dart';
import 'posts_feed_screen.dart';
import 'profile_screen.dart';
import 'video_feed_screen.dart';

/// الغلاف الرئيسي: يجهّز ملف المستخدم أولاً ثم يعرض التبويبات.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Future<AppUser> _profile = UserService.ensureProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser>(
      future: _profile,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر تحميل ملفك الشخصي\n${snap.error}', textAlign: TextAlign.center))));
        }
        if (!snap.hasData) return const Scaffold(body: AppLoading(message: 'جارٍ إعداد حسابك...'));
        return const _Tabs();
      },
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // حذف قصصي المنتهية (أقدم من 24 ساعة) لتوفير الحصة المجانية.
    PostService.cleanupMyExpiredStories().catchError((_) {});
    // رابط ملف شخصي: https://موقعك/?u=username
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLinkedProfile());
  }

  Future<void> _openLinkedProfile() async {
    final u = Uri.base.queryParameters['u'];
    if (u == null || u.isEmpty) return;
    final user = await UserService.byUsername(u);
    if (user != null && mounted) openProfile(context, user.uid);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      VideoFeedScreen(active: _index == 0, onSearch: () => setState(() => _index = 1)),
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
          gradient: LinearGradient(
            colors: [
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(_index == 0 ? 0.45 : 0.75)
                  : context.appColors.bg.withOpacity(0.65),
              context.appColors.bg.withOpacity(0.92),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(top: BorderSide(color: context.appColors.text.withOpacity(0.08), width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
            child: SizedBox(
              height: 66,
              child: Row(
                children: [
                  _navItem(0, Icons.videocam_rounded, Icons.videocam_rounded, 'ريلز'),
                  _navItem(1, Icons.search_rounded, Icons.search_rounded, 'استكشف'),
                  Expanded(child: Center(child: _createButton())),
                  _navItem(3, Icons.home_rounded, Icons.home_rounded, 'المنشورات'),
                  _navItem(4, Icons.person_rounded, Icons.person_rounded, 'حسابي'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, IconData activeIcon, String label) {
    final selected = _index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _index = i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: selected
              ? BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon,               color: selected ? Theme.of(context).colorScheme.primary : context.appColors.textDim, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Theme.of(context).colorScheme.primary : context.appColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createButton() {
    return GestureDetector(
      onTap: () => showCreateSheet(context),
      child: Container(
        width: 54,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [AppColors.accent, AppColors.accent2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x55A855F7), blurRadius: 16, offset: Offset(0, 8)),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

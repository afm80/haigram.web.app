import 'dart:async';

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'create_flow.dart';
import 'explore_screen.dart';
import 'social_screens.dart';
import 'posts_feed_screen.dart';
import 'post_widgets.dart' show PostDetailScreen;
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
          return Scaffold(
              body: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('تعذر تحميل ملفك الشخصي\n${snap.error}',
                          textAlign: TextAlign.center))));
        }
        if (!snap.hasData)
          return const Scaffold(
              body: AppLoading(message: 'جارٍ إعداد حسابك...'));
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

class _TabsState extends State<_Tabs> with WidgetsBindingObserver {
  int _index = 0;
  bool _appVisible = true;
  Timer? _presenceHeartbeat;
  final _selectedTab = ValueNotifier<int>(0);
  final _tabNavigators =
      List.generate(7, (_) => GlobalKey<NavigatorState>());
  late final Stream<int> _unreadNotificationCount =
      SocialService.unreadNotificationCount();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updatePresence(true);
    _presenceHeartbeat = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updatePresence(_appVisible),
    );
    // حذف قصصي المنتهية (أقدم من 24 ساعة) لتوفير الحصة المجانية.
    PostService.cleanupMyExpiredStories().catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _openDeepLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    _updatePresence(false);
    _selectedTab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _updatePresence(_appVisible);
  }

  Future<void> _updatePresence(bool online) async {
    try {
      await PresenceService.setOnline(online);
    } catch (error, stackTrace) {
      debugPrint('Unable to update user presence: $error\n$stackTrace');
    }
  }

  Future<void> _openDeepLink() async {
    final u = Uri.base.queryParameters['u'];
    if (u != null && u.isNotEmpty) {
      final user = await UserService.byUsername(u);
      if (!mounted || user == null) return;
      _tabNavigators[0].currentState?.push<void>(
        MaterialPageRoute(builder: (_) => UserProfileScreen(uid: user.uid)),
      );
      return;
    }
    final postId = Uri.base.queryParameters['p'];
    if (postId != null && postId.isNotEmpty) {
      final post = await PostService.postById(postId);
      if (!mounted || post == null) return;
      _tabNavigators[0].currentState?.push<void>(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
      );
      return;
    }
    final videoId = Uri.base.queryParameters['v'];
    if (videoId == null || videoId.isEmpty) return;
    final post = await PostService.postById(videoId);
    if (!mounted || post == null || post.type != PostType.video) return;
    _tabNavigators[0].currentState?.push<void>(
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(posts: [post], initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navForeground = isDark ? Colors.white : Colors.black;
    final navInactive = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: List.generate(
          _tabNavigators.length,
          (tab) => Navigator(
            key: _tabNavigators[tab],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder<int>(
                valueListenable: _selectedTab,
                builder: (context, selectedTab, _) =>
                    _tabPage(tab, selectedTab),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _navItem(
                    0, Icons.home_outlined, Icons.home_rounded, 'الرئيسية',
                    foreground: navForeground, inactive: navInactive),
                _navItem(
                    1, Icons.search_rounded, Icons.search_rounded, 'استكشف',
                    foreground: navForeground, inactive: navInactive),
                _navItem(2, Icons.dynamic_feed_outlined,
                    Icons.dynamic_feed_rounded, 'المنشورات',
                    foreground: navForeground, inactive: navInactive),
                Expanded(child: Center(child: _createButton())),
                _navItem(4, Icons.mail_outline_rounded, Icons.mail_rounded,
                    'الرسائل',
                    foreground: navForeground, inactive: navInactive),
                StreamBuilder<int>(
                  stream: _unreadNotificationCount,
                  builder: (context, snapshot) => _navItem(
                    5,
                    Icons.favorite_border_rounded,
                    Icons.favorite_rounded,
                    'التنبيهات',
                    foreground: navForeground,
                    inactive: navInactive,
                    badgeCount: snapshot.hasError ? -1 : (snapshot.data ?? 0),
                  ),
                ),
                _navItem(6, Icons.person_outline_rounded, Icons.person_rounded,
                    'حسابي',
                    foreground: navForeground, inactive: navInactive),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabPage(int tab, int selectedTab) => switch (tab) {
        0 => VideoFeedScreen(
            active: selectedTab == 0,
            onSearch: () => _selectTab(1),
          ),
        1 => const ExploreScreen(),
        2 => const PostsFeedScreen(),
        3 => const SizedBox.shrink(),
        4 => const InboxScreen(),
        5 => const NotificationsScreen(),
        6 => const ProfileScreen(),
        _ => const SizedBox.shrink(),
      };

  void _selectTab(int tab) {
    setState(() => _index = tab);
    _selectedTab.value = tab;
  }

  Widget _navItem(
    int i,
    IconData icon,
    IconData activeIcon,
    String label, {
    required Color foreground,
    required Color inactive,
    int badgeCount = 0,
  }) {
    final selected = _index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTab(i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? activeIcon : icon,
                      color: selected ? foreground : inactive, size: 23),
                  if (badgeCount != 0)
                    Positioned(
                      top: -5,
                      right: -8,
                      child: Tooltip(
                        message: badgeCount < 0
                            ? 'تعذر تحميل عدد الإشعارات'
                            : '$badgeCount إشعار غير مقروء',
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 15, minHeight: 15),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: badgeCount < 0
                              ? const SizedBox(width: 5, height: 5)
                              : Text(
                                  badgeCount > 99 ? '99+' : '$badgeCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? foreground : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createButton() {
    return GestureDetector(
      onTap: () => showCreateSheet(
          _tabNavigators[_index].currentContext ?? context),
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
            BoxShadow(
                color: Color(0x5542D4F4), blurRadius: 16, offset: Offset(0, 8)),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

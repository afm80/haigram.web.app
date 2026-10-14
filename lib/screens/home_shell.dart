import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../route_state.dart';
import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'create_flow.dart';
import 'explore_screen.dart';
import 'social_screens.dart';
import 'post_widgets.dart' show PostDetailScreen;
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'video_feed_screen.dart';

/// الغلاف الرئيسي: يجهّز ملف المستخدم أولاً ثم يعرض التبويبات.
class HomeShell extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const HomeShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

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
        return _Tabs(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );
      },
    );
  }
}

class _Tabs extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  const _Tabs({
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with WidgetsBindingObserver {
  int _index = 0;
  bool _appVisible = true;
  DateTime? _lastBackPress;
  // بعد أول ضغطة رجوع على الرئيسية نسمح بالخروج الفعلي لمدة ثانيتين.
  bool _exitArmed = false;
  Timer? _exitTimer;
  // التبويبات التي زرتها قبل الحالي (الأحدث في النهاية) ليعيدك الرجوع إليها.
  final List<int> _tabHistory = [];
  Timer? _presenceHeartbeat;
  final _selectedTab = ValueNotifier<int>(0);
  final _tabNavigators =
      List.generate(5, (_) => GlobalKey<NavigatorState>());
  // يحفظ الصفحات المفتوحة في كل تبويب لاستعادتها بعد تحديث المتصفح.
  final _routeObservers = List.generate(5, (tab) => TabRouteObserver(tab));
  // يُزاد لطلب فتح حقل البحث في تبويب الاستكشاف.
  final _searchRequest = ValueNotifier<int>(0);
  // يُزاد عند النقر على «الرئيسية» وأنت فيها لتحديث الفيديوهات.
  final _homeRefresh = ValueNotifier<int>(0);
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restoreOrOpenDeepLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    _exitTimer?.cancel();
    _updatePresence(false);
    _selectedTab.dispose();
    _searchRequest.dispose();
    _homeRefresh.dispose();
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

  /// بعد تحديث الصفحة: يعيد التبويب والصفحات المفتوحة كما كانت.
  /// وإن لم توجد حالة محفوظة يفتح رابط المشاركة (إن وُجد).
  Future<void> _restoreOrOpenDeepLink() async {
    final saved = await RouteStore.loadSaved();
    if (!mounted) return;
    if (saved != null) {
      await _restore(saved);
      return;
    }
    await _openDeepLink();
  }

  Future<void> _restore(SavedNavState saved) async {
    final tab = (saved.tab >= 0 && saved.tab < _tabNavigators.length)
        ? saved.tab
        : 0;
    RouteStore.setTab(tab, persist: false);
    setState(() => _index = tab);
    _selectedTab.value = tab;
    for (var t = 0; t < _tabNavigators.length; t++) {
      for (final item in saved.stacks[t] ?? const <SavedRoute>[]) {
        Route<void>? route;
        try {
          route = await _routeFor(item);
        } catch (error) {
          debugPrint('Unable to restore page ${item.name}: $error');
        }
        if (!mounted) return;
        if (route != null) _tabNavigators[t].currentState?.push<void>(route);
      }
    }
    // الصفحات المفتوحة فوق الشريط السفلي (محادثة، إشعارات، تعديل الملف...).
    for (final item in saved.stacks[rootStackIndex] ?? const <SavedRoute>[]) {
      Route<void>? route;
      try {
        route = await _routeFor(item);
      } catch (error) {
        debugPrint('Unable to restore page ${item.name}: $error');
      }
      if (!mounted) return;
      if (route != null) rootNavigatorOf(context).push<void>(route);
    }
  }

  /// يبني الصفحة من وصفها المحفوظ (أو null إذا لم تعد متاحة).
  Future<Route<void>?> _routeFor(SavedRoute item) async {
    final args = item.args;
    switch (item.name) {
      case 'user':
        final uid = args['uid'] as String? ?? '';
        if (uid.isEmpty) return null;
        return appRoute<void>(
            'user', {'uid': uid}, (_) => UserProfileScreen(uid: uid));
      case 'post':
        final id = args['id'] as String? ?? '';
        final post = id.isEmpty ? null : await PostService.postById(id);
        if (post == null) return null;
        return appRoute<void>(
            'post', {'id': post.id}, (_) => PostDetailScreen(post: post));
      case 'video':
        final id = args['id'] as String? ?? '';
        final post = id.isEmpty ? null : await PostService.postById(id);
        if (post == null || post.type != PostType.video) return null;
        return appRoute<void>(
          'video',
          {'id': post.id},
          (_) => VideoViewerScreen(posts: [post], initialIndex: 0),
        );
      case 'sound':
        final id = args['id'] as String? ?? '';
        final sound = id.isEmpty ? null : await PostService.postById(id);
        if (sound == null || sound.type != PostType.video) return null;
        return appRoute<void>(
            'sound', {'id': sound.id}, (_) => SoundScreen(sound: sound));
      case 'chat':
        final cid = args['cid'] as String? ?? '';
        final uid = args['uid'] as String? ?? '';
        if (cid.isEmpty || uid.isEmpty) return null;
        return appRoute<void>(
          'chat',
          {'cid': cid, 'uid': uid},
          (_) => ChatScreen(conversationId: cid, otherUid: uid),
        );
      case 'notifications':
        final type = args['type'] as String?;
        final title = args['title'] as String?;
        return appRoute<void>(
          'notifications',
          {'type': type, 'title': title},
          (_) => NotificationsScreen(type: type, title: title),
        );
      case 'search':
        return appRoute<void>(
            'search', const {}, (_) => const ExploreSearchScreen());
      case 'editProfile':
        return appRoute<void>(
            'editProfile', const {}, (_) => const EditProfileScreen());
      case 'settings':
        return appRoute<void>(
          'settings',
          const {},
          (_) => SettingsScreen(
              onThemeModeChanged: widget.onThemeModeChanged),
        );
    }
    return null;
  }

  Future<void> _openDeepLink() async {
    final u = Uri.base.queryParameters['u'];
    if (u != null && u.isNotEmpty) {
      final user = await UserService.byUsername(u);
      if (!mounted || user == null) return;
      _tabNavigators[0].currentState?.push<void>(
        appRoute<void>('user', {'uid': user.uid},
            (_) => UserProfileScreen(uid: user.uid)),
      );
      return;
    }
    final postId = Uri.base.queryParameters['p'];
    if (postId != null && postId.isNotEmpty) {
      final post = await PostService.postById(postId);
      if (!mounted || post == null) return;
      _tabNavigators[0].currentState?.push<void>(
        appRoute<void>('post', {'id': post.id},
            (_) => PostDetailScreen(post: post)),
      );
      return;
    }
    final videoId = Uri.base.queryParameters['v'];
    if (videoId == null || videoId.isEmpty) return;
    final post = await PostService.postById(videoId);
    if (!mounted || post == null || post.type != PostType.video) return;
    _tabNavigators[0].currentState?.push<void>(
      appRoute<void>(
        'video',
        {'id': post.id},
        (_) => VideoViewerScreen(posts: [post], initialIndex: 0),
      ),
    );
  }

  /// زر الرجوع (أندرويد/المتصفح): يغلق الصفحة المفتوحة فوق التبويب أولاً،
  /// ثم يعود للرئيسية، ثم يطلب ضغطة ثانية للخروج.
  void _handleBack() {
    if (!mounted) return;
    final navigator = _tabNavigators[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    // الرجوع من تبويب: يعيدك إلى التبويب الذي جئت منه، وإلا إلى الرئيسية.
    if (_tabHistory.isNotEmpty) {
      _selectTab(_tabHistory.removeLast(), fromBack: true);
      return;
    }
    if (_index != 0) {
      _selectTab(0, fromBack: true);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      setState(() => _exitArmed = true);
      _exitTimer?.cancel();
      _exitTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _exitArmed = false);
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('اضغط مرة أخرى للخروج'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    _exitTimer?.cancel();
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final videoTabSelected = _index == 0;
    final navForeground =
        videoTabSelected || isDark ? Colors.white : Colors.black;
    final navInactive =
        videoTabSelected || isDark ? Colors.white70 : Colors.black54;

    return PopScope(
      // الضغطة الثانية خلال ثانيتين تمرّ للنظام فيُغلق التطبيق فعلاً.
      canPop: _exitArmed,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: List.generate(
          _tabNavigators.length,
          (tab) => Navigator(
            key: _tabNavigators[tab],
            observers: [_routeObservers[tab]],
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
                _navItem(1, Icons.explore_outlined, Icons.explore_rounded,
                    'استكشف',
                    foreground: navForeground, inactive: navInactive),
                Expanded(child: Center(child: _createButton())),
                StreamBuilder<int>(
                  stream: _unreadNotificationCount,
                  builder: (context, snapshot) => _navItem(
                    3,
                    Icons.chat_bubble_outline_rounded,
                    Icons.chat_bubble_rounded,
                    'صندوق البريد',
                    foreground: navForeground,
                    inactive: navInactive,
                    badgeCount: snapshot.hasError ? -1 : (snapshot.data ?? 0),
                  ),
                ),
                _navItem(4, Icons.person_outline_rounded, Icons.person_rounded,
                    'الملف الشخصي',
                    foreground: navForeground, inactive: navInactive),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Widget _tabPage(int tab, int selectedTab) => switch (tab) {
        0 => VideoFeedScreen(
            active: selectedTab == 0,
            refreshRequest: _homeRefresh,
            onSearch: () {
              _selectTab(1);
              _searchRequest.value++;
            },
          ),
        1 => ExploreScreen(focusRequest: _searchRequest),
        2 => const SizedBox.shrink(),
        3 => const InboxScreen(),
        4 => ProfileScreen(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        _ => const SizedBox.shrink(),
      };

  void _selectTab(int tab, {bool fromBack = false}) {
    if (!fromBack) {
      // النقر على «الرئيسية» وأنت في صفحتها الرئيسية: تحديث الفيديوهات.
      if (tab == 0 &&
          _index == 0 &&
          !(_tabNavigators[0].currentState?.canPop() ?? false)) {
        _homeRefresh.value++;
      }
      // كل ضغطة على تبويب تفتح صفحته الرئيسية: نُغلق أي صفحات فرعية
      // (ملف مستخدم آخر، منشور...) بقيت مفتوحة داخل التبويب سابقاً.
      final navigator = _tabNavigators[tab].currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
      if (tab != _index) {
        _tabHistory
          ..remove(tab)
          ..remove(_index)
          ..add(_index);
        if (_tabHistory.length > 10) _tabHistory.removeAt(0);
      }
    }
    setState(() => _index = tab);
    _selectedTab.value = tab;
    RouteStore.setTab(tab);
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
    // زر الإضافة بأسلوب تيك توك: طبقة سماوية يساراً وحمراء يميناً
    // ومستطيل أبيض في الوسط (أسود في الوضع الفاتح) وعليه علامة +.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final centerColor = isDark ? Colors.white : Colors.black;
    final plusColor = isDark ? Colors.black : Colors.white;
    Widget layer(Color color) => Container(
          width: 42,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        );
    return GestureDetector(
      onTap: () => showCreateSheet(
          _tabNavigators[_index].currentContext ?? context),
      child: SizedBox(
        width: 50,
        height: 34,
        child: Stack(
          children: [
            Positioned(left: 0, child: layer(const Color(0xFF25F4EE))),
            Positioned(right: 0, child: layer(const Color(0xFFFE2C55))),
            Positioned(
              left: 4,
              child: Container(
                width: 42,
                height: 34,
                decoration: BoxDecoration(
                  color: centerColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.add_rounded, color: plusColor, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

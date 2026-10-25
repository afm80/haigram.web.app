import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:firebase_messaging/firebase_messaging.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import '../net_error.dart';
import '../route_state.dart';
import '../share_links.dart';
import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'create_flow.dart';
import 'common_widgets.dart' show UserAvatar;
import 'explore_screen.dart';
import 'home_feed_screen.dart';
import 'story_privacy_screen.dart';
import 'social_screens.dart';
import 'post_widgets.dart' show PostDetailScreen, stopInlineVideos;
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'sound_screen.dart';

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
  late Future<AppUser> _profile = UserService.ensureProfile();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _blockedAccountSub;
  bool _blockedSignOutStarted = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _blockedAccountSub = FirebaseFirestore.instance
        .collection('blockedUsers')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || _blockedSignOutStarted) return;
      _blockedSignOutStarted = true;
      RouteStore.clear();
      UserService.me = null;
      SocialService.unregisterPushNotifications()
          .catchError((Object _) {})
          .whenComplete(() {
        FirebaseAuth.instance.signOut().catchError((Object error) {
          debugPrint('Unable to sign out blocked account: $error');
        });
      });
    });
  }

  @override
  void dispose() {
    _blockedAccountSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // الزائر: لا ملف شخصي يُجهَّز، نعرض التبويبات مباشرة للتصفح فقط.
    if (!isLoggedIn) {
      return _Tabs(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      );
    }
    return FutureBuilder<AppUser>(
      future: _profile,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
              body: ErrorState(
                  error: snap.error,
                  title: tr('تعذر تحميل ملفك الشخصي'),
                  onRetry: () =>
                      setState(() => _profile = UserService.ensureProfile())));
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: HaigramLogo(size: 96)));
        }
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
  StreamSubscription<RemoteMessage>? _pushOpenedSub;
  final _selectedTab = ValueNotifier<int>(0);
  final _tabNavigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  // يحفظ الصفحات المفتوحة في كل تبويب لاستعادتها بعد تحديث المتصفح.
  final _routeObservers = List.generate(5, (tab) => TabRouteObserver(tab));
  // يلغي نافذة «اضغط مرة أخرى للخروج» عند فتح أي صفحة داخل تبويب.
  late final _pushObservers =
      List.generate(5, (_) => _PushObserver(_disarmExit));
  // عدد الصفحات المفتوحة في كل تبويب (الصفحة الأولى = الرئيسية للتبويب).
  // عند فتح صفحة داخل التبويب (محادثة، منشور...) يختفي الشريط السفلي كإنستغرام.
  final _depths = List<int>.filled(5, 0);
  late final _depthObservers = List.generate(
    5,
    (tab) => _DepthObserver((delta) {
      final next = _depths[tab] + delta;
      _depths[tab] = next < 0 ? 0 : next;
      _refreshDeep();
    }),
  );
  bool _deep = false;

  void _refreshDeep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deep = _depths[_index] > 1;
      if (deep != _deep) setState(() => _deep = deep);
    });
  }

  bool get _guest => !isLoggedIn;
  // broadcast: القائمة السفلية في الغلاف وفي عارض الشورتز تستمعان معاً.
  late final Stream<AppUser?> _currentProfile = (_guest
          ? Stream<AppUser?>.value(null)
          : UserService.profileStream(UserService.me?.uid ?? ''))
      .asBroadcastStream();
  // شارة تبويب الرسائل: عدد المحادثات غير المقروءة (كإنستغرام)، لا الإشعارات.
  late final Stream<int> _unreadChatCount = (_guest
          ? Stream<int>.value(0)
          : SocialService.unreadChatCount())
      .asBroadcastStream();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShellNavBridge.shortsBar = _shortsNavBar;
    // الزائر: لا إشعارات دفع ولا حالة اتصال ولا تنظيف قصص (لا قراءات ولا كتابات).
    if (!_guest) {
      _pushOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _openChatFromPush,
      );
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openChatFromPush(message);
        });
      }).catchError((Object _) {});
      // تسجيل الجهاز لإشعارات الدفع فور الدخول (رسائل، إعجابات، تعليقات، متابعات).
      SocialService.registerChatPushNotifications().catchError((_) {});
      _updatePresence(true);
      _presenceHeartbeat = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _updatePresence(_appVisible),
      );
      // حذف قصصي المنتهية (أقدم من 24 ساعة) لتوفير الحصة المجانية.
      PostService.cleanupMyExpiredStories().catchError((_) {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreOrOpenDeepLink();
      _listenAppLinks();
    });
  }

  StreamSubscription<Uri>? _linkSub;

  /// أندرويد: فتح روابط haigram.web.app/p/ID و/@username داخل التطبيق.
  Future<void> _listenAppLinks() async {
    if (kIsWeb || !mounted) return;
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null && mounted) await _openDeepLink(initial);
      _linkSub = links.uriLinkStream.listen(
        (uri) {
          if (mounted) _openDeepLink(uri);
        },
        onError: (Object _) {},
      );
    } catch (error) {
      debugPrint('App links unavailable: $error');
    }
  }

  @override
  void dispose() {
    if (ShellNavBridge.shortsBar == _shortsNavBar) {
      ShellNavBridge.shortsBar = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    _pushOpenedSub?.cancel();
    _linkSub?.cancel();
    _exitTimer?.cancel();
    _updatePresence(false);
    _selectedTab.dispose();
    super.dispose();
  }

  void _disarmExit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_exitArmed) return;
      _exitTimer?.cancel();
      _lastBackPress = null;
      setState(() => _exitArmed = false);
    });
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
    final tab =
        (saved.tab >= 0 && saved.tab < _tabNavigators.length) ? saved.tab : 0;
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
      case 'activity':
        return appRoute<void>(
            'activity', const {}, (_) => const ActivityScreen());
      case 'profileVisits':
        return appRoute<void>(
            'profileVisits', const {}, (_) => const ProfileVisitsScreen());
      case 'blockedUsers':
        return appRoute<void>(
            'blockedUsers', const {}, (_) => const BlockedUsersScreen());
      case 'storyPrivacy':
        return appRoute<void>(
            'storyPrivacy', const {}, (_) => const StoryPrivacyScreen());
      case 'savedPosts':
        return appRoute<void>(
            'savedPosts', const {}, (_) => const SavedPostsScreen());
      case 'savedSounds':
        return appRoute<void>(
            'savedSounds', const {}, (_) => const SavedSoundsScreen());
      case 'sound':
        final sound = PostSound.fromMap(args);
        if (sound == null) return null;
        return appRoute<void>(
            'sound', sound.toMap(), (_) => SoundScreen(sound: sound));
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
          (_) => SettingsScreen(onThemeModeChanged: widget.onThemeModeChanged),
        );
    }
    return null;
  }

  Future<void> _openDeepLink([Uri? link]) async {
    final uri = link ?? Uri.base;
    if (link != null && _index != 0) {
      setState(() => _index = 0);
      _selectedTab.value = 0;
    }
    final chatId = uri.queryParameters['chat'];
    final senderUid = uri.queryParameters['from'];
    if (chatId != null &&
        chatId.isNotEmpty &&
        senderUid != null &&
        senderUid.isNotEmpty) {
      _pushChatRoute(chatId, senderUid);
      return;
    }
    final u = usernameFromUri(uri);
    if (u != null && u.isNotEmpty) {
      final user = await UserService.byUsername(u);
      if (!mounted || user == null) return;
      _tabNavigators[0].currentState?.push<void>(
            appRoute<void>('user', {'uid': user.uid},
                (_) => UserProfileScreen(uid: user.uid)),
          );
      return;
    }
    final postId = postIdFromUri(uri);
    if (postId != null && postId.isNotEmpty) {
      final post = await PostService.postById(postId);
      if (!mounted || post == null) return;
      _tabNavigators[0].currentState?.push<void>(
            appRoute<void>(
                'post', {'id': post.id}, (_) => PostDetailScreen(post: post)),
          );
      return;
    }
  }

  void _openChatFromPush(RemoteMessage message) {
    final chatId = message.data['conversationId'];
    final senderUid = message.data['senderUid'];
    final type = message.data['type'];
    // إشعارات النشاط مثل إنستغرام: إعجاب/تعليق يفتح المنشور، ومتابعة تفتح ملف الشخص.
    if (type is String && type != 'chat' && chatId == null) {
      _openActivityFromPush(type, message.data);
      return;
    }
    if (chatId is String &&
        chatId.isNotEmpty &&
        senderUid is String &&
        senderUid.isNotEmpty) {
      _pushChatRoute(chatId, senderUid);
    }
  }

  Future<void> _openActivityFromPush(
      String type, Map<String, dynamic> data) async {
    if (needsLogin(context)) return;
    final navigator = _tabNavigators[0].currentState;
    try {
      if (type == 'like' || type == 'comment') {
        final postId = data['postId'];
        if (postId is! String || postId.isEmpty) return;
        final post = await PostService.postById(postId);
        if (!mounted || post == null) return;
        navigator?.push<void>(appRoute<void>(
            'post', {'id': post.id}, (_) => PostDetailScreen(post: post)));
      } else {
        final uid = data['actorUid'];
        if (uid is! String || uid.isEmpty) return;
        navigator?.push<void>(appRoute<void>(
            'user', {'uid': uid}, (_) => UserProfileScreen(uid: uid)));
      }
    } catch (error) {
      debugPrint('Unable to open push target: $error');
    }
  }

  void _pushChatRoute(String chatId, String otherUid) {
    if (needsLogin(context)) return;
    _tabNavigators[0].currentState?.push<void>(
          appRoute<void>(
            'chat',
            {'cid': chatId, 'uid': otherUid},
            (_) => ChatScreen(conversationId: chatId, otherUid: otherUid),
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
      // رسالة صغيرة عائمة بأسلوب إنستغرام.
      messenger.showSnackBar(SnackBar(
        content: Text(
          tr('اضغط مرة أخرى للخروج'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 190,
        backgroundColor: Colors.black87,
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ));
      return;
    }
    _exitTimer?.cancel();
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navForeground = isDark ? Colors.white : Colors.black;
    final navInactive = isDark ? Colors.white70 : Colors.black54;

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
                observers: [
                  _routeObservers[tab],
                  _pushObservers[tab],
                  _depthObservers[tab],
                ],
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
          bottomNavigationBar: _deep
              ? null
              : _navBar(
                  foreground: navForeground,
                  inactive: navInactive,
                  dark: isDark,
                  select: _selectTab,
                ),
        ));
  }

  /// القائمة السفلية. [dark] = خلفية داكنة (الشورتز)، و[select] ما يحدث عند
  /// الضغط على تبويب.
  Widget _navBar({
    required Color foreground,
    required Color inactive,
    required bool dark,
    required void Function(int tab) select,
    VoidCallback? onCreate,
  }) {
    final bar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _navItem(0, Icons.home_outlined, Icons.home_rounded,
                  tr('الرئيسية'),
                  foreground: foreground, inactive: inactive, select: select),
              _navItem(1, Icons.explore_outlined, Icons.explore_rounded,
                  tr('استكشف'),
                  foreground: foreground, inactive: inactive, select: select),
              Expanded(
                  child: Center(
                      child: _createButton(dark: dark, onCreate: onCreate))),
              StreamBuilder<int>(
                stream: _unreadChatCount,
                builder: (context, snapshot) => _navItem(
                  3,
                  Icons.chat_bubble_outline_rounded,
                  Icons.chat_bubble_rounded,
                  tr('الرسائل'),
                  foreground: foreground,
                  inactive: inactive,
                  select: select,
                  badgeCount: snapshot.hasError ? -1 : (snapshot.data ?? 0),
                ),
              ),
              StreamBuilder<AppUser?>(
                stream: _currentProfile,
                builder: (context, snapshot) {
                  final profile = snapshot.data ?? UserService.me;
                  return _navItem(
                    4,
                    Icons.person_outline_rounded,
                    Icons.person_rounded,
                    tr('الملف الشخصي'),
                    foreground: foreground,
                    inactive: inactive,
                    select: select,
                    showLabel: _guest,
                    // صورة الملف الشخصي بحجم التبويب كامل (مثل انستغرام)
                    iconBuilder: _guest
                        ? null
                        : (selected) => Container(
                              width: 40,
                              height: 40,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? foreground
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: UserAvatar(
                                uid: profile?.uid ?? '',
                                fallbackName: profile?.username ?? '',
                                profile: profile,
                                radius: 16.5,
                              ),
                            ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!dark) return bar;
    // الشورتز: خلفية سوداء مثل تيك توك.
    return ColoredBox(color: Colors.black, child: bar);
  }

  /// القائمة السفلية داخل عارض الشورتز (يطلبها العارض عبر [ShellNavBridge]).
  /// الضغط على تبويب يغلق العارض وأي صفحات فوق الغلاف ثم ينتقل للتبويب.
  Widget _shortsNavBar(BuildContext viewerContext) {
    void leaveRoot() {
      Navigator.of(viewerContext, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    }

    return _navBar(
      foreground: Colors.white,
      inactive: Colors.white70,
      dark: true,
      select: (tab) {
        leaveRoot();
        if (!mounted) return;
        _selectTab(tab);
      },
      onCreate: () {
        if (needsLogin(viewerContext)) return;
        leaveRoot();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showCreateSheet(_tabNavigators[_index].currentContext ?? context);
        });
      },
    );
  }

  Widget _tabPage(int tab, int selectedTab) => switch (tab) {
        0 => const HomeFeedScreen(),
        1 => const ExploreScreen(),
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
      // كل ضغطة على تبويب تفتح صفحته الرئيسية: نُغلق أي صفحات فرعية
      // (ملف مستخدم آخر، منشور...) بقيت مفتوحة داخل التبويب سابقاً.
      final navigator = _tabNavigators[tab].currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
      if (tab == 0 && _index == 0) {
        // ضغط على الرئيسية وأنت فيها: تمرير للأعلى وتحديث.
        homeRefreshTick.value++;
      }
      if (tab != _index) {
        _tabHistory
          ..remove(tab)
          ..remove(_index)
          ..add(_index);
        if (_tabHistory.length > 10) _tabHistory.removeAt(0);
      }
    }
    // التبويبات تبقى حيّة خلف IndexedStack، فنوقف أي فيديو يعمل قبل مغادرة التبويب.
    if (tab != _index) stopInlineVideos();
    _exitTimer?.cancel();
    _lastBackPress = null;
    setState(() {
      _index = tab;
      _exitArmed = false;
    });
    _selectedTab.value = tab;
    RouteStore.setTab(tab);
    _refreshDeep();
  }

  Widget _navItem(
    int i,
    IconData icon,
    IconData activeIcon,
    String label, {
    required Color foreground,
    required Color inactive,
    required void Function(int tab) select,
    int badgeCount = 0,
    bool showLabel = true,
    Widget Function(bool selected)? iconBuilder,
  }) {
    final selected = _index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          // الرسائل والملف الشخصي تحتاج حساباً.
          if ((i == 3 || i == 4) && needsLogin(context)) return;
          select(i);
        },
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
                  iconBuilder?.call(selected) ??
                      Icon(selected ? activeIcon : icon,
                          color: selected ? foreground : inactive, size: 23),
                  if (badgeCount != 0)
                    Positioned(
                      top: -5,
                      right: -8,
                      child: Tooltip(
                        message: badgeCount < 0
                            ? tr('تعذر تحميل عدد الرسائل')
                            : '$badgeCount ${tr('رسالة غير مقروءة')}',
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 15, minHeight: 15),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.notificationRed,
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
              if (showLabel) ...[
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _createButton({required bool dark, VoidCallback? onCreate}) {
    // زر الإضافة: طبقة بنفسجية فاتحة يساراً وبنفسجية داكنة يميناً
    // ومستطيل أبيض في الوسط (أسود في الوضع الفاتح) وعليه علامة +.
    final isDark = dark;
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
      onTap: onCreate ??
          () {
            if (needsLogin(context)) return;
            showCreateSheet(_tabNavigators[_index].currentContext ?? context);
          },
      child: SizedBox(
        width: 50,
        height: 34,
        child: Stack(
          children: [
            Positioned(left: 0, child: layer(AppColors.brandOrange)),
            Positioned(right: 0, child: layer(AppColors.brandPurple)),
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

/// يبلغ عند فتح صفحة جديدة داخل Navigator التبويب.
class _PushObserver extends NavigatorObserver {
  final VoidCallback onPush;
  _PushObserver(this.onPush);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onPush();
}

/// يعدّ الصفحات (PageRoute) المفتوحة داخل تبويب؛ النوافذ والقوائم لا تُحسب.
class _DepthObserver extends NavigatorObserver {
  final void Function(int delta) onChange;
  _DepthObserver(this.onChange);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onChange(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onChange(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onChange(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PageRoute) onChange(-1);
    if (newRoute is PageRoute) onChange(1);
  }
}

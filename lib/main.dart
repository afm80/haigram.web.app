import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'l10n.dart';
import 'net_error.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';
import 'route_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HaigramBootstrap());
}

class HaigramBootstrap extends StatefulWidget {
  const HaigramBootstrap({super.key});

  @override
  State<HaigramBootstrap> createState() => _HaigramBootstrapState();
}

class _HaigramBootstrapState extends State<HaigramBootstrap> {
  late Future<SharedPreferences> _startup = _initialize();

  Future<SharedPreferences> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return await SharedPreferences.getInstance();
    } catch (error, stackTrace) {
      debugPrint('Haigram startup failed: $error\n$stackTrace');
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _startup = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: ThemeMode.dark,
            home: _StartupErrorScreen(
              error: snapshot.error!,
              onRetry: _retry,
            ),
          );
        }
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: ThemeMode.dark,
            // لا نعرض الشعار هنا حتى لا يظهر شعاران متتاليان؛ يظهر مرة واحدة في الخطوة التالية.
            home: const Scaffold(body: SizedBox.shrink()),
          );
        }
        final preferences = snapshot.data!;
        return HaigramApp(
          preferences: preferences,
          showOnboarding:
              !(preferences.getBool('onboarding_complete') ?? false),
        );
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _StartupErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HaigramLogo(size: 84),
                  const SizedBox(height: 20),
                  Text(
                    isOfflineError(error)
                        ? tr('لا يوجد اتصال بالإنترنت')
                        : tr('تعذر تشغيل التطبيق'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isOfflineError(error)
                        ? tr('تحقق من اتصالك بالإنترنت ثم حاول مجدداً.')
                        : tr('تعذر تهيئة التطبيق، حاول مجدداً بعد قليل.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        tr('إعادة المحاولة'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HaigramApp extends StatefulWidget {
  final SharedPreferences preferences;
  final bool showOnboarding;
  const HaigramApp(
      {super.key, required this.preferences, required this.showOnboarding});

  @override
  State<HaigramApp> createState() => _HaigramAppState();
}

class _HaigramAppState extends State<HaigramApp> {
  late bool _showOnboarding = widget.showOnboarding;
  late ThemeMode _themeMode = widget.preferences.getBool('dark_mode') == false
      ? ThemeMode.light
      : ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    AppLang.code.value =
        widget.preferences.getString('lang') == 'en' ? 'en' : 'ar';
    AppLang.code.addListener(_onLangChanged);
  }

  @override
  void dispose() {
    AppLang.code.removeListener(_onLangChanged);
    super.dispose();
  }

  void _onLangChanged() {
    widget.preferences.setString('lang', AppLang.code.value);
    if (!mounted) return;
    setState(() {});
    // النصوص تُقرأ عبر tr() دون اشتراك في أي Inherited، فنعيد بناء كل الشاشات
    // المفتوحة ليظهر تغيير اللغة فوراً دون الخروج من الصفحة الحالية.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element el) {
        el.markNeedsBuild();
        el.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
  }

  Future<void> _completeOnboarding() async {
    final saved = await widget.preferences.setBool('onboarding_complete', true);
    if (!saved) throw StateError('Failed to save onboarding preference');
    if (mounted) setState(() => _showOnboarding = false);
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    final saved = await widget.preferences
        .setBool('dark_mode', themeMode == ThemeMode.dark);
    if (!saved) throw StateError(tr('تعذر حفظ إعداد المظهر'));
    if (mounted) setState(() => _themeMode = themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haigram',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      navigatorObservers: [rootRouteObserver],
      builder: (context, child) {
        final isDark = _themeMode == ThemeMode.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor:
                isDark ? AppPalette.dark.bg : AppPalette.light.bg,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      locale: Locale(AppLang.code.value),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _showOnboarding
          ? OnboardingScreen(onComplete: _completeOnboarding)
          : _buildAuthenticatedHome(),
    );
  }

  Widget _buildAuthenticatedHome() {
    try {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _StartupErrorScreen(
              error: snap.error!,
              onRetry: () => setState(() {}),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: HaigramLogo(size: 96)),
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: snap.data == null
                ? const AuthScreen(key: ValueKey('auth'))
                : HomeShell(
                    key: const ValueKey('home'),
                    themeMode: _themeMode,
                    onThemeModeChanged: _setThemeMode,
                  ),
          );
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Firebase Auth initialization failed: $error\n$stackTrace');
      return _StartupErrorScreen(
        error: error,
        onRetry: () => setState(() {}),
      );
    }
  }
}

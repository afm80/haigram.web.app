import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
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
    setState(() => _startup = _initialize());
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
            themeMode: ThemeMode.system,
            // لا نعرض الشعار هنا حتى لا يظهر شعاران متتاليان؛ يظهر مرة واحدة في الخطوة التالية.
            home: const Scaffold(body: SizedBox.shrink()),
          );
        }
        final preferences = snapshot.data!;
        return LamhaApp(
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
                  const LamhaLogo(size: 84),
                  const SizedBox(height: 20),
                  Text(
                    'تعذر تشغيل التطبيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'تعذر تهيئة التطبيق. تحقق من الاتصال بالإنترنت ثم حاول مجدداً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim, fontSize: 12),
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
                      child: const Text(
                        'إعادة تشغيل التطبيق',
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

class LamhaApp extends StatefulWidget {
  final SharedPreferences preferences;
  final bool showOnboarding;
  const LamhaApp({super.key, required this.preferences, required this.showOnboarding});

  @override
  State<LamhaApp> createState() => _LamhaAppState();
}

class _LamhaAppState extends State<LamhaApp> {
  late bool _showOnboarding = widget.showOnboarding;
  late ThemeMode _themeMode = widget.preferences.getBool('dark_mode') == false
      ? ThemeMode.light
      : ThemeMode.dark;

  Future<void> _completeOnboarding() async {
    final saved = await widget.preferences.setBool('onboarding_complete', true);
    if (!saved) throw StateError('Failed to save onboarding preference');
    if (mounted) setState(() => _showOnboarding = false);
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    final saved =
        await widget.preferences.setBool('dark_mode', themeMode == ThemeMode.dark);
    if (!saved) throw StateError('تعذر حفظ إعداد المظهر');
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
      locale: const Locale('ar'),
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
              body: Center(child: LamhaLogo(size: 96)),
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

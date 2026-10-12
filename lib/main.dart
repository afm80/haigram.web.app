
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  final preferences = await SharedPreferences.getInstance();
  runApp(LamhaApp(
    preferences: preferences,
    showOnboarding: !(preferences.getBool('onboarding_complete') ?? false),
  ));
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

  Future<void> _completeOnboarding() async {
    final saved = await widget.preferences.setBool('onboarding_complete', true);
    if (!saved) throw StateError('Failed to save onboarding preference');
    if (mounted) setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haigram',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
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
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                      body: AppLoading(message: 'جارٍ تجهيز التطبيق...'));
                }
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: snap.data == null
                      ? const AuthScreen(key: ValueKey('auth'))
                      : const HomeShell(key: ValueKey('home')),
                );
              },
            ),
    );
  }
}

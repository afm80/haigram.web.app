import 'package:flutter/material.dart';

/// الهوية البصرية الأصلية لتطبيق "لمحة": خلفية داكنة عميقة ولون مميز بنفسجي-مرجاني.
class AppColors {
  static const bg = Color(0xFF0B0B10);
  static const surface = Color(0xFF16161E);
  static const surfaceHigh = Color(0xFF22222D);
  static const accent = Color(0xFF8B5CF6);
  static const accent2 = Color(0xFFFF6B8B);
  static const textDim = Color(0xFF9A9AAA);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.surface,
    ),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

/// شعار التطبيق الأصلي (تدرّج لوني + رمز تشغيل).
class LamhaLogo extends StatelessWidget {
  final double size;
  const LamhaLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          colors: [AppColors.accent, AppColors.accent2],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.62),
    );
  }
}

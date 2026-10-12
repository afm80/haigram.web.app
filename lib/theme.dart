import 'package:flutter/material.dart';

/// لوحة الألوان المشتركة لهوية Haigram.
class AppColors {
  static const brandRed = Color(0xFFFF0051);
  static const brandCyan = Color(0xFF42D4F4);
  static const accent = Color(0xFF087F94);
  static const accent2 = brandRed;
  static const accent3 = Color(0xFF006577);
  static const videoLike = Color(0xFFFE2C55);
  static const postLike = Color(0xFFFF3040);
  static const success = Color(0xFF34D399);

  static AppPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
}

class HaigramWordmark extends StatelessWidget {
  final TextStyle style;

  const HaigramWordmark({
    super.key,
    this.style = const TextStyle(fontWeight: FontWeight.w800),
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'H', style: style.copyWith(color: AppColors.brandRed)),
          const TextSpan(text: 'ai'),
          TextSpan(
              text: 'g', style: style.copyWith(color: AppColors.brandCyan)),
          const TextSpan(text: 'ram'),
        ],
      ),
      textDirection: TextDirection.ltr,
      style: style,
    );
  }
}

class AppPalette {
  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surfaceHigh;
  final Color card;
  final Color text;
  final Color textDim;
  final Color shadow;

  const AppPalette({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surfaceHigh,
    required this.card,
    required this.text,
    required this.textDim,
    required this.shadow,
  });

  static const dark = AppPalette(
    bg: Color(0xFF0B0B12),
    bg2: Color(0xFF12141C),
    surface: Color(0xFF171A24),
    surfaceHigh: Color(0xFF212632),
    card: Color(0xFF1A1D2A),
    text: Color(0xFFF3F5F9),
    textDim: Color(0xFF9AA2B5),
    shadow: Color(0x66000000),
  );

  static const light = AppPalette(
    bg: Color(0xFFF7F6FB),
    bg2: Color(0xFFEDEBF4),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEAE8F1),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF1C1B22),
    textDim: Color(0xFF666574),
    shadow: Color(0x22000000),
  );
}

extension AppColorContext on BuildContext {
  AppPalette get appColors =>
      AppColors.forBrightness(Theme.of(this).brightness);
}

ThemeData buildTheme(Brightness brightness) {
  final colors = AppColors.forBrightness(brightness);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: AppColors.accent3,
            secondary: AppColors.accent2,
            surface: colors.surface,
            onPrimary: Colors.white,
            onSurface: colors.text,
            onSecondary: Colors.white,
          )
        : ColorScheme.light(
            primary: AppColors.accent3,
            secondary: AppColors.accent2,
            surface: colors.surface,
            onPrimary: Colors.white,
            onSurface: colors.text,
            onSecondary: Colors.white,
          ),
    textTheme: base.textTheme
        .apply(
          bodyColor: colors.text,
          displayColor: colors.text,
          fontFamily: 'Roboto',
        )
        .copyWith(
          headlineSmall: const TextStyle(fontWeight: FontWeight.w800),
          titleLarge: const TextStyle(fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(color: colors.text),
          bodyMedium: TextStyle(color: colors.text),
        ),
    iconTheme: IconThemeData(color: colors.text),
    primaryIconTheme: IconThemeData(color: colors.text),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.text),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: colors.text),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: colors.text,
      unselectedLabelColor: colors.textDim,
      indicatorColor: colors.text,
      dividerColor: colors.surfaceHigh,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: colors.text),
      titleTextStyle: TextStyle(
        color: colors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceHigh,
      labelStyle: TextStyle(color: colors.textDim),
      floatingLabelStyle: TextStyle(color: colors.text),
      prefixStyle: TextStyle(color: colors.text),
      suffixStyle: TextStyle(color: colors.text),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: colors.textDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent3,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    cardTheme: CardTheme(
      color: colors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.text.withOpacity(0.12),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      textColor: colors.text,
      iconColor: colors.textDim,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceHigh,
      textStyle: TextStyle(color: colors.text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceHigh,
      contentTextStyle: TextStyle(color: colors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class LamhaLogo extends StatelessWidget {
  final double size;
  const LamhaLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/haigram-mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class AppLoading extends StatelessWidget {
  final String? message;
  const AppLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LamhaLogo(size: 52),
          const SizedBox(height: 18),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: TextStyle(color: context.appColors.textDim)),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appColors.surfaceHigh,
                border:
                    Border.all(color: context.appColors.text.withOpacity(0.06)),
              ),
              child: Icon(icon, size: 34, color: context.appColors.textDim),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: context.appColors.textDim, height: 1.5)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

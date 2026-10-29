import 'package:flutter/material.dart';

/// Halladín brand palette. Semantic roles are assigned in personasTheme.
abstract final class HalladinColors {
  static const night = Color(0xff012369);
  static const deepBlue = Color(0xff09296e);
  static const gold = Color(0xfffed73e);
  static const darkGold = Color(0xff9f4a00);
  static const turquoise = Color(0xff01b7ab);
  static const brightBlue = Color(0xff0c69fc);
  static const ivory = Color(0xfffdf9e4);
  // Accessible supporting tones for text, outlines and system dark mode.
  static const tealInk = Color(0xff00675f);
  static const selectionSurface = Color(0xffd7f3eb);
  static const focusSurface = Color(0xffe1edff);
  static const darkSurface = Color(0xff101b30);
  static const darkCard = Color(0xff192840);
  static const muted = Color(0xff526077);
  static const outline = Color(0xff748096);
  static const disabledSurface = Color(0xffdedfda);
  static const disabledInk = Color(0xff596175);
}

/// Shared depth and gradients keep all existing screens visually consistent.
abstract final class HalladinSurfaces {
  static Widget actionLayer(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => states.contains(WidgetState.disabled)
      ? child ?? const SizedBox.shrink()
      : DecoratedBox(
          decoration: BoxDecoration(
            gradient: action,
            borderRadius: BorderRadius.circular(buttonRadius),
            border: Border.all(color: HalladinColors.gold, width: 1.5),
          ),
          child: child,
        );
  static const cardRadius = 24.0;
  static const buttonRadius = 28.0;
  static const action = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xffffef83), HalladinColors.gold, Color(0xffffc334)],
    stops: [0, .4, 1],
  );
  static const hero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [HalladinColors.night, HalladinColors.deepBlue, Color(0xff001a52)],
    stops: [0, .45, 1],
  );
  static const goldLettering = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xfffff1a6), HalladinColors.gold, Color(0xffefb630)],
    stops: [0, .6, 1],
  );
  static const ivoryLettering = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xfffffff7), HalladinColors.ivory, Color(0xffffe5a5)],
    stops: [0, .75, 1],
  );

  static LinearGradient card(ColorScheme colors, {bool selected = false}) {
    final dark = colors.brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: selected
          ? [
              colors.secondaryContainer,
              dark ? HalladinColors.darkCard : const Color(0xffedf9f2),
            ]
          : [
              dark ? HalladinColors.darkCard : const Color(0xfffffef7),
              colors.surface,
            ],
    );
  }

  static List<BoxShadow> shadow({bool raised = false}) => [
    BoxShadow(
      color: HalladinColors.night.withValues(alpha: raised ? .16 : .07),
      blurRadius: raised ? 28 : 16,
      offset: Offset(0, raised ? 10 : 5),
      spreadRadius: -4,
    ),
  ];
}

abstract final class PersonasMotion {
  static const curve = Curves.easeOutCubic;
  static Duration duration(BuildContext context) =>
      Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180);
}

ThemeData personasTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: HalladinColors.night,
        brightness: brightness,
      ).copyWith(
        primary: dark ? HalladinColors.ivory : HalladinColors.night,
        onPrimary: dark ? HalladinColors.night : HalladinColors.ivory,
        primaryContainer: dark
            ? HalladinColors.deepBlue
            : HalladinColors.focusSurface,
        onPrimaryContainer: dark ? HalladinColors.ivory : HalladinColors.night,
        secondary: HalladinColors.turquoise,
        onSecondary: HalladinColors.night,
        secondaryContainer: dark
            ? HalladinColors.tealInk
            : HalladinColors.selectionSurface,
        onSecondaryContainer: dark
            ? HalladinColors.ivory
            : HalladinColors.night,
        tertiary: dark ? HalladinColors.gold : HalladinColors.darkGold,
        onTertiary: dark ? HalladinColors.night : HalladinColors.ivory,
        surface: dark ? HalladinColors.darkSurface : HalladinColors.ivory,
        onSurface: dark ? HalladinColors.ivory : HalladinColors.night,
        onSurfaceVariant: dark ? const Color(0xffc3ccdc) : HalladinColors.muted,
        surfaceContainerLowest: dark
            ? HalladinColors.darkSurface
            : HalladinColors.ivory,
        surfaceContainerLow: dark
            ? HalladinColors.darkCard
            : HalladinColors.ivory,
        surfaceContainer: dark ? HalladinColors.darkCard : HalladinColors.ivory,
        surfaceContainerHigh: dark
            ? HalladinColors.deepBlue
            : HalladinColors.focusSurface,
        surfaceContainerHighest: dark
            ? HalladinColors.deepBlue
            : HalladinColors.focusSurface,
        outline: dark ? const Color(0xff9eabc2) : HalladinColors.outline,
        outlineVariant: dark
            ? const Color(0xff526077)
            : const Color(0xffc4c9cd),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -.7,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.18,
        letterSpacing: -.4,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: HalladinColors.night,
      foregroundColor: HalladinColors.ivory,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: HalladinColors.ivory,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: HalladinColors.night.withValues(alpha: .16),
      surfaceTintColor: Colors.transparent,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 3,
        shadowColor: HalladinColors.darkGold.withValues(alpha: .3),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
        backgroundColor: HalladinColors.gold,
        foregroundColor: HalladinColors.night,
        disabledBackgroundColor: dark
            ? HalladinColors.darkCard
            : HalladinColors.disabledSurface,
        disabledForegroundColor: dark
            ? const Color(0xff9eabc2)
            : HalladinColors.disabledInk,
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: scheme.surfaceContainerLow,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HalladinColors.brightBlue,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? null
            : states.contains(WidgetState.selected)
            ? HalladinColors.turquoise
            : null,
      ),
      checkColor: const WidgetStatePropertyAll(HalladinColors.night),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: HalladinColors.brightBlue, width: 2),
      ),
      border: OutlineInputBorder(),
    ),
  );
}

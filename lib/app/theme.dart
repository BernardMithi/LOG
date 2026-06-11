import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class LiftMotion {
  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration emphasized = Duration(milliseconds: 320);

  static const Curve pressCurve = Curves.easeOutCubic;
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve standardReverseCurve = Curves.easeInCubic;

  static const double pressScale = 0.97;
  static const double gentlePressScale = 0.985;
}

/// Shorter than Material’s default snack display (~4s). Use as [SnackBar.duration].
const Duration kLiftSnackBarDuration = Duration(milliseconds: 1750);

abstract final class LiftTransitions {
  static Widget buildRouteTransition({
    required BuildContext context,
    required Animation<double> animation,
    required Widget child,
  }) {
    final surfaceColor = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: surfaceColor,
      child: RepaintBoundary(
        child: buildFadeUpTransition(
          animation: animation,
          child: child,
          beginOffset: const Offset(0, 0.018),
          beginScale: 0.996,
          fadeStart: 0.18,
        ),
      ),
    );
  }

  static Widget buildFadeUpTransition({
    required Animation<double> animation,
    required Widget child,
    Offset beginOffset = const Offset(0, 0.018),
    double beginScale = 0.996,
    double fadeStart = 0.0,
  }) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: LiftMotion.enterCurve,
      reverseCurve: LiftMotion.exitCurve,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: Interval(
        fadeStart.clamp(0.0, 1.0),
        1.0,
        curve: LiftMotion.enterCurve,
      ),
      reverseCurve: LiftMotion.exitCurve,
    );
    final slide = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(curve);
    final scale = Tween<double>(begin: beginScale, end: 1.0).animate(curve);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }

  static Widget buildDirectionalSwap({
    required Animation<double> animation,
    required Widget child,
    required bool isIncoming,
    required bool isForward,
  }) {
    final slide = Tween<Offset>(
      begin: isIncoming ? Offset(isForward ? 0.08 : -0.08, 0) : Offset.zero,
      end: isIncoming ? Offset.zero : Offset(isForward ? -0.035 : 0.035, 0),
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: LiftMotion.enterCurve,
        reverseCurve: LiftMotion.exitCurve,
      ),
    );
    final fade = Tween<double>(
      begin: isIncoming ? 0.0 : 1.0,
      end: isIncoming ? 1.0 : 0.0,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve:
            isIncoming
                ? const Interval(0.10, 1.0, curve: LiftMotion.enterCurve)
                : LiftMotion.enterCurve,
        reverseCurve: LiftMotion.exitCurve,
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  static Widget buildPageSwap({
    required Animation<double> animation,
    required Widget child,
    required bool isIncoming,
    required bool isForward,
  }) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: LiftMotion.enterCurve,
      reverseCurve: LiftMotion.exitCurve,
    );
    final slide = Tween<Offset>(
      begin: isIncoming ? Offset(0, isForward ? 0.028 : -0.010) : Offset.zero,
      end: isIncoming ? Offset.zero : Offset(0, isForward ? -0.012 : 0.018),
    ).animate(curve);
    final fade = Tween<double>(
      begin: isIncoming ? 0.0 : 1.0,
      end: isIncoming ? 1.0 : 0.0,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve:
            isIncoming
                ? const Interval(0.08, 1.0, curve: LiftMotion.enterCurve)
                : const Interval(0.0, 0.78, curve: LiftMotion.exitCurve),
        reverseCurve: LiftMotion.exitCurve,
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  static Widget buildStackedPageSwap({
    required Animation<double> animation,
    required Widget child,
    required bool isIncoming,
    required bool isForward,
  }) {
    if (isForward) {
      if (!isIncoming) return child;
      return buildFadeUpTransition(
        animation: animation,
        child: child,
        beginOffset: const Offset(0, 0.022),
        beginScale: 0.994,
        fadeStart: 0.08,
      );
    }

    if (isIncoming) return child;

    final curve = CurvedAnimation(
      parent: animation,
      curve: LiftMotion.enterCurve,
      reverseCurve: LiftMotion.exitCurve,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.014),
      end: Offset.zero,
    ).animate(curve);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.78, curve: LiftMotion.enterCurve),
        reverseCurve: LiftMotion.exitCurve,
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

class _LiftPageTransitionsBuilder extends PageTransitionsBuilder {
  const _LiftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return LiftTransitions.buildRouteTransition(
      context: context,
      animation: animation,
      child: child,
    );
  }
}

const Color kAccentColor = Color(0xFF17181A);
const Color kAccentDark = Color(0xFF0F1114);
const Color kAccentMid = Color(0xFF56606B);
const Color kAccentLight = Color(0xFFD3D8DF);
const Color kCautionColor = Color(0xFF697381);
const Color kLiftDividerColor = Color(0x2617181A);

/// Dark green for positive actions (e.g. complete workout confirm).
const Color kLiftPositiveGreen = Color(0xFF1B5E20);

/// Home “Schedule” row: title, chevron, and day circles use the accent family.
const Color kScheduleTitleColor = kAccentColor;
const Color kScheduleChevronColor = kAccentMid;

/// Unselected day circle stroke (cool gray from palette).
const Color kScheduleDayCircleBorder = kAccentLight;

/// Selected day circle fill — soft tint between white and [kAccentLight].
const Color kScheduleDayCircleFillSelected = Color(0xFFE8EAED);
const Color kRecoveryMidColor = Color(0xFFFF9F0A);
const double kPagePadding = 12.0;
const double kIslandHeaderGap = 20.0;

Color liftCanvasColor(
  BuildContext context, {
  Color light = const Color(0xFFF7F7F8),
}) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF090A0C)
      : light;
}

/// Top [LiftIslandHeader] / frosted bars that match the shell header chrome.
const double kLiftIslandHeaderHeight = 56.0;

/// Home shell bottom tab bar ([_FloatingIslandNav]) — slightly taller than
/// [kLiftIslandHeaderHeight] for touch targets and the Guides pill.
const double kShellFloatingNavBarHeight = 60.0;

/// Mynaui icons in [LiftIslandHeader] leading / trailing slots (QR, profile, etc.).
const double kLiftIslandHeaderLeadingIconSize = 28.0;
const double kLiftIslandHeaderTrailingIconSize = 26.0;

/// Distance from the bottom of the screen to the **bottom** edge of the shell
/// floating nav (and matching floating bars on detail flows).
const double kShellFloatingNavBottomInset = 16.0;

/// Extra padding for tab scroll views so content clears the floating nav + inset.
const double kShellTabContentBottomInset =
    kShellFloatingNavBottomInset + kShellFloatingNavBarHeight + 12.0;

/// Gap between the bottom of [WorkoutLiveDock] and the top of the shell nav.
const double kShellLiveDockGapAboveNav = 8.0;

/// Bottom inset for [WorkoutLiveDock] when the shell nav is hidden.
const double kShellStandaloneLiveDockBottomInset = 18.0;

/// [WorkoutLiveDock] sits directly above the floating bottom nav (plus gap).
const double kShellLiveDockBottomOffset =
    kShellFloatingNavBottomInset +
    kShellFloatingNavBarHeight +
    kShellLiveDockGapAboveNav;

/// Scroll distance for island bar → floating buttons crossfade.
const double kLiftIslandHeaderCollapseDistance = 48.0;

/// Icon / title on frosted island surfaces (bottom nav unselected tone).
const Color kLiftIslandOnFrosted = Color(0xDD000000);

/// Primary surface radius used by the floating island, cards, and sheets.
const double kIosSurfaceRadius = 22;

/// Kept as the app-wide default for existing call sites.
const double kIosCornerRadius = kIosSurfaceRadius;

/// Smaller control radius derived from the island so compact controls do not
/// read rounder than primary surfaces.
const double kIosControlRadius = 18;

/// Media surfaces sit a bit tighter than cards so images do not read pill-like.
const double kIosMediaRadius = 16;

/// Exercise list / swap thumbnails — subtler rounding than [kIosControlRadius].
const double kExerciseImageRadius = 12;

/// Uniform [BorderRadius] for [kExerciseImageRadius].
const BorderRadius kExerciseImageBorderRadius = BorderRadius.all(
  Radius.circular(kExerciseImageRadius),
);

/// Tightest radius for chips, tags, and other compact inline surfaces.
const double kIosChipRadius = 14;

/// Kept for call sites that semantically mean “pill”.
const double kIosPillRadius = kIosChipRadius;

/// Uniform [BorderRadius] using [kIosSurfaceRadius].
const BorderRadius kIosBorderRadius = BorderRadius.all(
  Radius.circular(kIosSurfaceRadius),
);

/// Uniform [BorderRadius] using [kIosControlRadius].
const BorderRadius kIosControlBorderRadius = BorderRadius.all(
  Radius.circular(kIosControlRadius),
);

/// Uniform [BorderRadius] using [kIosChipRadius].
const BorderRadius kIosChipBorderRadius = BorderRadius.all(
  Radius.circular(kIosChipRadius),
);

TextStyle? _reduceTextStyle(TextStyle? style, [double delta = 1]) {
  if (style?.fontSize == null) return style;
  return style!.copyWith(fontSize: style.fontSize! - delta);
}

TextTheme _reduceTextTheme(TextTheme textTheme, [double delta = 1]) {
  return textTheme.copyWith(
    displayLarge: _reduceTextStyle(textTheme.displayLarge, delta),
    displayMedium: _reduceTextStyle(textTheme.displayMedium, delta),
    displaySmall: _reduceTextStyle(textTheme.displaySmall, delta),
    headlineLarge: _reduceTextStyle(textTheme.headlineLarge, delta),
    headlineMedium: _reduceTextStyle(textTheme.headlineMedium, delta),
    headlineSmall: _reduceTextStyle(textTheme.headlineSmall, delta),
    titleLarge: _reduceTextStyle(textTheme.titleLarge, delta),
    titleMedium: _reduceTextStyle(textTheme.titleMedium, delta),
    titleSmall: _reduceTextStyle(textTheme.titleSmall, delta),
    bodyLarge: _reduceTextStyle(textTheme.bodyLarge, delta),
    bodyMedium: _reduceTextStyle(textTheme.bodyMedium, delta),
    bodySmall: _reduceTextStyle(textTheme.bodySmall, delta),
    labelLarge: _reduceTextStyle(textTheme.labelLarge, delta),
    labelMedium: _reduceTextStyle(textTheme.labelMedium, delta),
    labelSmall: _reduceTextStyle(textTheme.labelSmall, delta),
  );
}

ThemeData buildLiftTheme([Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;
  final seed = isDark ? const Color(0xFFE8EAED) : kAccentColor;
  final scaffold = isDark ? const Color(0xFF090A0C) : Colors.white;
  final surface = isDark ? const Color(0xFF15171B) : Colors.white;
  final onSurface = isDark ? const Color(0xFFF4F5F7) : kAccentColor;
  final muted = isDark ? const Color(0xFFA9B1BA) : kAccentMid;
  final baseTheme = ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surface,
      onSurface: onSurface,
    ),
    useMaterial3: true,
  );
  final appTextTheme = _reduceTextTheme(
    GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme),
  );
  final buttonTextStyle = GoogleFonts.spaceGrotesk(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );
  return baseTheme.copyWith(
    textTheme: appTextTheme,
    scaffoldBackgroundColor: scaffold,
    dividerTheme: DividerThemeData(
      color: isDark ? Colors.white.withValues(alpha: 0.10) : kLiftDividerColor,
      thickness: 1,
      space: 1,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: _LiftPageTransitionsBuilder(),
        TargetPlatform.android: _LiftPageTransitionsBuilder(),
        TargetPlatform.macOS: _LiftPageTransitionsBuilder(),
        TargetPlatform.linux: _LiftPageTransitionsBuilder(),
        TargetPlatform.windows: _LiftPageTransitionsBuilder(),
      },
    ),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? const Color(0xFFF3F4F6) : kAccentColor,
        foregroundColor: isDark ? kAccentDark : Colors.white,
        disabledBackgroundColor: onSurface.withValues(alpha: 0.20),
        disabledForegroundColor: muted.withValues(alpha: 0.66),
        elevation: 0,
        shadowColor: Colors.transparent,
        overlayColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: kIosControlBorderRadius),
        textStyle: buttonTextStyle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        backgroundColor: onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
        disabledForegroundColor: muted.withValues(alpha: 0.58),
        side: BorderSide(color: onSurface.withValues(alpha: 0.26)),
        elevation: 0,
        shadowColor: Colors.transparent,
        overlayColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: kIosControlBorderRadius),
        textStyle: buttonTextStyle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: onSurface,
        disabledForegroundColor: muted.withValues(alpha: 0.58),
        overlayColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: kIosControlBorderRadius),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: onSurface,
        backgroundColor: onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: muted.withValues(alpha: 0.58),
        side: BorderSide(color: onSurface.withValues(alpha: 0.24)),
        minimumSize: const Size.square(46),
        overlayColor: Colors.transparent,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: kIosControlBorderRadius),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF2D2D2F),
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: GoogleFonts.spaceGrotesk(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
    ),
  );
}

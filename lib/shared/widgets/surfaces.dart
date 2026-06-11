import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.height,
    this.width,
    this.borderRadius = kIosCornerRadius,
    this.padding = const EdgeInsets.all(15),
    this.blur = 12,
    this.showBorder = true,
    this.showSheen = true,
  });

  final Widget child;
  final double? height;
  final double? width;
  final double borderRadius;
  final EdgeInsets padding;
  final double blur;
  final bool showBorder;
  final bool showSheen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final glassGrey = const Color(0xFFD8DDE3);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            spreadRadius: 0.5,
            offset: Offset.zero,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            height: height,
            width: width,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  glassGrey.withValues(alpha: 0.22),
                  glassGrey.withValues(alpha: 0.18),
                  glassGrey.withValues(alpha: 0.14),
                ],
              ),
              border:
                  showBorder
                      ? Border.all(
                        color: glassGrey.withValues(alpha: 0.26),
                        width: 1,
                      )
                      : null,
            ),
            child: Stack(
              children: [
                if (showSheen)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              glassGrey.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassIsland extends StatelessWidget {
  const GlassIsland({
    super.key,
    required this.child,
    this.height = 76,
    this.borderRadius = kIosCornerRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.blur = 14,
  });

  final Widget child;
  final double height;
  final double borderRadius;
  final EdgeInsets padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      height: height,
      borderRadius: borderRadius,
      blur: blur,
      showBorder: false,
      showSheen: false,
      padding: padding,
      child: child,
    );
  }
}

class FrostedControlSurface extends StatelessWidget {
  const FrostedControlSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.borderRadius = kIosControlRadius,
    this.blur = 12,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  backgroundColor ??
                  (isDark
                      ? const Color(0xFF17191D).withValues(alpha: 0.82)
                      : Colors.white.withValues(alpha: 0.74)),
              borderRadius: radius,
              border: Border.all(
                color:
                    borderColor ??
                    (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class FrostedIconActionButton extends StatelessWidget {
  const FrostedIconActionButton({
    super.key,
    this.icon,
    this.iconWidget,
    required this.onTap,
    this.size = 52,
    this.iconSize = 24,
    this.borderRadius = kIosControlRadius,
    this.highlighted = false,
    this.iconColor,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;

  /// When set (e.g. [MynauiIcon]), used instead of [icon].
  final Widget? iconWidget;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final double borderRadius;
  final bool highlighted;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        iconColor ??
        (highlighted
            ? (isDark ? Colors.white : kAccentColor)
            : kLiftIslandOnFrosted);
    return LiftPressable(
      onTap: onTap,
      borderRadius: borderRadius,
      pressedScale: LiftMotion.gentlePressScale,
      child: FrostedControlSurface(
        padding: EdgeInsets.zero,
        borderRadius: borderRadius,
        backgroundColor:
            isDark
                ? const Color(
                  0xFF17191D,
                ).withValues(alpha: highlighted ? 0.92 : 0.82)
                : Colors.white.withValues(alpha: highlighted ? 0.84 : 0.74),
        borderColor:
            highlighted
                ? foreground.withValues(alpha: 0.18)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.08)),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: iconWidget ?? Icon(icon!, color: foreground, size: iconSize),
          ),
        ),
      ),
    );
  }
}

/// First Progress section — same corner radius as the home recovery tile.
const BorderRadius kProgressFirstSectionRadius = kIosBorderRadius;

class SectionBoundary extends StatelessWidget {
  const SectionBoundary({
    super.key,
    required this.child,
    this.borderRadius = kIosCornerRadius,
    this.customBorderRadius,
    this.padding = const EdgeInsets.all(12),
    this.clipBehavior = Clip.none,
    this.floating = false,
    this.floatingBackgroundOpacity,
  });

  final Widget child;
  final double borderRadius;
  final BorderRadius? customBorderRadius;
  final EdgeInsets padding;
  final Clip clipBehavior;
  final bool floating;

  /// When [floating] is true, overrides the default 0.72 opacity for a more solid look.
  final double? floatingBackgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final radius = customBorderRadius ?? BorderRadius.circular(borderRadius);
    final floatAlpha = floatingBackgroundOpacity ?? 0.72;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF15171B) : Colors.white;
    final section = Container(
      padding: padding,
      decoration: BoxDecoration(
        color:
            floating
                ? baseColor.withValues(alpha: isDark ? 0.88 : floatAlpha)
                : baseColor,
        borderRadius: radius,
        border: Border.all(
          color:
              floating
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.11)
                      : Colors.grey.shade300.withValues(alpha: 0.6))
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.grey.shade200),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isDark ? 0.28 : (floating ? 0.06 : 0.03),
            ),
            blurRadius: floating ? 16 : 10,
            spreadRadius: floating ? 0 : 0.5,
            offset: Offset.zero,
          ),
        ],
      ),
      child: child,
    );

    if (clipBehavior == Clip.none) return section;

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: section,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';

/// Renders an SVG from [assets/icons] ([MynauiGlyphs] paths).
///
/// Vendored icons use `stroke="currentColor"` / `fill="currentColor"` where possible
/// so [color] tints reliably via [ColorFilter].
class MynauiIcon extends StatelessWidget {
  const MynauiIcon(
    this.assetPath, {
    super.key,
    this.size = 24,
    this.color,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  });

  final String assetPath;
  final double size;
  final Color? color;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? DefaultTextStyle.of(context).style.color;
    final icon = SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      fit: fit,
      colorFilter:
          effectiveColor != null
              ? ColorFilter.mode(effectiveColor, BlendMode.srcIn)
              : null,
      semanticsLabel: semanticLabel,
    );
    if (assetPath == MynauiGlyphs.altArrowLeft) {
      return Transform.translate(offset: const Offset(-2, 0), child: icon);
    }
    return icon;
  }
}

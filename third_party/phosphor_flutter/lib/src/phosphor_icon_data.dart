library phosphor_flutter;

import 'package:flutter/widgets.dart';

class PhosphorIconData {
  const PhosphorIconData(this.codePoint, this.style);

  final int codePoint;
  final String style;

  IconData toIconData() {
    return IconData(
      codePoint,
      fontFamily: 'Phosphor$style',
      fontPackage: 'phosphor_flutter',
      matchTextDirection: true,
    );
  }
}

class PhosphorDuotoneIconData {
  const PhosphorDuotoneIconData(this.codePoint, this.secondary);

  final int codePoint;
  final PhosphorIconData secondary;

  IconData toIconData() {
    return IconData(
      codePoint,
      fontFamily: 'PhosphorDuotone',
      fontPackage: 'phosphor_flutter',
      matchTextDirection: true,
    );
  }
}

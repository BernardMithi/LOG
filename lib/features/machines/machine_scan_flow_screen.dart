import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/machines/machine_screen.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/models/machine.dart';

/// Short “scanning station” phase, then [MachineScreen] in the **same** route so
/// back navigation and `Navigator.pop(result)` behave like opening the machine
/// screen directly.
class MachineScanFlowScreen extends StatefulWidget {
  const MachineScanFlowScreen({
    super.key,
    required this.machine,
    this.returnExerciseOnTap = false,
  });

  final Machine machine;

  /// Passed through to [MachineScreen].
  final bool returnExerciseOnTap;

  @override
  State<MachineScanFlowScreen> createState() => _MachineScanFlowScreenState();
}

class _MachineScanFlowScreenState extends State<MachineScanFlowScreen> {
  static const Duration _scanDuration = Duration(milliseconds: 1100);

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_scanDuration, () {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MachineScreen(
        machine: widget.machine,
        returnExerciseOnTap: widget.returnExerciseOnTap,
      );
    }
    return Scaffold(
      backgroundColor: liftCanvasColor(context, light: const Color(0xFFF8F8F8)),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: 8,
              left: kPagePadding,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: MynauiIcon(
                      MynauiGlyphs.altArrowLeft,
                      size: 24,
                      color: Colors.black.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _MachineScanLoadingCard(
                  machineLabel: widget.machine.displayName,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineScanLoadingCard extends StatelessWidget {
  const _MachineScanLoadingCard({required this.machineLabel});

  final String machineLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(kIosCornerRadius + 6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kAccentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Center(
              child: MynauiIcon(
                MynauiGlyphs.qrCode,
                size: 34,
                color: kAccentColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Scanning machine',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF171717),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            machineLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 6,
              color: kAccentColor,
              backgroundColor: Color(0xFFE3E7EC),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Matching this station to your exercise library.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

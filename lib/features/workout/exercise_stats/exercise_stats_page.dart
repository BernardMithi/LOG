import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_models.dart';
import 'package:lift/features/progress/leg_day_trends/widgets/leg_day_trends_sections.dart';
import 'package:lift/features/workout/exercise_stats/exercise_stats_mock_data.dart';
import 'package:lift/features/workout/exercise_stats/exercise_stats_models.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_floating_island.dart';
import 'package:lift/shared/widgets/surfaces.dart';

const Color _kExerciseStatsAccent = Color(0xFF171717);

/// Full-screen stats for a single exercise (trends-style chart + summary).
class ExerciseStatsPage extends StatefulWidget {
  const ExerciseStatsPage({super.key, required this.exerciseName, this.data});

  final String exerciseName;
  final ExerciseStatsData? data;

  @override
  State<ExerciseStatsPage> createState() => _ExerciseStatsPageState();
}

class _ExerciseStatsPageState extends State<ExerciseStatsPage> {
  LegDayTrendRange _selectedRange = LegDayTrendRange.thirtyDays;
  LegDayTrendMetric _selectedMetric = LegDayTrendMetric.volume;

  @override
  Widget build(BuildContext context) {
    final data =
        widget.data ?? ExerciseStatsMockData.forExercise(widget.exerciseName);
    final snapshot = data.snapshotFor(_selectedRange);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    final listTopPadding = topInset + islandTop;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  kPagePadding,
                  listTopPadding,
                  kPagePadding,
                  12 + bottomInset,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LegDayTrendsHeader(
                          title: data.exerciseName,
                          subtitle: data.subtitle,
                        ),
                        const SizedBox(height: 16),
                        _QuickStatsCard(
                          summary: data.summary,
                          accentColor: _kExerciseStatsAccent,
                        ),
                        const SizedBox(height: 12),
                        LegDayRangeSelector(
                          selectedRange: _selectedRange,
                          onChanged:
                              (range) => setState(() => _selectedRange = range),
                          accentColor: _kExerciseStatsAccent,
                        ),
                        const SizedBox(height: 16),
                        PrimaryTrendCard(
                          snapshot: snapshot,
                          selectedMetric: _selectedMetric,
                          onMetricChanged:
                              (metric) =>
                                  setState(() => _selectedMetric = metric),
                          accentColor: _kExerciseStatsAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset + islandTop,
              left: kPagePadding,
              child: _BackOrbButton(onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStatsCard extends StatelessWidget {
  const _QuickStatsCard({required this.summary, required this.accentColor});

  final ExerciseStatsSummary summary;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final iconTint = accentColor.withValues(alpha: 0.88);
    final chipBg = accentColor.withValues(alpha: 0.07);

    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: MynauiIcon(
                    MynauiGlyphs.diagramUp,
                    size: 16,
                    color: iconTint,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'At a glance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MiniStat(
                    icon: MynauiGlyphs.clipboardList,
                    label: 'Sessions',
                    value: '${summary.sessionsWithExercise}',
                    accentColor: accentColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    icon: MynauiGlyphs.weightlifting,
                    label: 'Best recent set',
                    value: summary.bestRecentSet,
                    accentColor: accentColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    icon: MynauiGlyphs.calendar,
                    label: 'Last time',
                    value: summary.lastPerformedLabel,
                    accentColor: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.shade300.withValues(alpha: 0.65);
    final tileBg = accentColor.withValues(alpha: 0.035);
    final iconWell = accentColor.withValues(alpha: 0.09);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconWell,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: MynauiIcon(
                  icon,
                  size: 17,
                  color: accentColor.withValues(alpha: 0.88),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.25,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: accentColor.withValues(alpha: 0.94),
                height: 1.22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackOrbButton extends StatelessWidget {
  const _BackOrbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiftFloatingIslandSurface(
      borderRadius: 24,
      boxShadow: LiftFloatingIslandTokens.chipShadows,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: MynauiIcon(
                MynauiGlyphs.altArrowLeft,
                color: kLiftIslandOnFrosted,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_models.dart';
import 'package:lift/features/progress/leg_day_trends/widgets/leg_day_trends_sections.dart';
import 'package:lift/features/workout/exercise_details/exercise_detail_data.dart';
import 'package:lift/features/workout/exercise_stats/exercise_stats_mock_data.dart';
import 'package:lift/features/workout/exercise_stats/exercise_stats_models.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_floating_island.dart';
import 'package:lift/shared/widgets/lower_body_mannequin_panel.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:lift/shared/widgets/workout_target_mannequin_panel.dart';

Future<void> pushExerciseDetailPage(
  BuildContext context, {
  required String exerciseName,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ExerciseDetailPage(exerciseName: exerciseName),
    ),
  );
}

enum _ExerciseDetailTab { execution, target, trends }

extension on _ExerciseDetailTab {
  String get label {
    switch (this) {
      case _ExerciseDetailTab.execution:
        return 'Execution';
      case _ExerciseDetailTab.target:
        return 'Target';
      case _ExerciseDetailTab.trends:
        return 'Trends';
    }
  }

  String get icon {
    switch (this) {
      case _ExerciseDetailTab.execution:
        return MynauiGlyphs.stretchingRound;
      case _ExerciseDetailTab.target:
        return MynauiGlyphs.target;
      case _ExerciseDetailTab.trends:
        return MynauiGlyphs.trends;
    }
  }
}

class ExerciseDetailPage extends StatefulWidget {
  const ExerciseDetailPage({super.key, required this.exerciseName});

  final String exerciseName;

  @override
  State<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends State<ExerciseDetailPage> {
  final ScrollController _scrollController = ScrollController();

  _ExerciseDetailTab _selectedTab = _ExerciseDetailTab.execution;
  LegDayTrendRange _selectedTrendRange = LegDayTrendRange.thirtyDays;
  LegDayTrendMetric _selectedTrendMetric = LegDayTrendMetric.volume;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final data = ExerciseDetailMockData.forExercise(widget.exerciseName);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    const headerLeadingInset = 62.0;
    const sectionGap = 24.0;
    final topTags = <String>[
      data.exerciseType,
      data.equipmentLabel,
      data.difficulty,
      if (data.primaryMuscles.isNotEmpty) data.primaryMuscles.first,
    ];
    final listBottomPadding = bottomInset + 28;
    final listTopPadding = topInset + islandTop;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                kPagePadding,
                listTopPadding,
                kPagePadding,
                listBottomPadding,
              ),
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: headerLeadingInset),
                      Expanded(
                        child: Text(
                          data.exerciseName,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1.02,
                            letterSpacing: -1.1,
                            color: Color(0xFF111111),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Movement breakdown, muscle focus, and coaching cues in one place.',
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: Colors.black.withValues(alpha: 0.56),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topTags
                      .map((tag) => _ExerciseInfoChip(label: tag))
                      .toList(growable: false),
                ),
                const SizedBox(height: 20),
                _ExerciseDetailTabBar(
                  selectedTab: _selectedTab,
                  onTabSelected: (tab) {
                    setState(() => _selectedTab = tab);
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                ),
                const SizedBox(height: sectionGap),
                ...switch (_selectedTab) {
                  _ExerciseDetailTab.execution => _buildExecutionTab(data),
                  _ExerciseDetailTab.target => _buildTargetTab(data),
                  _ExerciseDetailTab.trends => _buildTrendsTab(data),
                },
              ],
            ),
            Positioned(
              top: topInset + islandTop,
              left: kPagePadding,
              child: _ExerciseBackPill(
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExecutionTab(ExerciseDetailData data) {
    return [
      _ExerciseSectionTitle(
        title: 'Execution',
        subtitle: 'Preview the movement and key setup before you load it.',
        subtitleFontSize: 12.5,
        subtitleMaxLines: 1,
      ),
      const SizedBox(height: 12),
      _ExerciseHeroCard(
        imageUrl: data.mediaImageUrl,
        onPlay:
            () => _showMessage(
              'Execution video playback is the next hookup on this screen.',
            ),
      ),
      const SizedBox(height: 16),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.summary,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.black.withValues(alpha: 0.74),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            _ExerciseMetaTile(
              label: 'Exercise type',
              value: data.exerciseType,
              icon: Icons.auto_awesome_motion_rounded,
              accent: const Color(0xFFFF902B),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _ExerciseSectionTitle(title: 'Equipment'),
      const SizedBox(height: 12),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: _EquipmentRow(
          imageUrl: data.mediaImageUrl,
          label: data.equipmentLabel,
        ),
      ),
      const SizedBox(height: 24),
      const _ExerciseSectionTitle(
        title: 'How to perform',
        subtitle: 'Sequence, setup, and rep execution cues.',
      ),
      const SizedBox(height: 12),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: Column(
          children: [
            for (
              var index = 0;
              index < data.instructions.length;
              index += 1
            ) ...[
              _InstructionRow(index: index + 1, text: data.instructions[index]),
              if (index != data.instructions.length - 1)
                const SizedBox(height: 14),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _ExerciseSectionTitle(
        title: 'Coaching tips',
        subtitle: 'Simple cues worth keeping in mind during harder sets.',
      ),
      const SizedBox(height: 12),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: Column(
          children: [
            for (
              var index = 0;
              index < data.coachingTips.length;
              index += 1
            ) ...[
              _CoachingTipRow(text: data.coachingTips[index]),
              if (index != data.coachingTips.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildTargetTab(ExerciseDetailData data) {
    return [
      const _ExerciseSectionTitle(
        title: 'Target muscles',
        subtitle:
            'Primary drivers and the supporting muscles that stabilise the pattern.',
      ),
      const SizedBox(height: 12),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final muscleList = _MuscleGroupSummary(
              primaryMuscles: data.primaryMuscles,
              secondaryMuscles: data.secondaryMuscles,
            );
            final mannequin = SizedBox(
              height: compact ? 284 : 318,
              child: WorkoutTargetMannequinPanel(
                highlightedRegions: data.highlightedRegions,
                bodyType: LowerBodyMannequinBodyType.male,
                regionStates: data.regionStates,
                pulsateHighlights: true,
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [muscleList, const SizedBox(height: 16), mannequin],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 132, child: muscleList),
                const SizedBox(width: 14),
                Expanded(child: mannequin),
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 24),
      const _ExerciseSectionTitle(
        title: 'Advanced targeting',
        subtitle: 'Relative emphasis across the main tissues this lift loads.',
      ),
      const SizedBox(height: 12),
      SectionBoundary(
        borderRadius: kIosCornerRadius,
        child: Column(
          children: [
            for (var index = 0; index < data.targeting.length; index += 1) ...[
              _TargetingRow(entry: data.targeting[index]),
              if (index != data.targeting.length - 1)
                const SizedBox(height: 18),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      const _ExerciseSectionTitle(
        title: 'Related exercises',
        subtitle:
            'Similar patterns if you want a close substitute or variation.',
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 262,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: data.relatedExercises.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            final exercise = data.relatedExercises[index];
            return _RelatedExerciseCard(
              exercise: exercise,
              onTap:
                  () => pushExerciseDetailPage(
                    context,
                    exerciseName: exercise.name,
                  ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildTrendsTab(ExerciseDetailData data) {
    final stats = ExerciseStatsMockData.forExercise(data.exerciseName);
    final snapshot = stats.snapshotFor(_selectedTrendRange);
    return [
      _ExerciseSectionTitle(title: 'Trends', subtitle: stats.subtitle),
      const SizedBox(height: 12),
      _ExerciseTrendSnapshotCard(summary: stats.summary),
      const SizedBox(height: 12),
      LegDayRangeSelector(
        selectedRange: _selectedTrendRange,
        onChanged: (range) => setState(() => _selectedTrendRange = range),
        accentColor: const Color(0xFF171717),
      ),
      const SizedBox(height: 16),
      PrimaryTrendCard(
        snapshot: snapshot,
        selectedMetric: _selectedTrendMetric,
        onMetricChanged:
            (metric) => setState(() => _selectedTrendMetric = metric),
        accentColor: const Color(0xFF171717),
      ),
    ];
  }
}

class _ExerciseBackPill extends StatelessWidget {
  const _ExerciseBackPill({required this.onTap});

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
                size: 22,
                color: kLiftIslandOnFrosted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseInfoChip extends StatelessWidget {
  const _ExerciseInfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEEEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.72),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ExerciseDetailTabBar extends StatelessWidget {
  const _ExerciseDetailTabBar({
    required this.selectedTab,
    required this.onTabSelected,
  });

  final _ExerciseDetailTab selectedTab;
  final ValueChanged<_ExerciseDetailTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _ExerciseDetailTab.values.indexed
          .map((entry) {
            final index = entry.$1;
            final tab = entry.$2;
            final selected = tab == selectedTab;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == _ExerciseDetailTab.values.length - 1 ? 0 : 10,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTabSelected(tab),
                    borderRadius: BorderRadius.circular(22),
                    child: AnimatedContainer(
                      duration: LiftMotion.fast,
                      curve: LiftMotion.standardCurve,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color:
                            selected ? const Color(0xFF171717) : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color:
                              selected
                                  ? const Color(0xFF171717)
                                  : Colors.black.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: selected ? 0.10 : 0.04,
                            ),
                            blurRadius: selected ? 18 : 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MynauiIcon(
                            tab.icon,
                            size: 18,
                            color:
                                selected
                                    ? Colors.white
                                    : const Color(0xFF495057),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tab.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                              color:
                                  selected
                                      ? Colors.white
                                      : const Color(0xFF2E3134),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ExerciseSectionTitle extends StatelessWidget {
  const _ExerciseSectionTitle({
    required this.title,
    this.subtitle,
    this.subtitleFontSize = 14,
    this.subtitleMaxLines,
  });

  final String title;
  final String? subtitle;
  final double subtitleFontSize;
  final int? subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: Color(0xFF111111),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: subtitleMaxLines,
            overflow:
                subtitleMaxLines == null
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: subtitleFontSize,
              height: 1.45,
              color: Colors.black.withValues(alpha: 0.52),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExerciseHeroCard extends StatelessWidget {
  const _ExerciseHeroCard({required this.imageUrl, required this.onPlay});

  final String imageUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1.08,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder:
                    (_, __, ___) => ColoredBox(
                      color: Colors.grey.shade100,
                      child: MynauiIcon(
                        MynauiGlyphs.galleryMinimalistic,
                        color: Colors.grey.shade400,
                        size: 36,
                      ),
                    ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0.14),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlay,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFE3CF).withValues(alpha: 0.88),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseMetaTile extends StatelessWidget {
  const _ExerciseMetaTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(kIosControlRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF151515),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.black.withValues(alpha: 0.48),
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

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({required this.imageUrl, required this.label});

  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 68,
            height: 68,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder:
                  (_, __, ___) => ColoredBox(
                    color: Colors.grey.shade100,
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: Colors.grey.shade400,
                    ),
                  ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedExerciseCard extends StatelessWidget {
  const _RelatedExerciseCard({required this.exercise, required this.onTap});

  final ExerciseRelatedExercise exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kIosCornerRadius),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(kIosCornerRadius),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox.expand(
                        child: Image.network(
                          exercise.imageUrl,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder:
                              (_, __, ___) => ColoredBox(
                                color: Colors.grey.shade100,
                                child: MynauiIcon(
                                  MynauiGlyphs.galleryMinimalistic,
                                  color: Colors.grey.shade400,
                                  size: 28,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    exercise.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Color(0xFF141414),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${exercise.muscleGroups.join(' • ')}  •  ${exercise.equipmentLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.loggedSetCount} sets logged',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.black.withValues(alpha: 0.42),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MuscleGroupSummary extends StatelessWidget {
  const _MuscleGroupSummary({
    required this.primaryMuscles,
    required this.secondaryMuscles,
  });

  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Primary',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121212),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: primaryMuscles
              .map((muscle) => _MuscleChip(label: muscle, primary: true))
              .toList(growable: false),
        ),
        if (secondaryMuscles.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Secondary',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: secondaryMuscles
                .map((muscle) => _MuscleChip(label: muscle, primary: false))
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({required this.label, required this.primary});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color =
        primary
            ? const Color(0xFF171717)
            : Colors.black.withValues(alpha: 0.56);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            primary
                ? const Color(0xFF171717).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(kIosChipRadius),
        border: Border.all(
          color:
              primary
                  ? const Color(0xFF171717).withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}

class _TargetingRow extends StatelessWidget {
  const _TargetingRow({required this.entry});

  final ExerciseTargetingEntry entry;

  @override
  Widget build(BuildContext context) {
    final normalized = (entry.scoreOutOfTen / 10).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
            ),
            Text(
              '${entry.scoreOutOfTen}/10',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black.withValues(alpha: 0.36),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: normalized,
            minHeight: 10,
            backgroundColor: Colors.black.withValues(alpha: 0.06),
            color: const Color(0xFF9DDC3A),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          entry.details,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: Colors.black.withValues(alpha: 0.46),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.42,
              color: Color(0xFF171717),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoachingTipRow extends StatelessWidget {
  const _CoachingTipRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              color: Color(0xFF171717),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseTrendSnapshotCard extends StatelessWidget {
  const _ExerciseTrendSnapshotCard({required this.summary});

  final ExerciseStatsSummary summary;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Row(
        children: [
          Expanded(
            child: _ExerciseTrendMiniStat(
              icon: MynauiGlyphs.clipboardList,
              label: 'Sessions',
              value: '${summary.sessionsWithExercise}',
              accent: const Color(0xFF171717),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExerciseTrendMiniStat(
              icon: MynauiGlyphs.weightlifting,
              label: 'Best set',
              value: summary.bestRecentSet,
              accent: const Color(0xFF171717),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExerciseTrendMiniStat(
              icon: MynauiGlyphs.calendar,
              label: 'Last done',
              value: summary.lastPerformedLabel,
              accent: const Color(0xFF171717),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseTrendMiniStat extends StatelessWidget {
  const _ExerciseTrendMiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final String icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: MynauiIcon(icon, size: 17, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.46),
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/machines/machine_scan_flow_screen.dart';
import 'package:lift/features/machines/mock_machines.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_page.dart';
import 'package:lift/features/settings/settings_screen.dart';
import 'package:lift/features/workout/exercise_details/exercise_detail_page.dart';
import 'package:lift/features/workout/live_workout_screen.dart';
import 'package:lift/features/workout/mock_workout_templates.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/exercise_demo_images.dart';
import 'package:lift/shared/models/workout_template.dart';
import 'package:lift/shared/widgets/lift_dialogs.dart';
import 'package:lift/shared/widgets/lower_body_mannequin_panel.dart';
import 'package:lift/shared/widgets/workout_detail_action_island.dart';
import 'package:lift/shared/widgets/lift_list_pagination.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:lift/shared/widgets/workout_template_hero_image.dart';
import 'package:lift/shared/widgets/workout_target_mannequin_panel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

enum _WorkoutTemplatesMode { overview, list, detail, editor, live }

enum _TemplateDetailMenuAction { edit, review, share, delete }

enum _WorkoutDurationFilter { any, under45, between45And60, over60 }

enum WorkoutFlowRouteTarget { list, detail, editor, live }

extension _WorkoutDurationFilterX on _WorkoutDurationFilter {
  String get label {
    switch (this) {
      case _WorkoutDurationFilter.any:
        return 'Any length';
      case _WorkoutDurationFilter.under45:
        return 'Under 45 min';
      case _WorkoutDurationFilter.between45And60:
        return '45-60 min';
      case _WorkoutDurationFilter.over60:
        return '60+ min';
    }
  }

  bool matches(int minutes) {
    switch (this) {
      case _WorkoutDurationFilter.any:
        return true;
      case _WorkoutDurationFilter.under45:
        return minutes < 45;
      case _WorkoutDurationFilter.between45And60:
        return minutes >= 45 && minutes <= 60;
      case _WorkoutDurationFilter.over60:
        return minutes > 60;
    }
  }
}

class _WorkoutListFilters {
  const _WorkoutListFilters({
    this.focusTags = const <String>{},
    this.duration = _WorkoutDurationFilter.any,
  });

  final Set<String> focusTags;
  final _WorkoutDurationFilter duration;

  bool get hasActiveFilters =>
      focusTags.isNotEmpty || duration != _WorkoutDurationFilter.any;

  int get activeCount =>
      focusTags.length + (duration == _WorkoutDurationFilter.any ? 0 : 1);

  bool matches(WorkoutTemplate template) {
    final matchesTags =
        focusTags.isEmpty ||
        template.focusTags.any((tag) => focusTags.contains(tag));
    final matchesDuration = duration.matches(template.estimatedDurationMinutes);
    return matchesTags && matchesDuration;
  }

  _WorkoutListFilters copyWith({
    Set<String>? focusTags,
    _WorkoutDurationFilter? duration,
  }) {
    return _WorkoutListFilters(
      focusTags: focusTags ?? this.focusTags,
      duration: duration ?? this.duration,
    );
  }
}

Widget _alignedWorkoutBackIcon({
  Color color = kLiftIslandOnFrosted,
  double size = 22,
}) {
  return MynauiIcon(MynauiGlyphs.altArrowLeft, color: color, size: size);
}

class _WorkoutSummaryMuscleEntry {
  const _WorkoutSummaryMuscleEntry({
    required this.label,
    this.volumeKg,
    this.isFallback = false,
  });

  final String label;
  final double? volumeKg;
  final bool isFallback;
}

class _WorkoutSummaryDialogContent extends StatelessWidget {
  const _WorkoutSummaryDialogContent({
    required this.summary,
    required this.workedMuscles,
    required this.usesFallbackTargetMap,
    required this.formatDuration,
    required this.formatVolume,
    required this.onShare,
  });

  final LiveWorkoutSummaryState summary;
  final List<_WorkoutSummaryMuscleEntry> workedMuscles;
  final bool usesFallbackTargetMap;
  final String Function(Duration duration) formatDuration;
  final String Function(double volumeKg) formatVolume;
  final VoidCallback onShare;

  static const Color _accent = Color(0xFF2C6A4B);
  static const Color _warmAccent = Color(0xFFF2C7A9);

  WorkoutTargetHighlightState _highlightStateForEntry(
    _WorkoutSummaryMuscleEntry entry,
    double maxVolume,
  ) {
    if (entry.isFallback || maxVolume <= 0 || entry.volumeKg == null) {
      return WorkoutTargetHighlightState.mid;
    }
    final ratio = entry.volumeKg! / maxVolume;
    if (ratio >= 0.66) return WorkoutTargetHighlightState.fatigued;
    if (ratio >= 0.34) return WorkoutTargetHighlightState.mid;
    return WorkoutTargetHighlightState.recovered;
  }

  int _highlightPriority(WorkoutTargetHighlightState state) {
    switch (state) {
      case WorkoutTargetHighlightState.recovered:
        return 0;
      case WorkoutTargetHighlightState.mid:
        return 1;
      case WorkoutTargetHighlightState.fatigued:
        return 2;
    }
  }

  String _formatCompletionStamp(BuildContext context) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(summary.completedAt));
    final now = DateTime.now();
    final isToday =
        now.year == summary.completedAt.year &&
        now.month == summary.completedAt.month &&
        now.day == summary.completedAt.day;
    if (isToday) return 'Today • $time';
    return '${summary.completedAt.day}/${summary.completedAt.month} • $time';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxDialogHeight = math.min(screenHeight - 86, 760.0);
    final compactLayout = maxDialogHeight < 780;
    final ultraCompactLayout = maxDialogHeight < 700;
    final shellRadiusValue = ultraCompactLayout ? 30.0 : 34.0;
    final shellRadius = BorderRadius.circular(shellRadiusValue);
    final summaryPillRadius = ultraCompactLayout ? 20.0 : 22.0;
    final metricCardRadius = ultraCompactLayout ? 26.0 : 28.0;
    final actionButtonRadius = ultraCompactLayout ? 28.0 : 30.0;
    final mannequinCardRadius = ultraCompactLayout ? 28.0 : 30.0;
    final heroPadding = ultraCompactLayout ? 14.0 : 16.0;
    final heroTitleSize = ultraCompactLayout ? 24.0 : 28.0;
    final floatingButtonHeight = compactLayout ? 50.0 : 54.0;
    final contentSideInset = ultraCompactLayout ? 18.0 : 20.0;
    final contentTopInset = ultraCompactLayout ? 20.0 : 22.0;
    final sectionGap = ultraCompactLayout ? 10.0 : 14.0;
    final maxTrackedVolume = workedMuscles.fold<double>(
      0,
      (currentMax, muscle) => math.max(currentMax, muscle.volumeKg ?? 0),
    );
    final highlightedRegions = workoutTargetRegionsForLabels(
      workedMuscles.map((entry) => entry.label),
    );
    final regionStates = <WorkoutTargetRegion, WorkoutTargetHighlightState>{};

    for (final entry in workedMuscles) {
      final nextState = _highlightStateForEntry(entry, maxTrackedVolume);
      for (final region in workoutTargetRegionsForLabels([entry.label])) {
        final current = regionStates[region];
        if (current == null ||
            _highlightPriority(nextState) >= _highlightPriority(current)) {
          regionStates[region] = nextState;
        }
      }
    }

    return SizedBox(
      height: maxDialogHeight,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: shellRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 34,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: shellRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shellRadius,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF16231D),
                    Color(0xFF234439),
                    Color(0xFF416B58),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  contentSideInset,
                  contentTopInset,
                  contentSideInset,
                  compactLayout ? 12 : 14,
                ),
                child: Column(
                  children: [
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: ultraCompactLayout ? 10 : 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(heroPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ultraCompactLayout ? 8 : 10,
                                    vertical: ultraCompactLayout ? 5 : 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      summaryPillRadius,
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: ultraCompactLayout ? 14 : 15,
                                        color: const Color(0xFFB7E4C7),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Workout summary',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.92,
                                          ),
                                          fontSize:
                                              ultraCompactLayout ? 11.5 : 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _formatCompletionStamp(context),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: ultraCompactLayout ? 12.0 : 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: ultraCompactLayout ? 12 : 16),
                            Text(
                              summary.workoutName,
                              style: TextStyle(
                                fontSize: heroTitleSize,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.9,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: ultraCompactLayout ? 4 : 6),
                            Text(
                              summary.exercisesCompleted > 0
                                  ? '${summary.exercisesCompleted} of ${summary.totalExercises} exercises completed'
                                  : 'Session closed without any completed sets logged',
                              style: TextStyle(
                                fontSize: ultraCompactLayout ? 12.5 : 13.5,
                                height: 1.22,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                            SizedBox(height: sectionGap),
                            Row(
                              children: [
                                Expanded(
                                  child: _WorkoutSummaryMetricCard(
                                    icon: Icons.schedule_rounded,
                                    label: 'Duration',
                                    value:
                                        formatDuration(
                                          summary.elapsed,
                                        ).toUpperCase(),
                                    compact: compactLayout,
                                    cornerRadius: metricCardRadius,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _WorkoutSummaryMetricCard(
                                    icon: Icons.local_fire_department_rounded,
                                    label: 'Calories',
                                    value:
                                        '${summary.estimatedCaloriesBurned} CAL',
                                    tint: _warmAccent,
                                    compact: compactLayout,
                                    cornerRadius: metricCardRadius,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _WorkoutSummaryMetricCard(
                                    icon: Icons.bolt_rounded,
                                    label: 'Training score',
                                    value: '${summary.trainingScore}/100',
                                    compact: compactLayout,
                                    cornerRadius: metricCardRadius,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _WorkoutSummaryMetricCard(
                                    icon: Icons.speed_rounded,
                                    label: 'Intensity',
                                    value:
                                        summary.workoutIntensityLabel
                                            .toUpperCase(),
                                    compact: compactLayout,
                                    cornerRadius: metricCardRadius,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _WorkoutSummaryHeroPill(
                                  icon: Icons.fitness_center_rounded,
                                  label:
                                      '${summary.exercisesCompleted}/${summary.totalExercises} complete',
                                  compact: compactLayout,
                                  cornerRadius: summaryPillRadius,
                                ),
                                _WorkoutSummaryHeroPill(
                                  icon: Icons.repeat_rounded,
                                  label: '${summary.totalReps} reps',
                                  compact: compactLayout,
                                  cornerRadius: summaryPillRadius,
                                ),
                                _WorkoutSummaryHeroPill(
                                  icon: Icons.local_fire_department_rounded,
                                  label: formatVolume(summary.totalVolumeKg),
                                  tint: _warmAccent,
                                  compact: compactLayout,
                                  cornerRadius: summaryPillRadius,
                                ),
                              ],
                            ),
                            SizedBox(height: sectionGap),
                            Text(
                              usesFallbackTargetMap
                                  ? 'Target map'
                                  : 'Worked muscles',
                              style: TextStyle(
                                fontSize: ultraCompactLayout ? 16 : 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: ultraCompactLayout ? 8 : 10),
                            Expanded(
                              child: WorkoutTargetMannequinPanel(
                                highlightedRegions: highlightedRegions,
                                bodyType: LowerBodyMannequinBodyType.male,
                                highlightColor: _accent,
                                regionStates: regionStates,
                                pulsateHighlights: true,
                                cardCornerRadius: mannequinCardRadius,
                                showViewLabels: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: ultraCompactLayout ? 10 : 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onShare,
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size.fromHeight(
                                floatingButtonHeight,
                              ),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.72,
                              ),
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  actionButtonRadius,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              height: 24,
                              child: Stack(
                                alignment: Alignment.center,
                                children: const [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: MynauiIcon(
                                      MynauiGlyphs.squareShareLine,
                                      size: 18,
                                      color: Color(0xFF161616),
                                    ),
                                  ),
                                  Text(
                                    'Share',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF161616),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              minimumSize: Size.fromHeight(
                                floatingButtonHeight,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  actionButtonRadius,
                                ),
                              ),
                              elevation: 6,
                              shadowColor: Colors.black.withValues(alpha: 0.18),
                            ),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkoutSummaryHeroPill extends StatelessWidget {
  const _WorkoutSummaryHeroPill({
    required this.icon,
    required this.label,
    this.tint = Colors.white,
    this.compact = false,
    this.cornerRadius = kIosChipRadius,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool compact;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 14 : 15,
            color: tint.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutSummaryMetricCard extends StatelessWidget {
  const _WorkoutSummaryMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.tint = Colors.white,
    this.compact = false,
    this.cornerRadius = 22,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final bool compact;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 11 : 12,
        compact ? 11 : 12,
        compact ? 11 : 12,
        compact ? 11 : 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: compact ? 15 : 16,
                color: tint.withValues(alpha: 0.94),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: compact ? 9.5 : 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: compact ? 16.5 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

String _workoutTargetRegionLabel(WorkoutTargetRegion region) {
  switch (region) {
    case WorkoutTargetRegion.shoulders:
      return 'Shoulders';
    case WorkoutTargetRegion.chest:
      return 'Chest';
    case WorkoutTargetRegion.abs:
      return 'Core';
    case WorkoutTargetRegion.back:
      return 'Back';
    case WorkoutTargetRegion.lats:
      return 'Lats';
    case WorkoutTargetRegion.biceps:
      return 'Biceps';
    case WorkoutTargetRegion.triceps:
      return 'Triceps';
    case WorkoutTargetRegion.forearms:
      return 'Forearms';
    case WorkoutTargetRegion.glutes:
      return 'Glutes';
    case WorkoutTargetRegion.quads:
      return 'Quads';
    case WorkoutTargetRegion.hamstrings:
      return 'Hamstrings';
    case WorkoutTargetRegion.calves:
      return 'Calves';
  }
}

_SwapExerciseCatalogItem? _summaryCatalogItemForExerciseName(String name) {
  final needle = name.trim().toLowerCase();
  for (final item in _kSwapExerciseCatalog) {
    if (item.name.toLowerCase() == needle) return item;
  }
  for (final item in _kSwapExerciseCatalog) {
    if (item.name.toLowerCase().contains(needle) ||
        needle.contains(item.name.toLowerCase())) {
      return item;
    }
  }
  return null;
}

List<String> _summaryHeuristicMuscleTagsForName(String rawName) {
  final name = rawName.toLowerCase();
  final tags = <String>{};
  final isForearmFocused =
      name.contains('forearm') ||
      name.contains('wrist') ||
      name.contains('grip') ||
      name.contains('farmer') ||
      name.contains('reverse curl') ||
      name.contains('pronation') ||
      name.contains('supination');
  if (name.contains('ham')) tags.add('Hamstrings');
  if (name.contains('quad') ||
      name.contains('leg press') ||
      name.contains('squat') ||
      name.contains('leg extension')) {
    tags.add('Quads');
  }
  if (name.contains('glute') ||
      name.contains('leg press') ||
      name.contains('hip')) {
    tags.add('Glutes');
  }
  if (name.contains('lat') || name.contains('row') || name.contains('pull')) {
    tags.add('Back');
  }
  if (isForearmFocused) {
    tags.add('Forearms');
  }
  if ((name.contains('bicep') ||
          (name.contains('curl') && !name.contains('ham'))) &&
      !isForearmFocused &&
      !name.contains('tricep')) {
    tags.add('Biceps');
  }
  if (name.contains('press') && !name.contains('leg')) {
    tags.add('Chest');
  }
  if (name.contains('shoulder') || name.contains('lateral')) {
    tags.add('Shoulders');
  }
  if (name.contains('tricep') ||
      name.contains('pushdown') ||
      name.contains('skull crusher') ||
      name.contains('overhead extension') ||
      name.contains('dip')) {
    tags.add('Triceps');
  }
  if (name.contains('ab') || name.contains('core') || name.contains('plank')) {
    tags.add('Core');
  }
  if (name.contains('cardio') ||
      name.contains('walk') ||
      name.contains('run')) {
    tags.add('Conditioning');
  }
  return tags.toList();
}

class WorkoutFlowCommand {
  const WorkoutFlowCommand({
    required this.id,
    required this.target,
    this.templateId,
  });

  final String id;
  final WorkoutFlowRouteTarget target;
  final String? templateId;
}

enum _SwapExerciseEquipment { machine, barbell, dumbbell, cables, bodyweight }

extension _SwapExerciseEquipmentX on _SwapExerciseEquipment {
  String get label {
    switch (this) {
      case _SwapExerciseEquipment.machine:
        return 'Machines';
      case _SwapExerciseEquipment.barbell:
        return 'Barbell';
      case _SwapExerciseEquipment.dumbbell:
        return 'Dumbbell';
      case _SwapExerciseEquipment.cables:
        return 'Cables';
      case _SwapExerciseEquipment.bodyweight:
        return 'Bodyweight';
    }
  }
}

class _SwapExerciseCatalogItem {
  const _SwapExerciseCatalogItem({
    required this.name,
    required this.muscleGroups,
    required this.equipment,
    this.keywords = const <String>[],
  });

  final String name;
  final List<String> muscleGroups;
  final _SwapExerciseEquipment equipment;
  final List<String> keywords;
}

const List<_SwapExerciseCatalogItem> _kSwapExerciseCatalog = [
  _SwapExerciseCatalogItem(
    name: 'Leg Press',
    muscleGroups: ['Quads', 'Glutes'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['leg', 'press', 'quad'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Hamstring Curls',
    muscleGroups: ['Hamstrings'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['hamstring', 'curl', 'leg'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Leg Extension',
    muscleGroups: ['Quads'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['leg', 'extension', 'quad'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Barbell Back Squat',
    muscleGroups: ['Quads', 'Glutes'],
    equipment: _SwapExerciseEquipment.barbell,
    keywords: ['squat', 'barbell', 'leg'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Romanian Deadlift',
    muscleGroups: ['Hamstrings', 'Glutes'],
    equipment: _SwapExerciseEquipment.barbell,
    keywords: ['hinge', 'hamstring', 'deadlift', 'barbell'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Dumbbell Lunges',
    muscleGroups: ['Quads', 'Glutes'],
    equipment: _SwapExerciseEquipment.dumbbell,
    keywords: ['lunge', 'dumbbell', 'leg'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Standing Calf Raise',
    muscleGroups: ['Calves'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['calf', 'raise', 'standing', 'lower leg'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Lat Pulldown',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.cables,
    keywords: ['lat', 'pull', 'back'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Seated Row',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.cables,
    keywords: ['row', 'back', 'pull'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Single Arm Row',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['row', 'single', 'arm', 'back', 'unilateral'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Wide Grip Row',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['row', 'wide', 'grip', 'back'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Neutral Grip Row',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['row', 'neutral', 'grip', 'back'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Cable Face Pull',
    muscleGroups: ['Back', 'Shoulders'],
    equipment: _SwapExerciseEquipment.cables,
    keywords: ['face', 'pull', 'rear'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Pull Up',
    muscleGroups: ['Back', 'Biceps'],
    equipment: _SwapExerciseEquipment.bodyweight,
    keywords: ['pull', 'up', 'back'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Wrist Curl',
    muscleGroups: ['Forearms'],
    equipment: _SwapExerciseEquipment.dumbbell,
    keywords: ['wrist', 'curl', 'forearm', 'grip'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Chest Press',
    muscleGroups: ['Chest', 'Triceps'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['chest', 'press', 'push'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Shoulder Press',
    muscleGroups: ['Shoulders', 'Triceps'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['shoulder', 'press', 'push'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Lateral Raise',
    muscleGroups: ['Shoulders'],
    equipment: _SwapExerciseEquipment.dumbbell,
    keywords: ['lateral', 'raise', 'shoulder'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Tricep Pushdown',
    muscleGroups: ['Triceps'],
    equipment: _SwapExerciseEquipment.cables,
    keywords: ['tricep', 'pushdown', 'cable'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Bench Press',
    muscleGroups: ['Chest', 'Triceps'],
    equipment: _SwapExerciseEquipment.barbell,
    keywords: ['bench', 'press', 'chest'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Dumbbell Incline Press',
    muscleGroups: ['Chest', 'Shoulders', 'Triceps'],
    equipment: _SwapExerciseEquipment.dumbbell,
    keywords: ['incline', 'press', 'chest'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Push Up',
    muscleGroups: ['Chest', 'Shoulders', 'Triceps'],
    equipment: _SwapExerciseEquipment.bodyweight,
    keywords: ['push', 'up', 'chest'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Ab Crunch Machine',
    muscleGroups: ['Core'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['ab', 'crunch', 'core'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Cable Woodchop',
    muscleGroups: ['Core'],
    equipment: _SwapExerciseEquipment.cables,
    keywords: ['core', 'rotation', 'cable'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Plank',
    muscleGroups: ['Core'],
    equipment: _SwapExerciseEquipment.bodyweight,
    keywords: ['plank', 'core'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Incline Walk',
    muscleGroups: ['Conditioning'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['walk', 'cardio', 'conditioning'],
  ),
  _SwapExerciseCatalogItem(
    name: 'Row Erg',
    muscleGroups: ['Conditioning', 'Back'],
    equipment: _SwapExerciseEquipment.machine,
    keywords: ['row', 'cardio', 'conditioning'],
  ),
];

class WorkoutTemplatesFlow extends StatefulWidget {
  const WorkoutTemplatesFlow({
    super.key,
    this.onLiveDockChanged,
    this.onLiveFullscreenChanged,
    this.onWorkoutCompleted,
    this.onHideShellNavChanged,
    this.initialTemplateId,
    this.externalCommand,
    this.onExternalCommandHandled,
    this.onLeadingTap,
    this.popOnBackFromDetail = false,
    this.popOnBackFromList = false,
    this.startInList = false,
    this.showRootBack = false,
    this.onRootBack,
    this.showRootProfileAction = true,
  });

  final ValueChanged<WorkoutLiveDockHandle?>? onLiveDockChanged;
  final ValueChanged<WorkoutLiveFullscreenHandle?>? onLiveFullscreenChanged;
  final ValueChanged<WorkoutHistoryEntry>? onWorkoutCompleted;
  final ValueChanged<bool>? onHideShellNavChanged;
  final String? initialTemplateId;
  final WorkoutFlowCommand? externalCommand;
  final ValueChanged<String>? onExternalCommandHandled;
  final VoidCallback? onLeadingTap;
  final bool popOnBackFromDetail;
  final bool popOnBackFromList;
  final bool startInList;
  final bool showRootBack;
  final VoidCallback? onRootBack;
  final bool showRootProfileAction;

  @override
  State<WorkoutTemplatesFlow> createState() => _WorkoutTemplatesFlowState();
}

class WorkoutLiveDockHandle {
  const WorkoutLiveDockHandle({required this.state, required this.onResume});

  final LiveWorkoutMiniState state;
  final VoidCallback onResume;
}

class WorkoutLiveFullscreenHandle {
  const WorkoutLiveFullscreenHandle({
    required this.onDiscard,
    required this.onComplete,
  });

  final VoidCallback onDiscard;
  final VoidCallback onComplete;
}

class _WorkoutTemplatesFlowState extends State<WorkoutTemplatesFlow> {
  late List<WorkoutTemplate> _templates;
  _WorkoutTemplatesMode _mode = _WorkoutTemplatesMode.overview;
  _WorkoutTemplatesMode _editorReturnMode = _WorkoutTemplatesMode.list;

  /// Shell content behind fullscreen live; also where minimize/collapse returns.
  _WorkoutTemplatesMode _liveReturnMode = _WorkoutTemplatesMode.overview;

  /// Last overview vs list before opening template detail (start-workout return target).
  _WorkoutTemplatesMode _detailBrowseOrigin = _WorkoutTemplatesMode.overview;
  String? _selectedTemplateId;
  WorkoutTemplate? _activeLiveTemplate;
  LiveWorkoutMiniState? _liveMiniState;
  LiveWorkoutSummaryState? _liveSummaryState;

  /// One key per live session so [LiveWorkoutScreen] state survives rebuilds
  /// (collapse/expand, padding changes, parent Stack) without duplicating widgets.
  GlobalKey? _liveWorkoutKey;
  String _searchQuery = '';
  _WorkoutListFilters _listFilters = const _WorkoutListFilters();
  final Set<String> _expandedExerciseIds = <String>{};
  int _templateIdSeed = 100;
  int _exerciseIdSeed = 100;
  bool _isCompletingLiveWorkout = false;
  bool _isDiscardingLiveWorkout = false;
  bool? _lastPublishedHideShellNav;
  String? _lastHandledExternalCommandId;

  final ScrollController _templateDetailScrollController = ScrollController();
  final PageController _templateListPageController = PageController();
  final PageController _overviewPageController = PageController(
    viewportFraction: 0.66,
  );

  /// Tracks page size while the list mode is active so we can reset the page
  /// when switching between the shell and standalone row counts.
  int? _lastTemplateListPageSizeForList;
  int _templateListPageIndex = 0;

  /// Matches the gap below the create row when the live dock is visible
  /// ([_modeContentPadding] uses this + [WorkoutLiveDock.kExpandedVisualHeight]).
  static const double _kListCreateActionsVerticalGap = 14.0;

  void _selectTemplateForDetail(WorkoutTemplate template) {
    _selectedTemplateId = template.id;
    _expandedExerciseIds.clear();
    if (template.exercises.isNotEmpty) {
      _expandedExerciseIds.add(template.exercises.first.id);
    }
  }

  void _transitionToMode(
    _WorkoutTemplatesMode nextMode, {
    VoidCallback? update,
  }) {
    setState(() {
      update?.call();
      _mode = nextMode;
    });
  }

  @override
  void initState() {
    super.initState();
    _templates = List<WorkoutTemplate>.from(MockWorkoutTemplates.seed());
    if (widget.startInList) {
      _mode = _WorkoutTemplatesMode.list;
      _liveReturnMode = _WorkoutTemplatesMode.list;
      _detailBrowseOrigin = _WorkoutTemplatesMode.list;
    }
    final initialTemplate = _templateById(widget.initialTemplateId);
    if (initialTemplate != null) {
      _mode = _WorkoutTemplatesMode.detail;
      _selectTemplateForDetail(initialTemplate);
      _detailBrowseOrigin =
          widget.startInList
              ? _WorkoutTemplatesMode.list
              : _WorkoutTemplatesMode.overview;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.externalCommand != null) {
        _applyExternalCommand(widget.externalCommand);
      }
      _publishShellNavVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant WorkoutTemplatesFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalCommand?.id == oldWidget.externalCommand?.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyExternalCommand(widget.externalCommand);
    });
  }

  @override
  void dispose() {
    _templateDetailScrollController.dispose();
    _templateListPageController.dispose();
    _overviewPageController.dispose();
    widget.onLiveDockChanged?.call(null);
    widget.onLiveFullscreenChanged?.call(null);
    widget.onHideShellNavChanged?.call(false);
    super.dispose();
  }

  /// The shell workout tab has less vertical room because the bottom island is
  /// present; standalone routes can fit one extra workout row.
  bool get _hasBottomNavigationIsland => widget.onHideShellNavChanged != null;

  /// Rows per page: fewer when the live dock is visible, more when the screen
  /// is presented standalone without the shell bottom island.
  int get _templateListPageSize {
    if (_showLiveDock) return 4;
    return _hasBottomNavigationIsland ? 5 : 6;
  }

  List<WorkoutTemplate> get _filteredTemplates {
    final query = _searchQuery.trim().toLowerCase();
    return _templates.where((template) {
      final matchesQuery =
          query.isEmpty ||
          template.name.toLowerCase().contains(query) ||
          template.focusTags.any((tag) => tag.toLowerCase().contains(query)) ||
          template.exercises.any(
            (exercise) => exercise.name.toLowerCase().contains(query),
          );
      return matchesQuery && _listFilters.matches(template);
    }).toList();
  }

  List<String> get _availableWorkoutFocusTags {
    final ordered = <String>[];
    final seen = <String>{};
    for (final template in _templates) {
      for (final rawTag in template.focusTags) {
        final tag = rawTag.trim();
        if (tag.isEmpty) continue;
        final key = tag.toLowerCase();
        if (seen.add(key)) {
          ordered.add(tag);
        }
      }
    }
    return ordered;
  }

  Future<void> _openWorkoutFilters() async {
    final nextFilters = await showModalBottomSheet<_WorkoutListFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: _WorkoutFiltersSheet(
            initialFilters: _listFilters,
            availableFocusTags: _availableWorkoutFocusTags,
          ),
        );
      },
    );
    if (!mounted || nextFilters == null) return;
    setState(() => _listFilters = nextFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_templateListPageController.hasClients) {
        _templateListPageController.jumpToPage(0);
      }
    });
  }

  WorkoutTemplate? get _selectedTemplate {
    if (_selectedTemplateId == null) return null;
    for (final template in _templates) {
      if (template.id == _selectedTemplateId) return template;
    }
    return null;
  }

  WorkoutTemplate? _templateById(String? templateId) {
    if (templateId == null || templateId.trim().isEmpty) return null;
    for (final template in _templates) {
      if (template.id == templateId) return template;
    }
    return null;
  }

  void _applyExternalCommand(WorkoutFlowCommand? command) {
    if (command == null) return;
    if (_lastHandledExternalCommandId == command.id) return;
    _lastHandledExternalCommandId = command.id;

    final targetTemplate = _templateById(command.templateId);
    switch (command.target) {
      case WorkoutFlowRouteTarget.list:
        _openList();
        break;
      case WorkoutFlowRouteTarget.detail:
        if (targetTemplate != null) {
          _openDetail(targetTemplate);
        } else {
          _openList();
        }
        break;
      case WorkoutFlowRouteTarget.editor:
        if (targetTemplate != null) {
          _openEdit(targetTemplate);
        } else {
          _openCreate();
        }
        break;
      case WorkoutFlowRouteTarget.live:
        if (targetTemplate != null &&
            _hasActiveLiveWorkout &&
            _activeLiveTemplate?.id == targetTemplate.id) {
          _resumeLiveWorkout();
        } else if (targetTemplate != null) {
          _openLiveWorkout(targetTemplate);
        } else {
          _openList();
        }
        break;
    }
    widget.onExternalCommandHandled?.call(command.id);
  }

  bool get _hasActiveLiveWorkout => _activeLiveTemplate != null;

  /// Minimized live session with mini state. Only [onLiveDockChanged] hosts
  /// (e.g. the Workout tab) render the shell dock — pushed routes must keep the
  /// floating Start/Resume bar and must not reserve dock bottom inset.
  bool get _showLiveDock =>
      widget.onLiveDockChanged != null &&
      _hasActiveLiveWorkout &&
      _mode != _WorkoutTemplatesMode.live &&
      _liveMiniState != null;

  bool get _showLiveFullscreenActions =>
      _hasActiveLiveWorkout && _mode == _WorkoutTemplatesMode.live;

  void _publishLiveDockState() {
    final callback = widget.onLiveDockChanged;
    if (callback == null) return;
    if (_showLiveDock && _liveMiniState != null) {
      callback(
        WorkoutLiveDockHandle(
          state: _liveMiniState!,
          onResume: _resumeLiveWorkout,
        ),
      );
      return;
    }
    callback(null);
  }

  void _publishLiveFullscreenState() {
    final callback = widget.onLiveFullscreenChanged;
    if (callback == null) return;
    if (_showLiveFullscreenActions) {
      callback(
        WorkoutLiveFullscreenHandle(
          onDiscard: _discardLiveWorkout,
          onComplete: _completeLiveWorkout,
        ),
      );
      return;
    }
    callback(null);
  }

  void _publishLiveShellState() {
    _publishLiveDockState();
    _publishLiveFullscreenState();
    _publishShellNavVisibility();
  }

  bool get _shouldHideShellNav =>
      _mode == _WorkoutTemplatesMode.detail ||
      _mode == _WorkoutTemplatesMode.editor ||
      _mode == _WorkoutTemplatesMode.live;

  void _publishShellNavVisibility() {
    final shouldHide = _shouldHideShellNav;
    if (_lastPublishedHideShellNav == shouldHide) return;
    _lastPublishedHideShellNav = shouldHide;
    widget.onHideShellNavChanged?.call(shouldHide);
  }

  void _syncShellNavVisibilityFromBuild() {
    final callback = widget.onHideShellNavChanged;
    if (callback == null) return;
    final shouldHide = _shouldHideShellNav;
    if (_lastPublishedHideShellNav == shouldHide) return;
    _lastPublishedHideShellNav = shouldHide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(shouldHide);
    });
  }

  void _discardLiveWorkout() {
    if (_isDiscardingLiveWorkout) return;
    _discardLiveWorkoutAsync();
  }

  void _completeLiveWorkout() {
    if (_isCompletingLiveWorkout) return;
    _completeLiveWorkoutAsync();
  }

  Future<void> _discardLiveWorkoutAsync() async {
    final template = _activeLiveTemplate ?? _selectedTemplate;
    if (template == null) return;
    _isDiscardingLiveWorkout = true;
    try {
      final confirmed = await _confirmDiscardLiveWorkoutDialog();
      if (!confirmed || !mounted) return;
      final latestTemplate = _activeLiveTemplate ?? _selectedTemplate;
      if (latestTemplate == null) return;
      _transitionToMode(
        _WorkoutTemplatesMode.detail,
        update: () {
          _clearLiveWorkoutSession();
          _selectedTemplateId = latestTemplate.id;
        },
      );
      _publishLiveShellState();
    } finally {
      _isDiscardingLiveWorkout = false;
    }
  }

  Future<void> _completeLiveWorkoutAsync() async {
    final template = _activeLiveTemplate ?? _selectedTemplate;
    if (template == null) return;
    _isCompletingLiveWorkout = true;
    try {
      final confirmed = await _confirmCompleteLiveWorkoutDialog();
      if (!confirmed || !mounted) return;
      final summary = _liveSummaryState ?? _buildFallbackSummaryState(template);
      await _showWorkoutSummaryDialog(summary);
      if (!mounted) return;
      final historyEntry = _toHistoryEntry(summary, template);
      widget.onWorkoutCompleted?.call(historyEntry);
      final latestTemplate = _activeLiveTemplate ?? _selectedTemplate;
      if (latestTemplate == null) return;
      _transitionToMode(
        _WorkoutTemplatesMode.detail,
        update: () {
          _clearLiveWorkoutSession();
          _selectedTemplateId = latestTemplate.id;
        },
      );
      _publishLiveShellState();
    } finally {
      _isCompletingLiveWorkout = false;
    }
  }

  LiveWorkoutSummaryState _buildFallbackSummaryState(WorkoutTemplate template) {
    final completedAt = DateTime.now();
    return LiveWorkoutSummaryState(
      workoutName: template.name,
      startedAt: completedAt,
      completedAt: completedAt,
      elapsed: Duration.zero,
      totalVolumeKg: 0,
      totalReps: 0,
      exercisesCompleted: 0,
      totalExercises: template.exercises.length,
      prsAchieved: 0,
      exerciseSummaries: const <WorkoutHistoryExerciseSummary>[],
      muscleGroupVolumeKg: const <String, double>{},
    );
  }

  WorkoutHistoryEntry _toHistoryEntry(
    LiveWorkoutSummaryState summary,
    WorkoutTemplate template,
  ) {
    final normalizedDuration =
        summary.elapsed.isNegative ? Duration.zero : summary.elapsed;
    return WorkoutHistoryEntry(
      id: 'history_${template.id}_${summary.completedAt.millisecondsSinceEpoch}',
      workoutName: summary.workoutName,
      startedAt: summary.startedAt,
      completedAt: summary.completedAt,
      duration: normalizedDuration,
      totalVolumeKg: summary.totalVolumeKg,
      totalReps: summary.totalReps,
      exercisesCompleted: summary.exercisesCompleted,
      totalExercises: summary.totalExercises,
      prsAchieved: summary.prsAchieved,
      exerciseSummaries: summary.exerciseSummaries,
      muscleGroupVolumeKg: summary.muscleGroupVolumeKg,
    );
  }

  Future<bool> _confirmDiscardLiveWorkoutDialog() async {
    return showLiftConfirmDialog(
      context: context,
      title: 'Discard workout?',
      message: 'This will end your live workout and discard this session.',
      cancelLabel: 'Keep workout',
      confirmLabel: 'Discard',
      cancelLeadingAssetPath: MynauiGlyphs.checkUnread,
      confirmLeadingAssetPath: MynauiGlyphs.trashBin,
      confirmColor: Colors.red.shade600,
    );
  }

  Future<bool> _confirmCompleteLiveWorkoutDialog() async {
    return showLiftConfirmDialog(
      context: context,
      title: 'Complete workout?',
      message: 'This will end the live workout and show your summary.',
      cancelLabel: 'Keep workout',
      confirmLabel: 'Complete',
      cancelColor: Colors.black,
      confirmColor: kLiftPositiveGreen,
      cancelLeadingAssetPath: MynauiGlyphs.altArrowLeft,
      confirmLeadingAssetPath: MynauiGlyphs.checkCircle,
    );
  }

  Future<void> _deleteTemplate(WorkoutTemplate template) async {
    final isDeletingLiveTemplate = _activeLiveTemplate?.id == template.id;
    final confirmed = await showLiftConfirmDialog(
      context: context,
      title: 'Delete workout template?',
      message:
          isDeletingLiveTemplate
              ? 'This will delete "${template.name}" and end its live workout session.'
              : 'This will delete "${template.name}" from your templates.',
      confirmLabel: 'Delete',
      confirmColor: Colors.red.shade600,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _templates.removeWhere((value) => value.id == template.id);
      _expandedExerciseIds.clear();
      if (_activeLiveTemplate?.id == template.id) {
        _clearLiveWorkoutSession();
      }
      if (_selectedTemplateId == template.id) {
        _selectedTemplateId = null;
      }
      _mode =
          _templates.isEmpty
              ? _WorkoutTemplatesMode.overview
              : _WorkoutTemplatesMode.list;
    });
    _publishLiveShellState();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted "${template.name}"')));
  }

  Future<void> _showTemplateOptionsSheet(WorkoutTemplate template) async {
    final action = await showModalBottomSheet<_TemplateDetailMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      isScrollControlled: false,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Workout options',
            subtitle: template.name,
            children: [
              LiftMenuActionTile(
                icon: MynauiIcon(
                  MynauiGlyphs.editOne,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Edit workout',
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_TemplateDetailMenuAction.edit);
                },
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: const MynauiIcon(
                  MynauiGlyphs.clipboardList,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Review',
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_TemplateDetailMenuAction.review);
                },
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: const MynauiIcon(
                  MynauiGlyphs.squareShareLine,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Share',
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_TemplateDetailMenuAction.share);
                },
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: const MynauiIcon(
                  MynauiGlyphs.trashBin,
                  size: 22,
                  color: Colors.red,
                ),
                title: 'Delete workout',
                accent: Colors.red,
                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop(_TemplateDetailMenuAction.delete);
                },
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TemplateDetailMenuAction.edit:
        _openEdit(template);
      case _TemplateDetailMenuAction.review:
        _openReview(template);
      case _TemplateDetailMenuAction.share:
        _shareTemplate(template);
      case _TemplateDetailMenuAction.delete:
        _deleteTemplate(template);
    }
  }

  void _openOverview() {
    _transitionToMode(_WorkoutTemplatesMode.overview);
    _publishLiveShellState();
  }

  void _openList() {
    _transitionToMode(_WorkoutTemplatesMode.list);
    _publishLiveShellState();
  }

  void _openDetail(WorkoutTemplate template) {
    final openedFrom = _mode;
    _transitionToMode(
      _WorkoutTemplatesMode.detail,
      update: () {
        _selectTemplateForDetail(template);
        if (openedFrom == _WorkoutTemplatesMode.overview ||
            openedFrom == _WorkoutTemplatesMode.list) {
          _detailBrowseOrigin = openedFrom;
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_templateDetailScrollController.hasClients) {
        _templateDetailScrollController.jumpTo(0);
      }
    });
    _publishLiveShellState();
  }

  void _openCreate() {
    _transitionToMode(
      _WorkoutTemplatesMode.editor,
      update: () {
        _selectedTemplateId = null;
        _editorReturnMode = _WorkoutTemplatesMode.list;
      },
    );
    _publishLiveShellState();
  }

  void _openEdit(WorkoutTemplate template) {
    _transitionToMode(
      _WorkoutTemplatesMode.editor,
      update: () {
        _selectedTemplateId = template.id;
        _editorReturnMode = _WorkoutTemplatesMode.detail;
      },
    );
    _publishLiveShellState();
  }

  void _openTrends(WorkoutTemplate template) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => LegDayTrendsPage(template: template)),
    );
  }

  void _openReview(WorkoutTemplate template) {
    _openTrends(template);
  }

  void _showWorkoutDetailSnackBar(String message) {
    const gapAboveBottomIsland = 12.0;
    final bottomMargin =
        kShellFloatingNavBottomInset +
        kLiftIslandHeaderHeight +
        gapAboveBottomIsland;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
      ),
    );
  }

  Future<void> _shareTemplate(WorkoutTemplate template) async {
    final text = '''
Workout: ${template.name}
Duration: ${template.estimatedDurationMinutes} min
Exercises: ${template.exercises.length}
''';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showWorkoutDetailSnackBar('Workout info copied to clipboard');
  }

  Future<void> _shareWorkoutSummary(
    LiveWorkoutSummaryState summary,
    List<_WorkoutSummaryMuscleEntry> workedMuscles,
  ) async {
    final workedMuscleLabels =
        workedMuscles.map((entry) => entry.label).toList();
    final workedMusclesLine =
        workedMuscleLabels.isEmpty
            ? ''
            : '\nWorked muscles: ${workedMuscleLabels.join(', ')}';
    final text = '''
Workout summary
Workout: ${summary.workoutName}
Duration: ${_formatSummaryDuration(summary.elapsed)}
Calories burned (est.): ${summary.estimatedCaloriesBurned} cal
Training score: ${summary.trainingScore}/100
Workout intensity: ${summary.workoutIntensityLabel}
Completed: ${summary.exercisesCompleted}/${summary.totalExercises} exercises
Reps: ${summary.totalReps}
Volume: ${_formatVolume(summary.totalVolumeKg)}$workedMusclesLine
''';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showWorkoutDetailSnackBar('Workout summary copied to clipboard');
  }

  void _openLiveWorkout(WorkoutTemplate template) {
    if (_hasActiveLiveWorkout && _activeLiveTemplate?.id == template.id) {
      _resumeLiveWorkout();
      return;
    }
    if (_hasActiveLiveWorkout) {
      final active = _activeLiveTemplate;
      if (!mounted) return;
      final name = active?.name ?? 'a workout';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have "$name" in progress. Finish or discard it before starting another.',
          ),
        ),
      );
      return;
    }
    final returnAfterLive =
        _mode == _WorkoutTemplatesMode.detail
            ? _detailBrowseOrigin
            : (_mode == _WorkoutTemplatesMode.list
                ? _WorkoutTemplatesMode.list
                : _WorkoutTemplatesMode.overview);
    _transitionToMode(
      _WorkoutTemplatesMode.live,
      update: () {
        _selectedTemplateId = template.id;
        _activeLiveTemplate = template;
        _liveReturnMode = returnAfterLive;
        _liveMiniState = null;
        _liveWorkoutKey = GlobalKey();
      },
    );
    _publishLiveShellState();
  }

  void _minimizeLiveWorkout() {
    if (!_hasActiveLiveWorkout) return;
    _transitionToMode(
      _liveReturnMode,
      update: () {
        _selectedTemplateId = null;
      },
    );
    _publishLiveShellState();
  }

  void _resumeLiveWorkout() {
    if (!_hasActiveLiveWorkout) return;
    _transitionToMode(_WorkoutTemplatesMode.live);
    _publishLiveShellState();
  }

  void _clearLiveWorkoutSession() {
    _activeLiveTemplate = null;
    _liveMiniState = null;
    _liveSummaryState = null;
    _liveWorkoutKey = null;
  }

  String _formatSummaryDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatVolume(double volumeKg) {
    final rounded = volumeKg.round();
    final digits = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return '${buffer.toString()} kg';
  }

  Future<void> _showWorkoutSummaryDialog(LiveWorkoutSummaryState summary) {
    final template = _activeLiveTemplate ?? _selectedTemplate;
    final rankedMuscles =
        summary.muscleGroupVolumeKg.entries
            .where((entry) => entry.value > 0.001)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final usesFallbackTargetMap = rankedMuscles.isEmpty;
    final fallbackWorkedMuscles = <_WorkoutSummaryMuscleEntry>[];
    if (usesFallbackTargetMap) {
      final fallbackLabels = <String>{};
      if (template != null) {
        for (final exercise in template.exercises) {
          final catalogItem = _summaryCatalogItemForExerciseName(exercise.name);
          fallbackLabels.addAll(
            catalogItem?.muscleGroups ??
                _summaryHeuristicMuscleTagsForName(exercise.name),
          );
        }
      }
      for (final exercise in summary.exerciseSummaries) {
        fallbackLabels.addAll(exercise.muscleGroups);
      }
      if (fallbackLabels.isEmpty) {
        fallbackLabels.addAll(
          workoutTargetRegionsForLabels([
            summary.workoutName,
          ]).map(_workoutTargetRegionLabel),
        );
      }
      fallbackWorkedMuscles.addAll(
        fallbackLabels
            .take(6)
            .map(
              (label) =>
                  _WorkoutSummaryMuscleEntry(label: label, isFallback: true),
            ),
      );
    }
    final workedMuscles = <_WorkoutSummaryMuscleEntry>[
      if (rankedMuscles.isNotEmpty)
        ...rankedMuscles
            .take(6)
            .map(
              (entry) => _WorkoutSummaryMuscleEntry(
                label: entry.key,
                volumeKg: entry.value,
              ),
            )
      else
        ...fallbackWorkedMuscles,
    ];

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _WorkoutSummaryDialogContent(
              summary: summary,
              workedMuscles: workedMuscles,
              usesFallbackTargetMap: usesFallbackTargetMap,
              formatDuration: _formatSummaryDuration,
              formatVolume: _formatVolume,
              onShare: () => _shareWorkoutSummary(summary, workedMuscles),
            ),
          ),
        );
      },
    );
  }

  void _saveTemplate(WorkoutTemplate template) {
    final existingIndex = _templates.indexWhere((t) => t.id == template.id);
    _transitionToMode(
      _WorkoutTemplatesMode.detail,
      update: () {
        if (existingIndex >= 0) {
          _templates[existingIndex] = template;
        } else {
          _templates.insert(0, template);
        }
        _selectedTemplateId = template.id;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_templateListPageController.hasClients) {
        _templateListPageController.jumpToPage(0);
      }
    });
    _publishLiveShellState();
  }

  void _handleBack() {
    switch (_mode) {
      case _WorkoutTemplatesMode.overview:
        return;
      case _WorkoutTemplatesMode.list:
        if (widget.popOnBackFromList) {
          Navigator.of(context).maybePop();
        } else {
          _openOverview();
        }
      case _WorkoutTemplatesMode.detail:
        if (widget.popOnBackFromDetail) {
          Navigator.of(context).maybePop();
        } else {
          _openList();
        }
      case _WorkoutTemplatesMode.editor:
        _transitionToMode(_editorReturnMode);
      case _WorkoutTemplatesMode.live:
        _minimizeLiveWorkout();
    }
  }

  void _openExerciseDetails(WorkoutTemplateExercise exercise) {
    pushExerciseDetailPage(context, exerciseName: exercise.name);
  }

  String _formatDuration(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) return '$hours hour';
      return '${hours}hr ${mins}mins';
    }
    return '$minutes mins';
  }

  String _formatShortDuration(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) return '$hours hour';
      return '${hours}hr ${mins}mins';
    }
    return '$minutes mins';
  }

  String _formatRest(int seconds) {
    final minutes = seconds ~/ 60;
    final rem = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rem';
  }

  WorkoutTemplate _createEmptyTemplate() {
    _templateIdSeed += 1;
    return WorkoutTemplate(
      id: 'template_custom_$_templateIdSeed',
      name: 'New Workout',
      imageUrl:
          'https://images.pexels.com/photos/4162490/pexels-photo-4162490.jpeg',
      durationMinutes: 45,
      focusTags: const ['Custom'],
      exercises: const [],
    );
  }

  String _nextExerciseId() {
    _exerciseIdSeed += 1;
    return 'exercise_$_exerciseIdSeed';
  }

  double _modeBaseBottomPadding(
    _WorkoutTemplatesMode mode, {
    required bool showFloatingDetailAction,
    required double bottomSafePadding,
  }) {
    final standaloneBottomPadding = math.max(12.0, bottomSafePadding - 10.0);
    return switch (mode) {
      _WorkoutTemplatesMode.overview =>
        _hasBottomNavigationIsland ? 104.0 : standaloneBottomPadding,
      _WorkoutTemplatesMode.list =>
        _hasBottomNavigationIsland
            ? kShellFloatingNavBottomInset +
                kShellFloatingNavBarHeight +
                _kListCreateActionsVerticalGap
            : standaloneBottomPadding,
      // Detail uses a floating Start bar outside this padding; a non-zero bottom
      // inset leaves an empty band that shows the shell's white behind the bar.
      _WorkoutTemplatesMode.detail => showFloatingDetailAction ? 0.0 : 24.0,
      // Editor uses floating chrome; scroll padding clears it — no extra viewport band.
      _WorkoutTemplatesMode.editor => 0.0,
      _WorkoutTemplatesMode.live => 0.0,
    };
  }

  EdgeInsets _modeContentPadding(
    BuildContext context,
    _WorkoutTemplatesMode mode, {
    required bool showFloatingDetailAction,
    required bool showLiveFullscreen,
  }) {
    final baseBottomPadding = _modeBaseBottomPadding(
      mode,
      showFloatingDetailAction: showFloatingDetailAction,
      bottomSafePadding: MediaQuery.viewPaddingOf(context).bottom,
    );
    // The live dock sits above the shell nav ([kShellLiveDockBottomOffset] is the
    // dock's bottom inset). Reserve: offset + dock height + same gap as between
    // the list card and the create row ([_kListCreateActionsVerticalGap]).
    final liveDockBottomOffset =
        _shouldHideShellNav
            ? kShellStandaloneLiveDockBottomInset
            : kShellLiveDockBottomOffset;
    final bottomPadding =
        _showLiveDock
            ? math.max(
              baseBottomPadding,
              liveDockBottomOffset +
                  WorkoutLiveDock.kExpandedVisualHeight +
                  _kListCreateActionsVerticalGap,
            )
            : baseBottomPadding;
    final edgeToEdgeTop =
        (mode == _WorkoutTemplatesMode.detail && !showLiveFullscreen) ||
        mode == _WorkoutTemplatesMode.editor;

    return EdgeInsets.fromLTRB(
      kPagePadding,
      edgeToEdgeTop ? 0.0 : 16.0,
      kPagePadding,
      bottomPadding,
    );
  }

  Widget _buildModeViewport({
    required _WorkoutTemplatesMode mode,
    required Widget child,
    required bool showFloatingDetailAction,
    required bool showLiveFullscreen,
  }) {
    final edgeToEdgeTop =
        (mode == _WorkoutTemplatesMode.detail && !showLiveFullscreen) ||
        mode == _WorkoutTemplatesMode.editor;
    final body = Padding(
      padding: _modeContentPadding(
        context,
        mode,
        showFloatingDetailAction: showFloatingDetailAction,
        showLiveFullscreen: showLiveFullscreen,
      ),
      child: child,
    );

    if (edgeToEdgeTop) {
      return body;
    }

    return SafeArea(top: true, bottom: false, child: body);
  }

  @override
  Widget build(BuildContext context) {
    _syncShellNavVisibilityFromBuild();
    final showLiveFullscreen =
        _hasActiveLiveWorkout && _mode == _WorkoutTemplatesMode.live;
    final contentMode = showLiveFullscreen ? _liveReturnMode : _mode;
    if (contentMode != _WorkoutTemplatesMode.list) {
      _lastTemplateListPageSizeForList = null;
    }
    final showFloatingDetailAction =
        contentMode == _WorkoutTemplatesMode.detail &&
        !showLiveFullscreen &&
        !_showLiveDock;
    final detailTemplate =
        contentMode == _WorkoutTemplatesMode.detail ? _selectedTemplate : null;

    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: ValueKey(contentMode),
            child: _buildModeViewport(
              mode: contentMode,
              showFloatingDetailAction: showFloatingDetailAction,
              showLiveFullscreen: showLiveFullscreen,
              child: switch (contentMode) {
                _WorkoutTemplatesMode.overview => _buildOverview(),
                _WorkoutTemplatesMode.list => _buildTemplateList(),
                _WorkoutTemplatesMode.detail => _buildTemplateDetail(
                  showFloatingAction: showFloatingDetailAction,
                ),
                _WorkoutTemplatesMode.editor => _buildEditor(),
                // Live UI is only mounted in the Offstage layer below so
                // [LiveWorkoutScreen] state is not duplicated.
                _WorkoutTemplatesMode.live => const SizedBox.shrink(),
              },
            ),
          ),
        ),
        if (showLiveFullscreen)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        if (_hasActiveLiveWorkout)
          Positioned.fill(
            child: TickerMode(
              enabled: true,
              child: Offstage(
                offstage: !showLiveFullscreen,
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Padding(
                    // Fullscreen live must not inherit [_liveReturnMode] bottom
                    // inset (e.g. 104 for list / shell nav); that caused a large
                    // empty band below the live bottom action bar.
                    padding: _modeContentPadding(
                      context,
                      _WorkoutTemplatesMode.live,
                      showFloatingDetailAction: false,
                      showLiveFullscreen: true,
                    ),
                    child: _buildLiveWorkout(),
                  ),
                ),
              ),
            ),
          ),
        if (showFloatingDetailAction && detailTemplate != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: kShellFloatingNavBottomInset,
            child: SafeArea(
              top: false,
              bottom: false,
              child: _TemplateDetailBottomBar(
                hasActiveLiveWorkout: _hasActiveLiveWorkout,
                onStartWorkout: () => _openLiveWorkout(detailTemplate),
                onResumeWorkout: _resumeLiveWorkout,
                onTrends: () => _openTrends(detailTemplate),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOverview() {
    final templates = _templates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TemplatesHeader(
          scrollController: null,
          showBack: widget.showRootBack,
          onBack:
              widget.showRootBack
                  ? (widget.onRootBack ??
                      () => Navigator.of(context).maybePop())
                  : null,
          onLeadingTap: widget.showRootBack ? null : widget.onLeadingTap,
          onTrailingTap:
              widget.showRootProfileAction
                  ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  }
                  : null,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const railBleed = 16.0;
              final railWidth = constraints.maxWidth + (railBleed * 2);
              final cardWidth = (railWidth * 0.66).clamp(240.0, 300.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minWidth: railWidth,
                      maxWidth: railWidth,
                      child: SizedBox(
                        width: railWidth,
                        child: PageView.builder(
                          controller: _overviewPageController,
                          padEnds: false,
                          itemCount: templates.length,
                          itemBuilder: (context, index) {
                            final template = templates[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                left: index == 0 ? 16 : 7,
                                right: index == templates.length - 1 ? 32 : 7,
                              ),
                              child: SizedBox(
                                width: cardWidth,
                                child: _TemplateFeatureCard(
                                  template: template,
                                  durationLabel: _formatShortDuration(
                                    template.estimatedDurationMinutes,
                                  ),
                                  onTap: () => _openDetail(template),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _openList,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'View all',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionBoundary(
                    borderRadius: kIosCornerRadius,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start from scratch or create a custom template for your gym.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CreateActionsRow(
                          hideEmptyWorkout: _hasActiveLiveWorkout,
                          onEmptyWorkout: () {
                            final template = _createEmptyTemplate().copyWith(
                              name: 'Empty Workout',
                            );
                            _openEdit(template);
                          },
                          onCreate: _openCreate,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateList() {
    final filtered = _filteredTemplates;
    final hasActiveFilters = _listFilters.hasActiveFilters;
    final filterActiveCount = _listFilters.activeCount;
    final noResultsMessage =
        _searchQuery.trim().isNotEmpty && hasActiveFilters
            ? 'No workouts match your search and filters'
            : _searchQuery.trim().isNotEmpty
            ? 'No workouts match "$_searchQuery"'
            : hasActiveFilters
            ? 'No workouts match the selected filters'
            : 'No workouts yet';
    return Column(
      children: [
        _TemplatesHeader(
          scrollController: _templateListPageController,
          showBack: true,
          onBack: _handleBack,
          rightWidget: LiftIslandHeaderAction(
            onTap: () {},
            child: const MynauiIcon(
              MynauiGlyphs.menuDotsCircle,
              size: 22,
              color: kLiftIslandOnFrosted,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  cursorColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(
                    color: Color(0xE6000000),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_templateListPageController.hasClients) {
                        _templateListPageController.jumpToPage(0);
                      }
                    });
                  },
                  scrollPadding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 120,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search workouts',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: MynauiIcon(
                          MynauiGlyphs.magnifer,
                          size: 20,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    prefixIconConstraints: BoxConstraints.tight(
                      const Size(48, 48),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    // Left padding is inside the field *after* the 48px prefix slot.
                    // Symmetric horizontal: 14 was letting the hint/cursor sit under the icon.
                    contentPadding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      borderSide: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      borderSide: const BorderSide(
                        color: Color(0xFF2C2C2C),
                        width: 1.25,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      borderSide: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openOverview,
                borderRadius: BorderRadius.circular(kIosCornerRadius),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Ink(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kIosCornerRadius),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Center(
                    child: MynauiIcon(
                      MynauiGlyphs.documents,
                      size: 20,
                      color: Colors.black.withValues(alpha: 0.55),
                      semanticLabel: 'Default workouts',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openWorkoutFilters,
                borderRadius: BorderRadius.circular(kIosCornerRadius),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Ink(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasActiveFilters ? kAccentColor : Colors.white,
                    borderRadius: BorderRadius.circular(kIosCornerRadius),
                    border: Border.all(
                      color:
                          hasActiveFilters
                              ? kAccentColor
                              : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: MynauiIcon(
                          MynauiGlyphs.filter,
                          size: 20,
                          color:
                              hasActiveFilters
                                  ? Colors.white
                                  : Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                      if (filterActiveCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            height: 16,
                            constraints: const BoxConstraints(minWidth: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$filterActiveCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: kAccentColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child:
              filtered.isEmpty
                  ? Center(
                    child: Text(
                      noResultsMessage,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                  : Builder(
                    builder: (context) {
                      final pageSize = _templateListPageSize;
                      final lastPageSize = _lastTemplateListPageSizeForList;
                      if (lastPageSize != null && lastPageSize != pageSize) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_templateListPageController.hasClients) {
                            _templateListPageController.jumpToPage(0);
                          }
                        });
                      }
                      _lastTemplateListPageSizeForList = pageSize;

                      final pageCount =
                          (filtered.length + pageSize - 1) ~/ pageSize;

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (!_templateListPageController.hasClients) return;
                        final idx =
                            _templateListPageController.page?.round() ?? 0;
                        if (idx >= pageCount) {
                          _templateListPageController.jumpToPage(
                            math.max(0, pageCount - 1),
                          );
                        }
                      });

                      return SectionBoundary(
                        borderRadius: kIosCornerRadius,
                        padding: const EdgeInsets.all(12),
                        clipBehavior: Clip.antiAlias,
                        floating: true,
                        floatingBackgroundOpacity: 0.98,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: PageView.builder(
                                controller: _templateListPageController,
                                scrollDirection: Axis.vertical,
                                itemCount: pageCount,
                                onPageChanged: (index) {
                                  setState(
                                    () => _templateListPageIndex = index,
                                  );
                                },
                                itemBuilder: (context, pageIndex) {
                                  final start = pageIndex * pageSize;
                                  final end = math.min(
                                    start + pageSize,
                                    filtered.length,
                                  );
                                  final rowCount = end - start;
                                  return LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compactRows = pageSize >= 5;
                                      final gap = compactRows ? 4.0 : 6.0;
                                      // Full pages split the available height
                                      // evenly across the active row count.
                                      if (rowCount == pageSize) {
                                        return SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (
                                                var i = start;
                                                i < end;
                                                i++
                                              ) ...[
                                                if (i > start)
                                                  SizedBox(height: gap),
                                                Expanded(
                                                  child: _TemplateListRow(
                                                    compact: compactRows,
                                                    expandVertical: true,
                                                    template: filtered[i],
                                                    durationLabel: _formatDuration(
                                                      filtered[i]
                                                          .estimatedDurationMinutes,
                                                    ),
                                                    onTap:
                                                        () => _openDetail(
                                                          filtered[i],
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }
                                      // Partial pages: top-aligned; FittedBox scales if short.
                                      return SizedBox(
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.topCenter,
                                            child: SizedBox(
                                              width: constraints.maxWidth,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  for (
                                                    var i = start;
                                                    i < end;
                                                    i++
                                                  ) ...[
                                                    if (i > start)
                                                      SizedBox(height: gap),
                                                    _TemplateListRow(
                                                      compact: compactRows,
                                                      template: filtered[i],
                                                      durationLabel:
                                                          _formatDuration(
                                                            filtered[i]
                                                                .estimatedDurationMinutes,
                                                          ),
                                                      onTap:
                                                          () => _openDetail(
                                                            filtered[i],
                                                          ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            // Always show the pager on the list card (like Guides footer),
                            // even for a single page, so Prev/Next/dots aren’t missing when
                            // everything fits in one vertical page (e.g. 4 rows @ page size 4).
                            if (filtered.isNotEmpty) ...[
                              // Same as [SectionBoundary] top padding (12): gap from last row
                              // to pager matches gap from container top to first row.
                              const SizedBox(height: 12),
                              Center(
                                child: LiftListPagination(
                                  currentPage: _templateListPageIndex + 1,
                                  totalPages: pageCount,
                                  onPrevious:
                                      pageCount > 1 &&
                                              _templateListPageIndex > 0
                                          ? () {
                                            _templateListPageController
                                                .previousPage(
                                                  duration: const Duration(
                                                    milliseconds: 280,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                );
                                          }
                                          : null,
                                  onNext:
                                      pageCount > 1 &&
                                              _templateListPageIndex <
                                                  pageCount - 1
                                          ? () {
                                            _templateListPageController
                                                .nextPage(
                                                  duration: const Duration(
                                                    milliseconds: 280,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                );
                                          }
                                          : null,
                                  onSelectPage:
                                      pageCount > 1
                                          ? (page) {
                                            _templateListPageController
                                                .animateToPage(
                                                  page - 1,
                                                  duration: const Duration(
                                                    milliseconds: 280,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                );
                                          }
                                          : null,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
        ),
        SizedBox(height: _kListCreateActionsVerticalGap),
        _CreateActionsRow(
          hideEmptyWorkout: _hasActiveLiveWorkout,
          onEmptyWorkout: () {
            final template = _createEmptyTemplate().copyWith(
              name: 'Empty Workout',
            );
            _openEdit(template);
          },
          onCreate: _openCreate,
        ),
      ],
    );
  }

  Widget _buildTemplateDetail({required bool showFloatingAction}) {
    final template = _selectedTemplate;
    if (template == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Template not found'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openList,
              child: const Text('Go to templates'),
            ),
          ],
        ),
      );
    }

    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    const sectionGap = 12.0;
    const heroHeaderSeparation = sectionGap;

    final headerBottom = topInset + islandTop + kLiftIslandHeaderHeight;
    final listScrollTopPadding = headerBottom + heroHeaderSeparation;
    final topBlurBandHeight = listScrollTopPadding + 36.0;
    const gapAboveBottomIsland = 10.0;
    final listBottomPadding =
        showFloatingAction
            ? kShellFloatingNavBottomInset +
                kLiftIslandHeaderHeight +
                gapAboveBottomIsland
            : 14.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ListView(
            controller: _templateDetailScrollController,
            primary: false,
            padding: EdgeInsets.fromLTRB(
              0,
              listScrollTopPadding,
              0,
              listBottomPadding,
            ),
            children: [
              _TemplateHeroDetailCard(
                template: template,
                durationLabel: _formatDuration(
                  template.estimatedDurationMinutes,
                ),
              ),
              const SizedBox(height: sectionGap),
              _TemplateStatsTile(
                exerciseCount: template.exercises.length,
                totalSetCount: template.exercises.fold<int>(
                  0,
                  (sum, exercise) => sum + exercise.presetRows.length,
                ),
                totalRestLabel: _formatRest(template.totalRestSeconds),
                focusTags: template.focusTags,
              ),
              const SizedBox(height: sectionGap),
              ...template.exercises.map(
                (exercise) => Padding(
                  padding: const EdgeInsets.only(bottom: sectionGap),
                  child: _ExerciseDetailCard(
                    exercise: exercise,
                    isExpanded: _expandedExerciseIds.contains(exercise.id),
                    restFormatter: _formatRest,
                    onOpenDetails: () => _openExerciseDetails(exercise),
                    onToggle: () {
                      setState(() {
                        if (_expandedExerciseIds.contains(exercise.id)) {
                          _expandedExerciseIds.remove(exercise.id);
                        } else {
                          _expandedExerciseIds.add(exercise.id);
                        }
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topBlurBandHeight,
          child: IgnorePointer(
            // Scroll-linked scrim is fully transparent at offset 0, so the hero
            // photo tinted the translucent island (warm/pink cast). Keep neutral
            // frost always on for this screen.
            child: const StaticFeatheredTopBlurScrim(blurSigma: 24),
          ),
        ),
        Positioned(
          top: topInset + islandTop,
          left: 0,
          right: 0,
          child: _TemplatesHeader(
            scrollController: _templateDetailScrollController,
            center: const SizedBox.shrink(),
            showBack: true,
            onBack: _handleBack,
            backButtonIcon: _alignedWorkoutBackIcon(),
            rightWidget: LiftIslandHeaderAction(
              onTap: () => _showTemplateOptionsSheet(template),
              child: const MynauiIcon(
                MynauiGlyphs.menuDotsCircle,
                size: 22,
                color: kLiftIslandOnFrosted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    final initialTemplate = _selectedTemplate ?? _createEmptyTemplate();

    return _TemplateEditorScreen(
      template: initialTemplate,
      showBack: true,
      nextExerciseId: _nextExerciseId,
      onBack: _handleBack,
      onOpenExerciseDetails: _openExerciseDetails,
      onSave: _saveTemplate,
    );
  }

  Widget _buildLiveWorkout() {
    final template = _activeLiveTemplate ?? _selectedTemplate;
    if (template == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Workout template not found'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openList,
              child: const Text('Go to templates'),
            ),
          ],
        ),
      );
    }

    final key = _liveWorkoutKey;
    if (key == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Live workout session unavailable'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openList,
              child: const Text('Go to templates'),
            ),
          ],
        ),
      );
    }

    return LiveWorkoutScreen(
      key: key,
      template: template,
      onBack: _minimizeLiveWorkout,
      onDiscard: _discardLiveWorkout,
      onCompleteWorkout: _completeLiveWorkout,
      showBottomActions: true,
      onStateChanged: (state) {
        if (!mounted) return;
        setState(() {
          _liveMiniState = state;
        });
        _publishLiveShellState();
      },
      onSummaryChanged: (summary) {
        if (!mounted) return;
        _liveSummaryState = summary;
      },
    );
  }
}

class WorkoutLiveDock extends StatelessWidget {
  const WorkoutLiveDock({
    super.key,
    required this.state,
    required this.onTap,
    this.compact = false,
  });

  /// Expanded layout: `vertical: 8` padding ×2 + 40px-tall row. Keep in sync with
  /// [build] so list bottom padding matches the real dock height.
  static const double kExpandedVisualHeight = 56.0;

  final LiveWorkoutMiniState state;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final timerLabel =
        state.isResting ? 'Rest ${state.restLabel}' : state.elapsedLabel;
    // Progress line shows session elapsed time; rest countdown is only on [timerLabel].
    final statusLabel =
        state.isResting
            ? '${state.progressLabel} • ${state.elapsedLabel}'
            : state.progressLabel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 30 : kIosCornerRadius),
        child: AnimatedContainer(
          duration: LiftMotion.emphasized,
          curve: Curves.easeOutCubic,
          padding:
              compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              compact ? 30 : kIosCornerRadius,
            ),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child:
              compact
                  ? _CompactWorkoutLiveDockBody(
                    state: state,
                    timerLabel: timerLabel,
                    statusLabel: statusLabel,
                  )
                  : _ExpandedWorkoutLiveDockBody(
                    state: state,
                    timerLabel: timerLabel,
                    statusLabel: statusLabel,
                  ),
        ),
      ),
    );
  }
}

class _ExpandedWorkoutLiveDockBody extends StatelessWidget {
  const _ExpandedWorkoutLiveDockBody({
    required this.state,
    required this.timerLabel,
    required this.statusLabel,
  });

  final LiveWorkoutMiniState state;
  final String timerLabel;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child:
                state.isFinished
                    ? MynauiIcon(
                      MynauiGlyphs.checkCircle,
                      size: 28,
                      color: const Color(0xFF2C6A4B),
                    )
                    : const PhosphorIcon(
                      PhosphorIconsRegular.barbell,
                      size: 26,
                      color: Color(0xFF2C6A4B),
                    ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.templateName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                state.currentExerciseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _WorkoutLiveDockTimerStrip(
            timerLabel: timerLabel,
            statusLabel: statusLabel,
            isRestOverrun: state.isRestOverrun,
          ),
        ),
      ],
    );
  }
}

class _CompactWorkoutLiveDockBody extends StatelessWidget {
  const _CompactWorkoutLiveDockBody({
    required this.state,
    required this.timerLabel,
    required this.statusLabel,
  });

  final LiveWorkoutMiniState state;
  final String timerLabel;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child:
                state.isFinished
                    ? MynauiIcon(
                      MynauiGlyphs.checkCircle,
                      size: 22,
                      color: const Color(0xFF2C6A4B),
                    )
                    : const PhosphorIcon(
                      PhosphorIconsRegular.barbell,
                      size: 20,
                      color: Color(0xFF2C6A4B),
                    ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.templateName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                state.currentExerciseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: _WorkoutLiveDockTimerStrip(
            timerLabel: timerLabel,
            statusLabel: statusLabel,
            isRestOverrun: state.isRestOverrun,
            dense: true,
          ),
        ),
      ],
    );
  }
}

/// Timer chip + progress on one row (nav-bar–height friendly).
class _WorkoutLiveDockTimerStrip extends StatelessWidget {
  const _WorkoutLiveDockTimerStrip({
    required this.timerLabel,
    required this.statusLabel,
    required this.isRestOverrun,
    this.dense = false,
  });

  final String timerLabel;
  final String statusLabel;
  final bool isRestOverrun;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final hp = dense ? 5.0 : 6.0;
    final vp = dense ? 3.0 : 4.0;
    final timerSize = dense ? 10.5 : 11.0;
    final statusSize = dense ? 9.5 : 10.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: hp, vertical: vp),
          decoration: BoxDecoration(
            color: isRestOverrun ? Colors.red.shade50 : const Color(0xFFF2C7A9),
            borderRadius: BorderRadius.circular(kIosControlRadius),
            border:
                isRestOverrun ? Border.all(color: Colors.red.shade200) : null,
          ),
          child: Text(
            timerLabel,
            style: TextStyle(
              fontSize: timerSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color:
                  isRestOverrun ? Colors.red.shade800 : const Color(0xFF4A2B18),
            ),
          ),
        ),
        SizedBox(width: dense ? 5 : 7),
        Flexible(
          child: Text(
            statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: statusSize,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _TemplatesHeader extends StatelessWidget {
  const _TemplatesHeader({
    this.scrollController,
    this.center,
    this.showBack = false,
    this.onBack,
    this.rightWidget,
    this.backButtonIcon,
    this.onLeadingTap,
    this.onTrailingTap,
  });

  final ScrollController? scrollController;

  /// When non-null, used as the island center (e.g. [SizedBox.shrink] when the hero shows the title).
  final Widget? center;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? rightWidget;
  final Widget? backButtonIcon;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return LiftIslandHeader(
      scrollController: scrollController,
      center: center,
      leading:
          showBack
              ? LiftIslandHeaderAction(
                onTap: onBack,
                child:
                    backButtonIcon ??
                    const MynauiIcon(
                      MynauiGlyphs.altArrowLeft,
                      size: kLiftIslandHeaderLeadingIconSize,
                      color: kLiftIslandOnFrosted,
                    ),
              )
              : (onLeadingTap != null
                  ? LiftIslandHeaderAction(
                    onTap: onLeadingTap,
                    child: const MynauiIcon(
                      MynauiGlyphs.qrCode,
                      size: kLiftIslandHeaderLeadingIconSize,
                      color: kLiftIslandOnFrosted,
                    ),
                  )
                  : null),
      trailing:
          rightWidget ??
          (onTrailingTap != null
              ? LiftIslandHeaderAction(
                onTap: onTrailingTap,
                child: const MynauiIcon(
                  MynauiGlyphs.userNoCircle,
                  size: kLiftIslandHeaderTrailingIconSize,
                  color: kLiftIslandOnFrosted,
                ),
              )
              : null),
    );
  }
}

class _TemplateFeatureCard extends StatelessWidget {
  const _TemplateFeatureCard({
    required this.template,
    required this.durationLabel,
    required this.onTap,
  });

  final WorkoutTemplate template;
  final String durationLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiftPressable(
      onTap: onTap,
      borderRadius: kIosCornerRadius,
      child: SectionBoundary(
        borderRadius: kIosCornerRadius,
        padding: EdgeInsets.zero,
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(kIosCornerRadius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WorkoutTemplateHeroImage(
                        imageUrl: template.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: MynauiIcon(
                                MynauiGlyphs.galleryMinimalistic,
                                color: Colors.grey.shade500,
                                size: 36,
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
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.10),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.focusTags.join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DurationChip(label: durationLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateListRow extends StatelessWidget {
  const _TemplateListRow({
    required this.template,
    required this.durationLabel,
    required this.onTap,
    this.compact = false,
    this.expandVertical = false,
  });

  final WorkoutTemplate template;
  final String durationLabel;
  final VoidCallback onTap;

  /// Tighter row when the list shows 5 per page (no live dock).
  final bool compact;

  /// Fills an [Expanded] slot so five rows partition the list viewport evenly.
  final bool expandVertical;

  static const double _kHeroSize = 78.0;
  static const double _kHeroSizeCompact = 62.0;

  /// List rows in an [Expanded] slot can grow taller than the default hero;
  /// caps avoid oversized thumbs while using space that would otherwise sit
  /// empty above the pager (4-up with dock and 5-up without).
  static const double _kHeroCapExpanded = 108.0;

  @override
  Widget build(BuildContext context) {
    final heroDefault = compact ? _kHeroSizeCompact : _kHeroSize;
    final titleSize = compact ? 15.0 : 16.0;
    final bodySize = compact ? 12.0 : 12.0;
    final gapTitle = compact ? 4.0 : 6.0;
    final gapMeta = compact ? 6.0 : 8.0;
    final gapAfterHero = compact ? 11.0 : 12.0;
    final chevron = compact ? 22.0 : 24.0;
    final iconErrorBase = compact ? 24.0 : 28.0;
    final chipGap = compact ? 7.0 : 8.0;
    final heroRadiusBase = compact ? 12.0 : kIosMediaRadius;

    Widget cardFor(
      double heroDim, {
      EdgeInsets? padding,
      double? titleGapOverride,
      double? metaGapOverride,
      bool fitTextToHeight = false,
    }) {
      final iconError = math
          .min(iconErrorBase, heroDim * 0.38)
          .clamp(18.0, 28.0);
      final heroRadius = math
          .min(heroRadiusBase, heroDim * 0.22)
          .clamp(8.0, 16.0);
      final textColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            template.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: titleGapOverride ?? gapTitle),
          Text(
            template.focusTags.join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: bodySize,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: metaGapOverride ?? gapMeta),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${template.exercises.length} exercises',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: bodySize,
                  ),
                ),
              ),
              SizedBox(width: chipGap),
              _DurationChip(label: durationLabel, compact: compact),
            ],
          ),
        ],
      );
      return SectionBoundary(
        borderRadius: kIosCornerRadius,
        padding:
            padding ??
            (compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : const EdgeInsets.all(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(heroRadius),
              child: SizedBox(
                width: heroDim,
                height: heroDim,
                child: WorkoutTemplateHeroImage(
                  imageUrl: template.imageUrl,
                  width: heroDim,
                  height: heroDim,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: MynauiIcon(
                          MynauiGlyphs.galleryMinimalistic,
                          color: Colors.grey.shade500,
                          size: iconError,
                        ),
                      ),
                ),
              ),
            ),
            SizedBox(width: gapAfterHero),
            Expanded(
              child:
                  fitTextToHeight
                      ? LayoutBuilder(
                        builder: (context, constraints) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                child: textColumn,
                              ),
                            ),
                          );
                        },
                      )
                      : textColumn,
            ),
            SizedBox(width: compact ? 4 : 6),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade500,
              size: chevron,
            ),
          ],
        ),
      );
    }

    if (expandVertical) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final verticalPadding = compact ? 4.0 : 12.0;
            final sectionVPad = verticalPadding * 2;
            final heroMin = compact ? _kHeroSizeCompact : 62.0;
            final heroDim =
                math
                    .min(
                      _kHeroCapExpanded,
                      compact
                          ? heroMin
                          : math.max(heroMin, availableHeight - sectionVPad),
                    )
                    .toDouble();
            return SizedBox(
              width: constraints.maxWidth,
              height: availableHeight,
              child: cardFor(
                heroDim,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 12,
                  vertical: verticalPadding,
                ),
                titleGapOverride: compact ? 3 : null,
                metaGapOverride: compact ? 4 : null,
                fitTextToHeight: compact,
              ),
            );
          },
        ),
      );
    }

    final card = cardFor(heroDefault);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kIosCornerRadius),
      child: card,
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111111).withValues(alpha: 0.96),
        borderRadius: kIosChipBorderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 9,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SwapSectionTitle extends StatelessWidget {
  const _SwapSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ExerciseThumbnail extends StatelessWidget {
  const _ExerciseThumbnail({required this.name, this.size = 56});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: kExerciseImageBorderRadius,
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(
          Radius.circular(kExerciseImageRadius - 1),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              exerciseDemoImageUrl(name),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder:
                  (_, __, ___) => Container(
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.fitness_center,
                      color: Colors.grey.shade500,
                      size: size * 0.38,
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
                      Colors.black.withValues(alpha: 0.00),
                      Colors.black.withValues(alpha: 0.10),
                    ],
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

class _SwapExerciseTile extends StatelessWidget {
  const _SwapExerciseTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isCurrent = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              _ExerciseThumbnail(name: title, size: 50),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color:
                            isCurrent ? kAccentColor : const Color(0xFF171717),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isCurrent
                                ? kAccentColor.withValues(alpha: 0.72)
                                : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                MynauiIcon(
                  MynauiGlyphs.checkUnread,
                  size: 22,
                  color: kAccentColor,
                )
              else
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapExerciseDivider extends StatelessWidget {
  const _SwapExerciseDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paddedW = math.max(0.0, constraints.maxWidth - 16);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: SizedBox(
              width: paddedW * 0.5,
              child: Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).dividerTheme.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TemplateHeroDetailCard extends StatelessWidget {
  const _TemplateHeroDetailCard({
    required this.template,
    required this.durationLabel,
  });

  final WorkoutTemplate template;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final clipRadius = BorderRadius.circular(kIosCornerRadius);
    return SectionBoundary(
      customBorderRadius: clipRadius,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: clipRadius,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.45,
              child: WorkoutTemplateHeroImage(
                imageUrl: template.imageUrl,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: MynauiIcon(
                        MynauiGlyphs.galleryMinimalistic,
                        color: Colors.grey.shade500,
                        size: 40,
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
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.42),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      durationLabel.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateStatsTile extends StatelessWidget {
  const _TemplateStatsTile({
    required this.exerciseCount,
    required this.totalSetCount,
    required this.totalRestLabel,
    required this.focusTags,
  });

  final int exerciseCount;
  final int totalSetCount;
  final String totalRestLabel;
  final List<String> focusTags;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TemplateStatCell(
                  label: 'Exercises',
                  value: '$exerciseCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TemplateStatCell(
                  label: 'Sets',
                  value: '$totalSetCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TemplateStatCell(label: 'Rest', value: totalRestLabel),
              ),
            ],
          ),
          if (focusTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(kIosCornerRadius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: const ColoredBox(color: Color(0x00000000)),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.52),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MUSCLES WORKED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              focusTags
                                  .take(5)
                                  .map(
                                    (tag) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        borderRadius: kIosChipBorderRadius,
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        tag.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade900,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TemplateStatCell extends StatelessWidget {
  const _TemplateStatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: kIosControlBorderRadius,
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({
    required this.exercise,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenDetails,
    required this.restFormatter,
    this.footer,
    this.expandedTable,
  });

  final WorkoutTemplateExercise exercise;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenDetails;
  final String Function(int seconds) restFormatter;
  final Widget? footer;
  final Widget? expandedTable;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenDetails,
                  borderRadius: kIosControlBorderRadius,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _ExerciseThumbnail(name: exercise.name),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _DurationChip(label: '${exercise.setCount} sets'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: kIosControlBorderRadius,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: Row(
                    children: [
                      _DurationChip(label: '${exercise.estimatedMinutes} mins'),
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 28,
                        color: Colors.grey.shade700,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 8),
            expandedTable ??
                _SetPresetTable(
                  rows: exercise.presetRows,
                  restFormatter: restFormatter,
                ),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

class _SetPresetTable extends StatelessWidget {
  const _SetPresetTable({required this.rows, required this.restFormatter});

  final List<WorkoutTemplateSetRow> rows;
  final String Function(int seconds) restFormatter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _TableHeaderCell('SETS'),
            _TableHeaderCell('REPS'),
            _TableHeaderCell('WEIGHT'),
            _TableHeaderCell('REST'),
          ],
        ),
        const SizedBox(height: 6),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: kIosControlBorderRadius,
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  _TableValueCell(row.label),
                  _TableValueCell('${row.reps}'),
                  _TableValueCell(
                    row.weightKg <= 0
                        ? '--'
                        : '${row.weightKg.toStringAsFixed(0)}KG',
                  ),
                  _TableValueCell(
                    row.restSeconds <= 0
                        ? '--'
                        : restFormatter(row.restSeconds),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _TableValueCell extends StatelessWidget {
  const _TableValueCell(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EditableCell extends StatelessWidget {
  const _EditableCell({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: kIosControlBorderRadius,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: kIosControlBorderRadius,
            border: Border.all(color: Colors.grey.shade200),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: Colors.grey.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditStateChip extends StatelessWidget {
  const _EditStateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: kIosChipBorderRadius,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
    );
  }
}

class _CreateActionsRow extends StatelessWidget {
  const _CreateActionsRow({
    required this.onEmptyWorkout,
    required this.onCreate,
    this.hideEmptyWorkout = false,
  });

  final VoidCallback onEmptyWorkout;
  final VoidCallback onCreate;

  /// When a live workout is active, hide "Empty workout" and show only a centered
  /// "Create template" control (same action as the standalone +).
  final bool hideEmptyWorkout;

  static ButtonStyle _pillStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : Colors.black;
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: isDark ? const Color(0xFF15171B) : Colors.white,
      side: BorderSide(color: foreground, width: 1),
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pillHeight = 48.0;
    // Slightly larger than the pill so the + reads clearly and the hit target is generous.
    const addSize = 54.0;
    const addIcon = 34.0;
    const createIcon = 22.0;

    if (hideEmptyWorkout) {
      return Center(
        child: SizedBox(
          height: pillHeight,
          child: OutlinedButton(
            style: _pillStyle(context),
            onPressed: onCreate,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MynauiIcon(
                  MynauiGlyphs.addCircle,
                  color: kAccentColor,
                  size: createIcon,
                ),
                const SizedBox(width: 8),
                const Text('Create template'),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: pillHeight,
            child: OutlinedButton(
              style: _pillStyle(context).copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              onPressed: onEmptyWorkout,
              child: const Text('Empty workout'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        LiftPressable(
          onTap: onCreate,
          borderRadius: addSize / 2,
          pressedScale: LiftMotion.gentlePressScale,
          child: SizedBox(
            width: addSize,
            height: addSize,
            child: Center(
              child: MynauiIcon(
                MynauiGlyphs.addCircle,
                color: kAccentColor,
                size: addIcon,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkoutFiltersSheet extends StatefulWidget {
  const _WorkoutFiltersSheet({
    required this.initialFilters,
    required this.availableFocusTags,
  });

  final _WorkoutListFilters initialFilters;
  final List<String> availableFocusTags;

  @override
  State<_WorkoutFiltersSheet> createState() => _WorkoutFiltersSheetState();
}

class _WorkoutFiltersSheetState extends State<_WorkoutFiltersSheet> {
  late Set<String> _selectedTags;
  late _WorkoutDurationFilter _selectedDuration;

  bool get _hasActiveFilters =>
      _selectedTags.isNotEmpty ||
      _selectedDuration != _WorkoutDurationFilter.any;

  String get _tagSummary {
    if (_selectedTags.isEmpty) return '';
    if (_selectedTags.length == 1) {
      return _selectedTags.first;
    }
    return '${_selectedTags.length} muscle groups';
  }

  String get _selectionSummary {
    if (!_hasActiveFilters) {
      return 'Narrow workouts by target muscles and session length.';
    }

    final parts = <String>[];
    if (_selectedTags.isNotEmpty) {
      parts.add(_tagSummary);
    }
    if (_selectedDuration != _WorkoutDurationFilter.any) {
      parts.add(_selectedDuration.label);
    }
    return parts.join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.initialFilters.focusTags);
    _selectedDuration = widget.initialFilters.duration;
  }

  @override
  Widget build(BuildContext context) {
    return LiftMenuSheet(
      title: 'Filter workouts',
      subtitle: _selectionSummary,
      children: [
        const _WorkoutFilterSectionLabel('Focus'),
        const SizedBox(height: 8),
        if (widget.availableFocusTags.isEmpty)
          Text(
            'Focus filters will appear once workouts have muscle tags.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.availableFocusTags
                .map(
                  (tag) => _WorkoutFilterChip(
                    label: tag,
                    selected: _selectedTags.contains(tag),
                    onTap: () {
                      setState(() {
                        if (_selectedTags.contains(tag)) {
                          _selectedTags.remove(tag);
                        } else {
                          _selectedTags.add(tag);
                        }
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 14),
        const _WorkoutFilterSectionLabel('Duration'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _WorkoutDurationFilter.values
              .map(
                (duration) => _WorkoutFilterChip(
                  label: duration.label,
                  selected: duration == _selectedDuration,
                  onTap: () => setState(() => _selectedDuration = duration),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed:
                      _hasActiveFilters
                          ? () {
                            setState(() {
                              _selectedTags.clear();
                              _selectedDuration = _WorkoutDurationFilter.any;
                            });
                          }
                          : null,
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return const Color(0xFF64748B);
                      }
                      return const Color(0xFF171717);
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return Colors.white.withValues(alpha: 0.55);
                      }
                      return Colors.white.withValues(alpha: 0.92);
                    }),
                    side: WidgetStateProperty.resolveWith((states) {
                      final border =
                          states.contains(WidgetState.disabled)
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF94A3B8);
                      return BorderSide(color: border, width: 1);
                    }),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kIosCornerRadius),
                      ),
                    ),
                    overlayColor: WidgetStateProperty.all(
                      Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MynauiIcon(
                        MynauiGlyphs.restartCircle,
                        size: 19,
                        color:
                            _hasActiveFilters
                                ? const Color(0xFF171717)
                                : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Reset',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _WorkoutListFilters(
                        focusTags: Set<String>.from(_selectedTags),
                        duration: _selectedDuration,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MynauiIcon(
                        _hasActiveFilters
                            ? MynauiGlyphs.checkCircle
                            : MynauiGlyphs.listDown,
                        size: 19,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _hasActiveFilters ? 'Apply filters' : 'Show all',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkoutFilterSectionLabel extends StatelessWidget {
  const _WorkoutFilterSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Colors.grey.shade700,
      ),
    );
  }
}

class _WorkoutFilterChip extends StatelessWidget {
  const _WorkoutFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kIosChipRadius),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: LiftMotion.fast,
          curve: LiftMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? kAccentColor : Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(kIosChipRadius),
            border: Border.all(
              color:
                  selected
                      ? kAccentColor
                      : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color:
                  selected
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateDetailBottomBar extends StatelessWidget {
  const _TemplateDetailBottomBar({
    required this.hasActiveLiveWorkout,
    required this.onStartWorkout,
    required this.onResumeWorkout,
    required this.onTrends,
  });

  final bool hasActiveLiveWorkout;
  final VoidCallback onStartWorkout;
  final VoidCallback onResumeWorkout;
  final VoidCallback onTrends;

  @override
  Widget build(BuildContext context) {
    final label = hasActiveLiveWorkout ? 'Resume' : 'Start';
    final white = Colors.white.withValues(alpha: 0.96);
    return WorkoutDetailActionIsland(
      onSecondaryTap: onTrends,
      secondaryChild: MynauiIcon(
        MynauiGlyphs.courseUp,
        size: 23,
        color: Colors.black.withValues(alpha: 0.74),
      ),
      onPrimaryTap: hasActiveLiveWorkout ? onResumeWorkout : onStartWorkout,
      primaryLabel: label,
      primaryLeading:
          hasActiveLiveWorkout
              ? null
              : MynauiIcon(MynauiGlyphs.stopwatchPlay, size: 20, color: white),
      primaryWidth: hasActiveLiveWorkout ? 156 : 168,
    );
  }
}

class _TemplateEditorScreen extends StatelessWidget {
  const _TemplateEditorScreen({
    required this.template,
    required this.showBack,
    required this.onBack,
    required this.onSave,
    required this.nextExerciseId,
    required this.onOpenExerciseDetails,
  });

  final WorkoutTemplate template;
  final bool showBack;
  final VoidCallback onBack;
  final ValueChanged<WorkoutTemplate> onSave;
  final String Function() nextExerciseId;
  final ValueChanged<WorkoutTemplateExercise> onOpenExerciseDetails;

  @override
  Widget build(BuildContext context) {
    return _TemplateEditorForm(
      template: template,
      showBack: showBack,
      onBack: onBack,
      nextExerciseId: nextExerciseId,
      onOpenExerciseDetails: onOpenExerciseDetails,
      onSave: onSave,
    );
  }
}

class _TemplateEditorForm extends StatefulWidget {
  const _TemplateEditorForm({
    required this.template,
    required this.showBack,
    required this.onBack,
    required this.nextExerciseId,
    required this.onOpenExerciseDetails,
    required this.onSave,
  });

  final WorkoutTemplate template;
  final bool showBack;
  final VoidCallback onBack;
  final String Function() nextExerciseId;
  final ValueChanged<WorkoutTemplateExercise> onOpenExerciseDetails;
  final ValueChanged<WorkoutTemplate> onSave;

  @override
  State<_TemplateEditorForm> createState() => _TemplateEditorFormState();
}

class _TemplateEditorFormState extends State<_TemplateEditorForm> {
  static const int _minTargetDurationMinutes = 20;
  static const int _maxTargetDurationMinutes = 120;
  static const int _targetDurationStepMinutes = 5;

  late final ScrollController _editorScrollController;
  late final TextEditingController _nameController;
  late final TextEditingController _imageController;
  late final FixedExtentScrollController _durationDialController;
  late int _durationMinutes;
  late List<WorkoutTemplateExercise> _exercises;
  final Set<String> _expandedExerciseIds = <String>{};
  late final List<int> _durationDialValues = List<int>.generate(
    ((_maxTargetDurationMinutes - _minTargetDurationMinutes) ~/
            _targetDurationStepMinutes) +
        1,
    (index) => _minTargetDurationMinutes + (index * _targetDurationStepMinutes),
  );
  WorkoutTemplate get _draftTemplatePreview {
    final tags = _derivedFocusTagsFromExercises(_exercises);
    return widget.template.copyWith(
      name:
          _nameController.text.trim().isEmpty
              ? widget.template.name
              : _nameController.text.trim(),
      imageUrl:
          _imageController.text.trim().isEmpty
              ? widget.template.imageUrl
              : _imageController.text.trim(),
      durationMinutes: _durationMinutes,
      focusTags: tags.isEmpty ? const ['Custom'] : tags,
      exercises: _exercises,
    );
  }

  int get _estimatedDurationFromExercisesMinutes {
    if (_exercises.isEmpty) return _durationMinutes;
    final exerciseMinutes = _exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.estimatedMinutes,
    );
    final restSeconds = _exercises.fold<int>(
      0,
      (sum, exercise) =>
          sum +
          exercise.presetRows.fold<int>(
            0,
            (restSum, row) => restSum + row.restSeconds,
          ),
    );
    return exerciseMinutes + (restSeconds / 60).ceil();
  }

  int get _durationOverTargetMinutes =>
      math.max(0, _estimatedDurationFromExercisesMinutes - _durationMinutes);

  int _durationDialIndexFor(int minutes) {
    final rawIndex =
        ((minutes - _minTargetDurationMinutes) / _targetDurationStepMinutes)
            .round();
    return math.max(0, math.min(_durationDialValues.length - 1, rawIndex));
  }

  int _durationDialValueAt(int index) {
    final safeIndex = math.max(
      0,
      math.min(_durationDialValues.length - 1, index),
    );
    return _durationDialValues[safeIndex];
  }

  int _snapDurationToDial(int minutes) =>
      _durationDialValueAt(_durationDialIndexFor(minutes));

  @override
  void initState() {
    super.initState();
    _editorScrollController = ScrollController();
    _nameController = TextEditingController(text: widget.template.name);
    _imageController = TextEditingController(text: widget.template.imageUrl);
    _durationMinutes = _snapDurationToDial(widget.template.durationMinutes);
    _durationDialController = FixedExtentScrollController(
      initialItem: _durationDialIndexFor(_durationMinutes),
    );
    _exercises = List<WorkoutTemplateExercise>.from(widget.template.exercises);
    _expandedExerciseIds.addAll(_exercises.map((e) => e.id));
  }

  @override
  void dispose() {
    _editorScrollController.dispose();
    _nameController.dispose();
    _imageController.dispose();
    _durationDialController.dispose();
    super.dispose();
  }

  String _formatDuration(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) return '$hours hour';
      return '${hours}hr ${mins}mins';
    }
    return '$minutes mins';
  }

  String _formatRest(int seconds) {
    final minutes = seconds ~/ 60;
    final rem = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rem';
  }

  List<String> _derivedFocusTagsFromExercises(
    List<WorkoutTemplateExercise> exercises,
  ) {
    final tags = <String>{};
    for (final exercise in exercises) {
      final name = exercise.name.toLowerCase();
      final isForearmFocused =
          name.contains('forearm') ||
          name.contains('wrist') ||
          name.contains('grip') ||
          name.contains('farmer') ||
          name.contains('reverse curl') ||
          name.contains('pronation') ||
          name.contains('supination');
      if (name.contains('ham')) tags.add('Hamstrings');
      if (name.contains('quad') ||
          name.contains('leg press') ||
          name.contains('squat') ||
          name.contains('leg extension')) {
        tags.add('Quads');
      }
      if (name.contains('glute') ||
          name.contains('leg press') ||
          name.contains('hip')) {
        tags.add('Glutes');
      }
      if (name.contains('lat') ||
          name.contains('row') ||
          name.contains('pull')) {
        tags.add('Back');
      }
      if (isForearmFocused) tags.add('Forearms');
      if ((name.contains('bicep') ||
              (name.contains('curl') && !name.contains('ham'))) &&
          !isForearmFocused &&
          !name.contains('tricep')) {
        tags.add('Biceps');
      }
      if (name.contains('press') && !name.contains('leg')) tags.add('Chest');
      if (name.contains('shoulder') || name.contains('lateral')) {
        tags.add('Shoulders');
      }
      if (name.contains('tricep') ||
          name.contains('pushdown') ||
          name.contains('skull crusher') ||
          name.contains('overhead extension') ||
          name.contains('dip')) {
        tags.add('Triceps');
      }
      if (name.contains('ab') ||
          name.contains('core') ||
          name.contains('plank')) {
        tags.add('Core');
      }
      if (name.contains('cardio') ||
          name.contains('walk') ||
          name.contains('run')) {
        tags.add('Conditioning');
      }
    }
    if (tags.isEmpty) return const ['Custom'];
    return tags.take(4).toList();
  }

  Future<void> _pickHeroImageFromGallery() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(baseDir.path, 'template_hero_images'));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final ext = p.extension(x.path);
      final safeExt =
          ext.isNotEmpty && ext.length <= 6 && ext != '.' ? ext : '.jpg';
      final destPath = p.join(
        destDir.path,
        'hero_${DateTime.now().millisecondsSinceEpoch}$safeExt',
      );
      await File(x.path).copy(destPath);
      if (!mounted) return;
      setState(() => _imageController.text = destPath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save image. Try again.')),
      );
    }
  }

  Future<void> _editHeroImage() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Header image',
            subtitle: _draftTemplatePreview.name,
            children: [
              LiftMenuActionTile(
                icon: const MynauiIcon(
                  MynauiGlyphs.upload,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Upload image',
                subtitle: 'Choose from your photo library',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickHeroImageFromGallery();
                },
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: const MynauiIcon(
                  MynauiGlyphs.linkCircle,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Use image URL',
                subtitle: 'Paste a direct image link',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _promptForHeroImageUrl();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptForHeroImageUrl() async {
    final result = await showLiftTextInputDialog<String>(
      context: context,
      title: 'Hero image URL',
      message: 'Paste a direct link to an image (e.g. .jpg or .png).',
      initialValue: _imageController.text,
      keyboardType: TextInputType.url,
      hintText: 'https://...',
      confirmLabel: 'Use URL',
      parser: (value) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      },
    );
    if (result == null || result.isEmpty) return;
    setState(() => _imageController.text = result);
  }

  void _updateExerciseRows(
    WorkoutTemplateExercise exercise,
    List<WorkoutTemplateSetRow> rows,
  ) {
    setState(() {
      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index < 0) return;
      _exercises[index] = _exercises[index].copyWith(
        presetRows: rows,
        setCount: rows.length,
      );
    });
  }

  _SwapExerciseCatalogItem? _catalogItemForExerciseName(String name) {
    final needle = name.trim().toLowerCase();
    for (final item in _kSwapExerciseCatalog) {
      if (item.name.toLowerCase() == needle) return item;
    }
    for (final item in _kSwapExerciseCatalog) {
      if (item.name.toLowerCase().contains(needle) ||
          needle.contains(item.name.toLowerCase())) {
        return item;
      }
    }
    return null;
  }

  List<String> _heuristicMuscleTagsForName(String rawName) {
    final name = rawName.toLowerCase();
    final tags = <String>{};
    final isForearmFocused =
        name.contains('forearm') ||
        name.contains('wrist') ||
        name.contains('grip') ||
        name.contains('farmer') ||
        name.contains('reverse curl') ||
        name.contains('pronation') ||
        name.contains('supination');
    if (name.contains('ham')) tags.add('Hamstrings');
    if (name.contains('quad') ||
        name.contains('leg press') ||
        name.contains('squat') ||
        name.contains('leg extension')) {
      tags.add('Quads');
    }
    if (name.contains('glute') ||
        name.contains('leg press') ||
        name.contains('hip')) {
      tags.add('Glutes');
    }
    if (name.contains('lat') || name.contains('row') || name.contains('pull')) {
      tags.add('Back');
    }
    if (isForearmFocused) {
      tags.add('Forearms');
    }
    if ((name.contains('bicep') ||
            (name.contains('curl') && !name.contains('ham'))) &&
        !isForearmFocused &&
        !name.contains('tricep')) {
      tags.add('Biceps');
    }
    if (name.contains('press') && !name.contains('leg')) {
      tags.add('Chest');
    }
    if (name.contains('shoulder') || name.contains('lateral')) {
      tags.add('Shoulders');
    }
    if (name.contains('tricep') ||
        name.contains('pushdown') ||
        name.contains('skull crusher') ||
        name.contains('overhead extension') ||
        name.contains('dip')) {
      tags.add('Triceps');
    }
    if (name.contains('ab') ||
        name.contains('core') ||
        name.contains('plank')) {
      tags.add('Core');
    }
    if (name.contains('cardio') ||
        name.contains('walk') ||
        name.contains('run')) {
      tags.add('Conditioning');
    }
    return tags.toList();
  }

  Set<String> _swapSimilarityTokens(
    String name, [
    List<String> keywords = const [],
  ]) {
    final tokens = <String>{};
    final normalized = name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9 ]'),
      ' ',
    );
    for (final token in normalized.split(RegExp(r'\s+'))) {
      if (token.length >= 3) tokens.add(token);
    }
    tokens.addAll(keywords.map((e) => e.toLowerCase()));
    return tokens;
  }

  List<_SwapExerciseCatalogItem> _rankedSwapSuggestions(
    WorkoutTemplateExercise exercise,
  ) {
    final current = _catalogItemForExerciseName(exercise.name);
    final targetMuscles = <String>{
      ...(current?.muscleGroups ?? _heuristicMuscleTagsForName(exercise.name)),
    };
    final targetEquipment = current?.equipment;
    final targetTokens = _swapSimilarityTokens(
      exercise.name,
      current?.keywords ?? const [],
    );

    final scored = <MapEntry<_SwapExerciseCatalogItem, int>>[];
    for (final item in _kSwapExerciseCatalog) {
      if (item.name.toLowerCase() == exercise.name.toLowerCase()) continue;
      final sharedMuscles =
          item.muscleGroups.where(targetMuscles.contains).length;
      final sharedTokens = item.keywords.where(targetTokens.contains).length;
      final nameTokens =
          _swapSimilarityTokens(
            item.name,
            item.keywords,
          ).where(targetTokens.contains).length;

      var score = 0;
      score += sharedMuscles * 4;
      score += sharedTokens * 2;
      score += nameTokens;
      if (targetEquipment != null && item.equipment == targetEquipment) {
        score += 3;
      }
      if (score > 0) {
        scored.add(MapEntry(item, score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.value.compareTo(a.value);
      if (scoreCompare != 0) return scoreCompare;
      return a.key.name.compareTo(b.key.name);
    });
    return scored.take(6).map((e) => e.key).toList();
  }

  String _swapExerciseSubtitle(_SwapExerciseCatalogItem item) {
    return '${item.muscleGroups.join(' • ')}  •  ${item.equipment.label}';
  }

  bool _catalogItemMatchesSearch(_SwapExerciseCatalogItem item, String q) {
    if (q.isEmpty) return true;
    final lower = q.toLowerCase();
    if (item.name.toLowerCase().contains(lower)) return true;
    for (final m in item.muscleGroups) {
      if (m.toLowerCase().contains(lower)) return true;
    }
    if (item.equipment.label.toLowerCase().contains(lower)) return true;
    for (final k in item.keywords) {
      if (k.contains(lower)) return true;
    }
    return false;
  }

  List<WorkoutTemplateSetRow> _defaultPresetRowsForExercise() {
    return const [
      WorkoutTemplateSetRow(
        label: 'W',
        reps: 12,
        weightKg: 20,
        restSeconds: 90,
      ),
      WorkoutTemplateSetRow(
        label: '1',
        reps: 10,
        weightKg: 40,
        restSeconds: 120,
      ),
      WorkoutTemplateSetRow(
        label: '2',
        reps: 10,
        weightKg: 40,
        restSeconds: 120,
      ),
    ];
  }

  WorkoutTemplateExercise _newExerciseFromCatalogName(String name) {
    return WorkoutTemplateExercise(
      id: widget.nextExerciseId(),
      name: name,
      setCount: 3,
      estimatedMinutes: 15,
      presetRows: _defaultPresetRowsForExercise(),
    );
  }

  Future<String?> _pickExerciseNameFromCatalog({
    WorkoutTemplateExercise? replacingExercise,
  }) async {
    final currentCatalogItem =
        replacingExercise == null
            ? null
            : _catalogItemForExerciseName(replacingExercise.name);
    final suggested =
        replacingExercise == null
            ? const <_SwapExerciseCatalogItem>[]
            : _rankedSwapSuggestions(replacingExercise);
    final allMuscleGroups =
        _kSwapExerciseCatalog
            .expand((item) => item.muscleGroups)
            .toSet()
            .toList()
          ..sort();

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        String? selectedMuscleGroup =
            currentCatalogItem?.muscleGroups.isNotEmpty == true
                ? currentCatalogItem!.muscleGroups.first
                : null;
        _SwapExerciseEquipment? selectedEquipment =
            currentCatalogItem?.equipment;
        var searchQuery = '';
        var filtersExpanded = false;
        var catalogHeaderHeight = 0.0;
        final catalogHeaderKey = GlobalKey();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredExercises =
                _kSwapExerciseCatalog.where((item) {
                    final matchesMuscle =
                        selectedMuscleGroup == null ||
                        item.muscleGroups.contains(selectedMuscleGroup);
                    final matchesEquipment =
                        selectedEquipment == null ||
                        item.equipment == selectedEquipment;
                    return matchesMuscle &&
                        matchesEquipment &&
                        _catalogItemMatchesSearch(item, searchQuery);
                  }).toList()
                  ..sort((a, b) => a.name.compareTo(b.name));

            final suggestedFiltered =
                suggested
                    .where(
                      (item) => _catalogItemMatchesSearch(item, searchQuery),
                    )
                    .toList();

            final filterSummary =
                '${selectedMuscleGroup ?? 'All muscles'} · ${selectedEquipment?.label ?? 'All equipment'}';

            final sheetRadius = BorderRadius.vertical(
              top: Radius.circular(kIosSurfaceRadius),
            );

            final sheetMaxHeight = math.min(
              MediaQuery.sizeOf(context).height * 0.88,
              720.0,
            );
            final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

            void syncCatalogHeaderHeight() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final measuredHeight =
                    catalogHeaderKey.currentContext?.size?.height;
                if (measuredHeight == null) return;
                if ((measuredHeight - catalogHeaderHeight).abs() < 0.5) return;
                setModalState(() {
                  catalogHeaderHeight = measuredHeight;
                });
              });
            }

            Future<void> handleMachineScan() async {
              final picked = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder:
                      (_) => const MachineScanFlowScreen(
                        machine: MockMachines.swivelHandleRow,
                        returnExerciseOnTap: true,
                      ),
                ),
              );
              final name = picked?.trim();
              if (name == null || name.isEmpty) return;
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop(name);
            }

            Widget buildCatalogHeader() {
              return Padding(
                key: catalogHeaderKey,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SectionBoundary(
                  floating: true,
                  floatingBackgroundOpacity: 0.98,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kIosCornerRadius),
                          border: Border.all(
                            color: Colors.grey.shade300.withValues(alpha: 0.6),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        child: TextField(
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) {
                            setModalState(
                              () => searchQuery = v.trim().toLowerCase(),
                            );
                          },
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF171717),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            icon: MynauiIcon(
                              MynauiGlyphs.magnifer,
                              color: kAccentColor,
                              size: 21,
                            ),
                            hintText: 'Search exercises',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap:
                              () => setModalState(
                                () => filtersExpanded = !filtersExpanded,
                              ),
                          borderRadius: BorderRadius.circular(kIosCornerRadius),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                MynauiIcon(
                                  MynauiGlyphs.filter,
                                  size: 20,
                                  color: Colors.grey.shade800,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Muscle & equipment',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        filterSummary,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  filtersExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: Colors.grey.shade600,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (filtersExpanded) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Muscle groups',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _WorkoutFilterChip(
                                label: 'All',
                                selected: selectedMuscleGroup == null,
                                onTap: () {
                                  setModalState(
                                    () => selectedMuscleGroup = null,
                                  );
                                },
                              ),
                              ...allMuscleGroups.map(
                                (group) => _WorkoutFilterChip(
                                  label: group,
                                  selected: selectedMuscleGroup == group,
                                  onTap: () {
                                    setModalState(() {
                                      selectedMuscleGroup =
                                          selectedMuscleGroup == group
                                              ? null
                                              : group;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Equipment',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _WorkoutFilterChip(
                                label: 'All',
                                selected: selectedEquipment == null,
                                onTap: () {
                                  setModalState(() => selectedEquipment = null);
                                },
                              ),
                              ..._SwapExerciseEquipment.values.map(
                                (equipment) => _WorkoutFilterChip(
                                  label: equipment.label,
                                  selected: selectedEquipment == equipment,
                                  onTap: () {
                                    setModalState(() {
                                      selectedEquipment =
                                          selectedEquipment == equipment
                                              ? null
                                              : equipment;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              );
            }

            syncCatalogHeaderHeight();

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: ClipRRect(
                  borderRadius: sheetRadius,
                  clipBehavior: Clip.hardEdge,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: sheetRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFFF1F2F5).withValues(alpha: 0.78),
                            const Color(0xFFE7E9EE).withValues(alpha: 0.70),
                            const Color(0xFFF3F4F7).withValues(alpha: 0.84),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 34,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        left: false,
                        right: false,
                        child: SizedBox(
                          height: sheetMaxHeight + bottomInset,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Center(
                                child: Container(
                                  width: 48,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.09),
                                    borderRadius: kIosChipBorderRadius,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            replacingExercise == null
                                                ? 'Add exercise'
                                                : 'Swap exercise',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: -0.4,
                                              color: Color(0xFF161616),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        LiftMenuHeaderIconButton(
                                          onTap:
                                              () => unawaited(
                                                handleMachineScan(),
                                              ),
                                          child: MynauiIcon(
                                            MynauiGlyphs.qrCode,
                                            size: 28,
                                            color: kAccentColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      replacingExercise == null
                                          ? 'Choose an exercise for this workout'
                                          : 'Replacing ${replacingExercise.name}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF74808E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ClipRect(
                                        child: ShaderMask(
                                          blendMode: BlendMode.dstIn,
                                          shaderCallback: (bounds) {
                                            final hiddenFraction =
                                                bounds.height <= 0
                                                    ? 0.0
                                                    : ((catalogHeaderHeight +
                                                                8) /
                                                            bounds.height)
                                                        .clamp(0.0, 1.0);
                                            final revealFraction = math.min(
                                              1.0,
                                              hiddenFraction + 0.02,
                                            );
                                            return LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: const [
                                                Colors.transparent,
                                                Colors.transparent,
                                                Colors.white,
                                                Colors.white,
                                              ],
                                              stops: [
                                                0.0,
                                                hiddenFraction,
                                                revealFraction,
                                                1.0,
                                              ],
                                            ).createShader(bounds);
                                          },
                                          child: CustomScrollView(
                                            slivers: [
                                              SliverToBoxAdapter(
                                                child: SizedBox(
                                                  height:
                                                      catalogHeaderHeight > 0
                                                          ? catalogHeaderHeight +
                                                              8
                                                          : 0,
                                                ),
                                              ),
                                              SliverPadding(
                                                padding: EdgeInsets.fromLTRB(
                                                  14,
                                                  4,
                                                  14,
                                                  14 + bottomInset,
                                                ),
                                                sliver: SliverList(
                                                  delegate: SliverChildListDelegate([
                                                    if (suggestedFiltered
                                                        .isNotEmpty) ...[
                                                      const _SwapSectionTitle(
                                                        'Suggested exercises',
                                                      ),
                                                      const SizedBox(height: 8),
                                                      for (
                                                        var index = 0;
                                                        index <
                                                            suggestedFiltered
                                                                .length;
                                                        index++
                                                      ) ...[
                                                        _SwapExerciseTile(
                                                          title:
                                                              suggestedFiltered[index]
                                                                  .name,
                                                          subtitle:
                                                              _swapExerciseSubtitle(
                                                                suggestedFiltered[index],
                                                              ),
                                                          isCurrent:
                                                              suggestedFiltered[index]
                                                                  .name ==
                                                              replacingExercise
                                                                  ?.name,
                                                          onTap:
                                                              () => Navigator.pop(
                                                                sheetContext,
                                                                suggestedFiltered[index]
                                                                    .name,
                                                              ),
                                                        ),
                                                        if (index <
                                                            suggestedFiltered
                                                                    .length -
                                                                1)
                                                          const _SwapExerciseDivider(),
                                                      ],
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                    ],
                                                    _SwapSectionTitle(
                                                      'Exercises (${filteredExercises.length})',
                                                    ),
                                                    const SizedBox(height: 8),
                                                    for (
                                                      var index = 0;
                                                      index <
                                                          filteredExercises
                                                              .length;
                                                      index++
                                                    ) ...[
                                                      _SwapExerciseTile(
                                                        title:
                                                            filteredExercises[index]
                                                                .name,
                                                        subtitle:
                                                            _swapExerciseSubtitle(
                                                              filteredExercises[index],
                                                            ),
                                                        isCurrent:
                                                            filteredExercises[index]
                                                                .name ==
                                                            replacingExercise
                                                                ?.name,
                                                        onTap:
                                                            () => Navigator.pop(
                                                              sheetContext,
                                                              filteredExercises[index]
                                                                  .name,
                                                            ),
                                                      ),
                                                      if (index <
                                                          filteredExercises
                                                                  .length -
                                                              1)
                                                        const _SwapExerciseDivider(),
                                                    ],
                                                  ]),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 0,
                                      child: buildCatalogHeader(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return null;
    if (selected == replacingExercise?.name) return null;
    return selected;
  }

  Future<void> _addExerciseFromCatalog() async {
    final selected = await _pickExerciseNameFromCatalog();
    if (selected == null) return;

    final result = _newExerciseFromCatalogName(selected);

    setState(() {
      _exercises.add(result);
      _expandedExerciseIds.add(result.id);
    });
  }

  Future<void> _swapExercise(WorkoutTemplateExercise exercise) async {
    final selected = await _pickExerciseNameFromCatalog(
      replacingExercise: exercise,
    );
    if (selected == null) return;

    setState(() {
      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index < 0) return;
      _exercises[index] = _exercises[index].copyWith(name: selected);
    });
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      if (oldIndex == newIndex) return;
      final item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);
    });
  }

  Widget _exerciseReorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    EdgeInsetsGeometry outerPadding = EdgeInsets.zero;
    Widget content = child;
    if (child is Padding) {
      outerPadding = child.padding;
      content = child.child ?? const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: animation,
      child: content,
      builder: (context, proxyChild) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Padding(
          padding: outerPadding,
          child: Transform.scale(
            scale: 1 + (0.008 * t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kIosCornerRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10 + (0.06 * t)),
                    blurRadius: 14 + (6 * t),
                    offset: Offset(0, 6 + (2 * t)),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kIosCornerRadius),
                  child: proxyChild,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editSetTypeCell(
    WorkoutTemplateExercise exercise,
    int rowIndex,
  ) async {
    const options = ['Warmup', 'Working set', 'Cooldown'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kIosCornerRadius),
        ),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ...options.map(
                (option) => ListTile(
                  title: Text(option),
                  onTap: () => Navigator.pop(context, option),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    final rows = List<WorkoutTemplateSetRow>.from(exercise.presetRows);
    rows[rowIndex] = rows[rowIndex].copyWith(label: selected);
    _updateExerciseRows(exercise, rows);
  }

  Future<void> _editRepsCell(
    WorkoutTemplateExercise exercise,
    int rowIndex,
  ) async {
    final value = await showLiftTextInputDialog<int>(
      context: context,
      title: 'Edit reps',
      initialValue: exercise.presetRows[rowIndex].reps.toString(),
      keyboardType: TextInputType.number,
      labelText: 'Reps',
      parser: (value) {
        final reps = int.tryParse(value.trim());
        return reps?.clamp(0, 99);
      },
    );
    if (value == null) return;
    final rows = List<WorkoutTemplateSetRow>.from(exercise.presetRows);
    rows[rowIndex] = rows[rowIndex].copyWith(reps: value);
    _updateExerciseRows(exercise, rows);
  }

  Future<void> _editWeightCell(
    WorkoutTemplateExercise exercise,
    int rowIndex,
  ) async {
    final current = exercise.presetRows[rowIndex].weightKg;
    final weight = await _showWeightPicker(current);
    if (weight == null) return;
    final rows = List<WorkoutTemplateSetRow>.from(exercise.presetRows);
    rows[rowIndex] = rows[rowIndex].copyWith(weightKg: weight);
    _updateExerciseRows(exercise, rows);
  }

  Future<double?> _showWeightPicker(double initialWeight) async {
    final values = List<double>.generate(161, (i) => i * 2.5); // 0..400kg
    int selectedIndex = values.indexWhere(
      (v) => (v - initialWeight).abs() < 0.01,
    );
    if (selectedIndex == -1) {
      selectedIndex = (initialWeight / 2.5).round().clamp(0, values.length - 1);
    }
    double selectedValue = values[selectedIndex];

    final result = await showModalBottomSheet<double>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kIosCornerRadius),
        ),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SizedBox(
                height: 320,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(kIosCornerRadius),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${selectedValue.toStringAsFixed(selectedValue % 1 == 0 ? 0 : 1)} kg',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CupertinoPicker(
                        itemExtent: 36,
                        scrollController: FixedExtentScrollController(
                          initialItem: selectedIndex,
                        ),
                        onSelectedItemChanged: (index) {
                          selectedIndex = index;
                          setModalState(() => selectedValue = values[index]);
                        },
                        children:
                            values
                                .map(
                                  (v) => Center(
                                    child: Text(
                                      '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)} kg',
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final typed = await _promptTypedWeight(
                                  selectedValue,
                                );
                                if (!context.mounted) return;
                                if (typed == null) return;
                                Navigator.pop(context, typed);
                              },
                              child: const Text('Type in'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: kAccentColor,
                              ),
                              onPressed:
                                  () => Navigator.pop(context, selectedValue),
                              child: const Text('Use weight'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    return result;
  }

  Future<double?> _promptTypedWeight(double currentValue) async {
    return showLiftTextInputDialog<double>(
      context: context,
      title: 'Type weight',
      initialValue: currentValue.toStringAsFixed(currentValue % 1 == 0 ? 0 : 1),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      suffixText: 'kg',
      parser: (value) {
        final parsed = double.tryParse(value.trim());
        return parsed?.clamp(0, 400).toDouble();
      },
    );
  }

  Future<void> _editRestCell(
    WorkoutTemplateExercise exercise,
    int rowIndex,
  ) async {
    final current = exercise.presetRows[rowIndex].restSeconds;
    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kIosCornerRadius),
        ),
      ),
      builder: (context) {
        Duration temp = Duration(seconds: current);
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 340,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kIosCornerRadius),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Rest Timer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.ms,
                    initialTimerDuration: Duration(
                      minutes: temp.inMinutes,
                      seconds: temp.inSeconds % 60,
                    ),
                    onTimerDurationChanged: (duration) {
                      temp = duration;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentColor,
                      ),
                      onPressed: () => Navigator.pop(context, temp.inSeconds),
                      child: const Text('Use rest time'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    final rows = List<WorkoutTemplateSetRow>.from(exercise.presetRows);
    rows[rowIndex] = rows[rowIndex].copyWith(restSeconds: selected);
    _updateExerciseRows(exercise, rows);
  }

  Widget _buildEditableSetTable(WorkoutTemplateExercise exercise) {
    final rows = exercise.presetRows;
    return Column(
      children: [
        Row(
          children: const [
            _TableHeaderCell('SETS'),
            _TableHeaderCell('REPS'),
            _TableHeaderCell('WEIGHT'),
            _TableHeaderCell('REST'),
          ],
        ),
        const SizedBox(height: 6),
        ...rows.asMap().entries.map((entry) {
          final rowIndex = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: _EditableCell(
                    label: row.label,
                    onTap: () => _editSetTypeCell(exercise, rowIndex),
                  ),
                ),
                Expanded(
                  child: _EditableCell(
                    label: '${row.reps}',
                    onTap: () => _editRepsCell(exercise, rowIndex),
                  ),
                ),
                Expanded(
                  child: _EditableCell(
                    label:
                        row.weightKg <= 0
                            ? '--'
                            : '${row.weightKg.toStringAsFixed(row.weightKg % 1 == 0 ? 0 : 1)}KG',
                    onTap: () => _editWeightCell(exercise, rowIndex),
                  ),
                ),
                Expanded(
                  child: _EditableCell(
                    label:
                        row.restSeconds <= 0
                            ? '--'
                            : _formatRest(row.restSeconds),
                    onTap: () => _editRestCell(exercise, rowIndex),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _saveTemplate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final rawTags = _derivedFocusTagsFromExercises(_exercises);

    final template = widget.template.copyWith(
      name: name,
      imageUrl:
          _imageController.text.trim().isEmpty
              ? widget.template.imageUrl
              : _imageController.text.trim(),
      durationMinutes: _durationMinutes,
      focusTags: rawTags.isEmpty ? const ['Custom'] : rawTags,
      exercises: _exercises,
    );

    widget.onSave(template);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draftTemplatePreview;
    final topInset = MediaQuery.paddingOf(context).top;
    const islandTop = 16.0;
    const sectionGap = 12.0;
    const heroHeaderSeparation = sectionGap;
    final headerBottom = topInset + islandTop + kLiftIslandHeaderHeight;
    final listScrollTopPadding = headerBottom + heroHeaderSeparation;
    final topBlurBandHeight = listScrollTopPadding + 36.0;
    const gapAboveBottomIsland = 10.0;
    final listBottomPadding =
        kShellFloatingNavBottomInset +
        kLiftIslandHeaderHeight +
        gapAboveBottomIsland;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ListView(
            controller: _editorScrollController,
            primary: false,
            padding: EdgeInsets.fromLTRB(
              0,
              listScrollTopPadding,
              0,
              listBottomPadding,
            ),
            children: [
              Stack(
                children: [
                  _TemplateHeroDetailCard(
                    template: draft,
                    durationLabel: _formatDuration(
                      draft.estimatedDurationMinutes,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: InkWell(
                      onTap: _editHeroImage,
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      child: Ink(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(kIosCornerRadius),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                        ),
                        child: const Center(
                          child: MynauiIcon(
                            MynauiGlyphs.galleryMinimalistic,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SectionBoundary(
                borderRadius: kIosCornerRadius,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Template settings',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workout name',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 14, height: 1.35),
                          decoration: InputDecoration(
                            hintText: 'e.g. Leg day, Upper push',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                kIosCornerRadius,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                kIosCornerRadius,
                              ),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                kIosCornerRadius,
                              ),
                              borderSide: const BorderSide(
                                color: kAccentColor,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Muscles worked (generated from exercises)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          draft.focusTags
                              .map((tag) => _EditStateChip(label: tag))
                              .toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            'Target duration',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _DurationChip(label: '$_durationMinutes mins'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Estimated from exercise time + rest: $_estimatedDurationFromExercisesMinutes mins',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (_durationOverTargetMinutes > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kCautionColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(kIosCornerRadius),
                          border: Border.all(
                            color: kCautionColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: kCautionColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Current build is $_durationOverTargetMinutes min over your target duration.',
                                style: TextStyle(
                                  color: kCautionColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kIosCornerRadius),
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 96,
                            child: CupertinoPicker(
                              scrollController: _durationDialController,
                              itemExtent: 28,
                              useMagnifier: true,
                              magnification: 1.08,
                              diameterRatio: 1.25,
                              squeeze: 1.1,
                              selectionOverlay:
                                  CupertinoPickerDefaultSelectionOverlay(
                                    background: kAccentColor.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                              onSelectedItemChanged: (index) {
                                final nextValue = _durationDialValueAt(index);
                                if (nextValue == _durationMinutes) return;
                                setState(() => _durationMinutes = nextValue);
                              },
                              children:
                                  _durationDialValues
                                      .map(
                                        (minutes) => Center(
                                          child: Text(
                                            '$minutes mins',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              height: 1.1,
                                              color:
                                                  minutes == _durationMinutes
                                                      ? kAccentColor
                                                      : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Text(
                                  '$_minTargetDurationMinutes mins',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '$_maxTargetDurationMinutes mins',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Exercises (${_exercises.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_exercises.isEmpty)
                SectionBoundary(
                  borderRadius: kIosCornerRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No exercises yet.\nAdd one to start building this workout.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  clipBehavior: Clip.hardEdge,
                  buildDefaultDragHandles: false,
                  proxyDecorator: _exerciseReorderProxyDecorator,
                  itemCount: _exercises.length,
                  onReorder: _reorderExercises,
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    return Padding(
                      key: ValueKey(exercise.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ReorderableDelayedDragStartListener(
                        index: index,
                        child: _ExerciseDetailCard(
                          exercise: exercise,
                          isExpanded: _expandedExerciseIds.contains(
                            exercise.id,
                          ),
                          restFormatter: _formatRest,
                          onOpenDetails:
                              () => widget.onOpenExerciseDetails(exercise),
                          onToggle: () {
                            setState(() {
                              if (_expandedExerciseIds.contains(exercise.id)) {
                                _expandedExerciseIds.remove(exercise.id);
                              } else {
                                _expandedExerciseIds.add(exercise.id);
                              }
                            });
                          },
                          expandedTable: _buildEditableSetTable(exercise),
                          footer: Row(
                            children: [
                              const Spacer(),
                              InkWell(
                                onTap: () => _swapExercise(exercise),
                                borderRadius: BorderRadius.circular(
                                  kIosCornerRadius,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      kIosCornerRadius,
                                    ),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MynauiIcon(
                                        MynauiGlyphs.sortHorizontal,
                                        size: 18,
                                        color: Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Swap',
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _exercises.removeWhere(
                                      (e) => e.id == exercise.id,
                                    );
                                    _expandedExerciseIds.remove(exercise.id);
                                  });
                                },
                                borderRadius: BorderRadius.circular(
                                  kIosCornerRadius,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      kIosCornerRadius,
                                    ),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MynauiIcon(
                                        MynauiGlyphs.trashBin,
                                        size: 18,
                                        color: Colors.red.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Remove',
                                        style: TextStyle(
                                          color: Colors.red.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Tip: hold and drag an exercise card to rearrange. Tap a card to collapse/expand while editing.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topBlurBandHeight,
          child: IgnorePointer(
            child: const StaticFeatheredTopBlurScrim(blurSigma: 24),
          ),
        ),
        Positioned(
          top: topInset + islandTop,
          left: 0,
          right: 0,
          child: _TemplatesHeader(
            scrollController: _editorScrollController,
            center: const SizedBox.shrink(),
            showBack: widget.showBack,
            onBack: widget.onBack,
            backButtonIcon: const MynauiIcon(
              MynauiGlyphs.closeCircle,
              size: 24,
              color: kLiftIslandOnFrosted,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: kShellFloatingNavBottomInset,
          child: SafeArea(
            top: false,
            bottom: false,
            child: WorkoutDetailActionIsland(
              onSecondaryTap: _addExerciseFromCatalog,
              secondaryChild: MynauiIcon(
                MynauiGlyphs.addCircle,
                size: 28,
                color: Colors.black.withValues(alpha: 0.74),
              ),
              onPrimaryTap: _saveTemplate,
              primaryLabel: 'Save',
              primaryLeading: MynauiIcon(
                MynauiGlyphs.checkCircle,
                size: 20,
                color: Colors.white.withValues(alpha: 0.96),
              ),
              primaryWidth: 156,
            ),
          ),
        ),
      ],
    );
  }
}

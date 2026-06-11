import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/progress/leg_day_trends/leg_day_trends_page.dart';
import 'package:lift/features/workout/exercise_details/exercise_detail_page.dart';
import 'package:lift/shared/exercise_demo_images.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/models/workout_template.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/workout_detail_action_island.dart';
import 'package:lift/shared/widgets/workout_template_hero_image.dart';

enum _WorkoutMenuAction { edit, review, share }

Widget _alignedWorkoutBackIcon({
  Color color = kLiftIslandOnFrosted,
  double size = 22,
}) {
  return MynauiIcon(MynauiGlyphs.altArrowLeft, color: color, size: size);
}

void _openExerciseDetail(
  BuildContext context,
  WorkoutTemplateExercise exercise,
) {
  pushExerciseDetailPage(context, exerciseName: exercise.name);
}

class TodayWorkoutDetailScreen extends StatefulWidget {
  const TodayWorkoutDetailScreen({
    super.key,
    required this.template,
    required this.history,
    required this.onEdit,
    required this.onStart,

    /// When true (e.g. home hero or calendar row for **today**), primary is Start.
    /// When false, primary is Edit — user can still open trends from the secondary control.
    this.allowStart = true,
    this.heroUnderHeader = true,
  });

  final WorkoutTemplate template;
  final List<WorkoutHistoryEntry> history;
  final VoidCallback onEdit;
  final VoidCallback onStart;
  final bool allowStart;
  final bool heroUnderHeader;

  @override
  State<TodayWorkoutDetailScreen> createState() =>
      _TodayWorkoutDetailScreenState();
}

class _TodayWorkoutDetailScreenState extends State<TodayWorkoutDetailScreen> {
  final Set<String> _expandedExerciseIds = <String>{};
  final ScrollController _detailScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.template.exercises.isNotEmpty) {
      _expandedExerciseIds.add(widget.template.exercises.first.id);
    }
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  List<WorkoutHistoryEntry> get _historyForTemplate {
    final key = widget.template.name.trim().toLowerCase();
    final matches = widget.history
        .where((entry) => entry.workoutName.trim().toLowerCase() == key)
        .toList(growable: false);
    final sorted = List<WorkoutHistoryEntry>.from(matches);
    sorted.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return sorted;
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

  void _openTrends() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LegDayTrendsPage(template: widget.template),
      ),
    );
  }

  void _handleEdit() {
    widget.onEdit();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _handleStart() {
    widget.onStart();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _handleMenuSelection(_WorkoutMenuAction action) {
    switch (action) {
      case _WorkoutMenuAction.edit:
        _handleEdit();
        break;
      case _WorkoutMenuAction.review:
        _openReview();
        break;
      case _WorkoutMenuAction.share:
        _shareWorkout();
        break;
    }
  }

  Future<void> _showWorkoutOptionsSheet() async {
    final action = await showModalBottomSheet<_WorkoutMenuAction>(
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
            subtitle: widget.template.name,
            children: [
              LiftMenuActionTile(
                icon: MynauiIcon(
                  MynauiGlyphs.editOne,
                  size: 22,
                  color: kAccentColor,
                ),
                title: 'Edit workout',
                onTap: () {
                  Navigator.of(sheetContext).pop(_WorkoutMenuAction.edit);
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
                  Navigator.of(sheetContext).pop(_WorkoutMenuAction.review);
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
                  Navigator.of(sheetContext).pop(_WorkoutMenuAction.share);
                },
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    _handleMenuSelection(action);
  }

  void _openReview() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => _WorkoutReviewScreen(
              template: widget.template,
              history: _historyForTemplate,
            ),
      ),
    );
  }

  void _shareWorkout() async {
    final text = '''
Workout: ${widget.template.name}
Duration: ${widget.template.estimatedDurationMinutes} min
Exercises: ${widget.template.exercises.length}
''';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showWorkoutDetailSnackBar('Workout info copied to clipboard');
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

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    // The floating action island is already positioned above the home indicator,
    // so only reserve to the top of the island plus a small visual gap.
    const gapAboveBottomIsland = 10.0;
    final listBottomPadding =
        kShellFloatingNavBottomInset +
        kLiftIslandHeaderHeight +
        gapAboveBottomIsland;

    final exercises = widget.template.exercises;
    final totalExercises = exercises.length;
    final totalSets = exercises.fold<int>(
      0,
      (sum, ex) => sum + ex.presetRows.length,
    );
    final totalRestSeconds = exercises.fold<int>(
      0,
      (sum, ex) =>
          sum +
          ex.presetRows.fold<int>(0, (inner, row) => inner + row.restSeconds),
    );
    final totalRestLabel = _formatRest(totalRestSeconds);

    const islandTopOffset = 10.0;
    const sectionGap = 12.0;
    final islandTop = topInset + islandTopOffset;
    final listTopPadding =
        widget.heroUnderHeader
            ? 0.0
            : islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final topOverlayHeight =
        islandTop +
        kLiftIslandHeaderHeight +
        (widget.heroUnderHeader ? 36 : kIslandHeaderGap);

    return Scaffold(
      extendBody: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: liftCanvasColor(context),
      body: Stack(
        children: [
          ListView(
            controller: _detailScrollController,
            primary: false,
            padding: EdgeInsets.fromLTRB(
              kPagePadding,
              listTopPadding,
              kPagePadding,
              listBottomPadding,
            ),
            children: [
              _HeroWorkoutCard(
                template: widget.template,
                durationLabel: _formatDuration(
                  widget.template.estimatedDurationMinutes,
                ),
              ),
              const SizedBox(height: sectionGap),
              _WorkoutTemplateSummary(
                exerciseCount: totalExercises,
                totalSetCount: totalSets,
                totalRestLabel: totalRestLabel,
                focusTags: widget.template.focusTags,
              ),
              const SizedBox(height: sectionGap),
              ...exercises.map((exercise) {
                final isExpanded = _expandedExerciseIds.contains(exercise.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: sectionGap),
                  child: _ExercisePreviewCard(
                    exercise: exercise,
                    restFormatter: _formatRest,
                    isExpanded: isExpanded,
                    onOpenDetails: () => _openExerciseDetail(context, exercise),
                    onToggle: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedExerciseIds.remove(exercise.id);
                        } else {
                          _expandedExerciseIds.add(exercise.id);
                        }
                      });
                    },
                  ),
                );
              }),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topOverlayHeight,
            child: IgnorePointer(
              child: ScrollLinkedTopBlurScrim(
                scrollController: _detailScrollController,
                scrollRampDistance: 120,
                maxBlurSigma: 16,
                topTint: const Color(0xFFF7F7F8),
                maxTintOpacity: 0.28,
              ),
            ),
          ),
          Positioned(
            top: islandTop,
            left: kPagePadding,
            right: kPagePadding,
            child: LiftIslandHeader(
              center: const SizedBox.shrink(),
              scrollController: _detailScrollController,
              collapseScrollDistance: 28,
              leading: LiftIslandHeaderAction(
                onTap: () => Navigator.of(context).pop(),
                child: _alignedWorkoutBackIcon(),
              ),
              trailing: LiftIslandHeaderAction(
                onTap: _showWorkoutOptionsSheet,
                child: const MynauiIcon(
                  MynauiGlyphs.menuDotsCircle,
                  color: kLiftIslandOnFrosted,
                  size: 22,
                ),
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
              child: _DetailBottomBar(
                onTrends: _openTrends,
                allowStart: widget.allowStart,
                onStart: _handleStart,
                onEdit: _handleEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBottomBar extends StatelessWidget {
  const _DetailBottomBar({
    required this.onTrends,
    required this.allowStart,
    required this.onStart,
    required this.onEdit,
  });

  final VoidCallback onTrends;
  final bool allowStart;
  final VoidCallback onStart;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return WorkoutDetailActionIsland(
      onSecondaryTap: onTrends,
      secondaryChild: MynauiIcon(
        MynauiGlyphs.courseUp,
        size: 23,
        color: Colors.black.withValues(alpha: 0.74),
      ),
      onPrimaryTap: allowStart ? onStart : onEdit,
      primaryLabel: allowStart ? 'Start' : 'Edit',
      primaryLeading:
          allowStart
              ? MynauiIcon(
                MynauiGlyphs.stopwatchPlay,
                size: 20,
                color: Colors.white.withValues(alpha: 0.96),
              )
              : MynauiIcon(
                MynauiGlyphs.editOne,
                size: 20,
                color: Colors.white.withValues(alpha: 0.96),
              ),
      primaryWidth: allowStart ? 168 : 148,
    );
  }
}

class _WorkoutTemplateSummary extends StatelessWidget {
  const _WorkoutTemplateSummary({
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
                child: _SummaryStatCell(
                  label: 'Exercises',
                  value: '$exerciseCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatCell(label: 'Sets', value: '$totalSetCount'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatCell(label: 'Rest', value: totalRestLabel),
              ),
            ],
          ),
          if (focusTags.isNotEmpty) ...[
            const SizedBox(height: 10),
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
                            color: kAccentColor.withValues(alpha: 0.10),
                            borderRadius: kIosChipBorderRadius,
                            border: Border.all(
                              color: kAccentColor.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            tag.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kAccentColor,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryStatCell extends StatelessWidget {
  const _SummaryStatCell({required this.label, required this.value});

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

class _HeroWorkoutCard extends StatelessWidget {
  const _HeroWorkoutCard({required this.template, required this.durationLabel});

  final WorkoutTemplate template;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
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
                      borderRadius: kIosChipBorderRadius,
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

class _ExercisePreviewCard extends StatelessWidget {
  const _ExercisePreviewCard({
    required this.exercise,
    required this.restFormatter,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenDetails,
    this.footer,
  });

  final WorkoutTemplateExercise exercise;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenDetails;
  final String Function(int seconds) restFormatter;
  final Widget? footer;

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

class _ExerciseThumbnail extends StatelessWidget {
  const _ExerciseThumbnail({required this.name});

  final String name;
  static const double _kSize = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSize,
      height: _kSize,
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
                      size: _kSize * 0.38,
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

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF151618).withValues(alpha: 0.92),
        borderRadius: kIosChipBorderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
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
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _WorkoutReviewScreen extends StatefulWidget {
  const _WorkoutReviewScreen({required this.template, required this.history});

  final WorkoutTemplate template;
  final List<WorkoutHistoryEntry> history;

  @override
  State<_WorkoutReviewScreen> createState() => _WorkoutReviewScreenState();
}

class _WorkoutReviewScreenState extends State<_WorkoutReviewScreen> {
  late List<WorkoutTemplateExercise> _exercises;
  final Set<String> _expandedExerciseIds = <String>{};
  late final Map<String, TextEditingController> _weightControllers;
  final ScrollController _reviewScrollController = ScrollController();

  static const List<String> _swapOptions = [
    'Leg Press',
    'Hamstring Curls',
    'Leg Extension',
    'Barbell Back Squat',
    'Romanian Deadlift',
    'Dumbbell Lunges',
    'Standing Calf Raise',
    'Lat Pulldown',
    'Seated Row',
    'Cable Face Pull',
    'Wrist Curl',
    'Push Up',
    'Chest Press',
    'Lateral Raise',
    'Tricep Pushdown',
    'Bench Press',
  ];

  @override
  void initState() {
    super.initState();

    final lastEntry = widget.history.isNotEmpty ? widget.history.first : null;
    final lastWeights = <String, double>{};

    if (lastEntry != null) {
      for (final summary in lastEntry.exerciseSummaries) {
        lastWeights[summary.exerciseName] = summary.maxWeightKg;
      }
    }

    _exercises = List<WorkoutTemplateExercise>.from(widget.template.exercises);

    _weightControllers = {
      for (final exercise in _exercises)
        exercise.id: TextEditingController(
          text: (lastWeights[exercise.name] ??
                  exercise.presetRows
                      .map((r) => r.weightKg)
                      .fold<double>(0, (a, b) => a > b ? a : b))
              .toStringAsFixed(1),
        ),
    };

    _expandedExerciseIds.addAll(_exercises.map((e) => e.id));
  }

  @override
  void dispose() {
    _reviewScrollController.dispose();
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _swapExercise(WorkoutTemplateExercise exercise) async {
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              12,
              kPagePadding,
              16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Swap exercise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose a new exercise for this slot.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ..._swapOptions.map(
                  (option) => ListTile(
                    title: Text(option),
                    trailing:
                        option == exercise.name
                            ? MynauiIcon(
                              MynauiGlyphs.checkUnread,
                              size: 22,
                              color: kAccentColor,
                            )
                            : null,
                    onTap: () => Navigator.pop(context, option),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == exercise.name) return;

    setState(() {
      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index < 0) return;
      _exercises[index] = _exercises[index].copyWith(name: selected);
      _expandedExerciseIds.add(exercise.id);
    });
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      if (oldIndex == newIndex) return;
      final item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);
    });
  }

  void _handleSave() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review saved (not persisted)')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            kPagePadding,
            10,
            kPagePadding,
            16,
          ),
          child: Column(
            children: [
              LiftIslandHeader(
                title: 'REVIEW WORKOUT',
                scrollController: _reviewScrollController,
                leading: LiftIslandHeaderAction(
                  onTap: () => Navigator.of(context).pop(),
                  child: _alignedWorkoutBackIcon(),
                ),
                trailing: LiftIslandHeaderAction(
                  onTap: _handleSave,
                  child: const Text(
                    'DONE',
                    style: TextStyle(
                      color: kAccentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: _reviewScrollController,
                  primary: false,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _exercises.length,
                  onReorder: _reorderExercises,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    final controller = _weightControllers[exercise.id]!;
                    final isExpanded = _expandedExerciseIds.contains(
                      exercise.id,
                    );

                    return Padding(
                      key: ValueKey(exercise.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ReorderableDelayedDragStartListener(
                        index: index,
                        child: _ExercisePreviewCard(
                          exercise: exercise,
                          isExpanded: isExpanded,
                          onOpenDetails:
                              () => _openExerciseDetail(context, exercise),
                          onToggle: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedExerciseIds.remove(exercise.id);
                              } else {
                                _expandedExerciseIds.add(exercise.id);
                              }
                            });
                          },
                          restFormatter: (seconds) {
                            final minutes = seconds ~/ 60;
                            final rem = (seconds % 60).toString().padLeft(
                              2,
                              '0',
                            );
                            return '$minutes:$rem';
                          },
                          footer: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: controller,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Last logged weight (kg)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _swapExercise(exercise),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kAccentColor,
                                        side: BorderSide(
                                          color: kAccentColor.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Swap'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _exercises.removeWhere(
                                            (e) => e.id == exercise.id,
                                          );
                                          _expandedExerciseIds.remove(
                                            exercise.id,
                                          );
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade600,
                                        side: BorderSide(
                                          color: Colors.red.shade200,
                                        ),
                                      ),
                                      child: const Text('Remove'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/workout/exercise_details/exercise_detail_page.dart';
import 'package:lift/shared/exercise_demo_images.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/scroll_linked_top_blur_scrim.dart';
import 'package:lift/shared/widgets/surfaces.dart';

Future<void> pushWorkoutHistoryDetailPage(
  BuildContext context, {
  required WorkoutHistoryEntry entry,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutHistoryDetailPage(entry: entry),
    ),
  );
}

class WorkoutHistoryDetailPage extends StatefulWidget {
  const WorkoutHistoryDetailPage({super.key, required this.entry});

  final WorkoutHistoryEntry entry;

  @override
  State<WorkoutHistoryDetailPage> createState() =>
      _WorkoutHistoryDetailPageState();
}

class _WorkoutHistoryDetailPageState extends State<WorkoutHistoryDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _expandedIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.entry.exerciseSummaries.isNotEmpty) {
      _expandedIndexes.add(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (minutes == 0) return '${hours}HR';
      return '${hours}HR ${minutes}MIN';
    }
    return '${totalMinutes}MIN';
  }

  String _formatRest(int seconds) {
    final minutes = seconds ~/ 60;
    final rem = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rem';
  }

  String _formatCompletedAt(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(widget.entry.completedAt);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(widget.entry.completedAt),
    );
    return '$date • $time';
  }

  String get _heroImageName {
    if (widget.entry.exerciseSummaries.isNotEmpty) {
      return widget.entry.exerciseSummaries.first.exerciseName;
    }
    return widget.entry.workoutName;
  }

  int get _totalSetCount => widget.entry.exerciseSummaries.fold<int>(
    0,
    (sum, summary) => sum + summary.setCount,
  );

  bool get _hasRecordedSetRows => widget.entry.exerciseSummaries.any(
    (summary) => summary.setRows.isNotEmpty,
  );

  int get _totalRecordedRestSeconds => widget.entry.exerciseSummaries.fold<int>(
    0,
    (sum, summary) =>
        sum +
        summary.setRows.fold<int>(0, (inner, row) => inner + row.restSeconds),
  );

  List<String> get _focusTags {
    final rankedMuscles = widget.entry.muscleGroupVolumeKg.entries.toList(
      growable: false,
    )..sort((a, b) => b.value.compareTo(a.value));
    final ordered = <String>[
      ...rankedMuscles.map((entry) => entry.key),
      ...widget.entry.exerciseSummaries.expand(
        (summary) => summary.muscleGroups,
      ),
    ];
    final seen = <String>{};
    final tags = <String>[];
    for (final raw in ordered) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      if (!seen.add(key)) continue;
      tags.add(tag);
      if (tags.length == 5) break;
    }
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    const islandTop = 16.0;
    const sectionGap = 12.0;
    final headerBottom = islandTop + kLiftIslandHeaderHeight;
    final listTopPadding = headerBottom + sectionGap;
    final listBottomPadding = MediaQuery.paddingOf(context).bottom + 24;

    return Scaffold(
      backgroundColor: liftCanvasColor(context),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: listTopPadding,
              child: const ColoredBox(color: Color(0xFFF7F7F8)),
            ),
            ListView(
              controller: _scrollController,
              primary: false,
              padding: EdgeInsets.fromLTRB(
                kPagePadding,
                listTopPadding,
                kPagePadding,
                listBottomPadding,
              ),
              children: [
                _HistoryHeroCard(
                  imageUrl: exerciseDemoImageUrl(_heroImageName),
                  workoutName: widget.entry.workoutName,
                  durationLabel: _formatDuration(widget.entry.duration),
                ),
                const SizedBox(height: sectionGap),
                _WorkoutHistorySummaryCard(
                  completedLabel: _formatCompletedAt(context),
                  exercisesLabel:
                      '${widget.entry.exercisesCompleted}/${widget.entry.totalExercises}',
                  totalSets: _totalSetCount,
                  totalRestLabel:
                      _hasRecordedSetRows
                          ? _formatRest(_totalRecordedRestSeconds)
                          : '--',
                  focusTags: _focusTags,
                ),
                const SizedBox(height: sectionGap),
                if (widget.entry.exerciseSummaries.isEmpty)
                  const SectionBoundary(child: _EmptyHistoryExercisesState())
                else
                  ...widget.entry.exerciseSummaries.asMap().entries.map((
                    entry,
                  ) {
                    final index = entry.key;
                    final summary = entry.value;
                    final isExpanded = _expandedIndexes.contains(index);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: sectionGap),
                      child: _HistoryExerciseCard(
                        summary: summary,
                        isExpanded: isExpanded,
                        restFormatter: _formatRest,
                        onOpenDetails:
                            () => pushExerciseDetailPage(
                              context,
                              exerciseName: summary.exerciseName,
                            ),
                        onToggle: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedIndexes.remove(index);
                            } else {
                              _expandedIndexes.add(index);
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
              height: listTopPadding + 36,
              child: IgnorePointer(
                child: ScrollLinkedTopBlurScrim(
                  scrollController: _scrollController,
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
                scrollController: _scrollController,
                leading: LiftIslandHeaderAction(
                  onTap: () => Navigator.of(context).pop(),
                  child: Transform.translate(
                    offset: const Offset(1, 0),
                    child: const MynauiIcon(
                      MynauiGlyphs.altArrowLeft,
                      size: 22,
                      color: kLiftIslandOnFrosted,
                    ),
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

class _HistoryHeroCard extends StatelessWidget {
  const _HistoryHeroCard({
    required this.imageUrl,
    required this.workoutName,
    required this.durationLabel,
  });

  final String imageUrl;
  final String workoutName;
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
              child: Image.network(
                imageUrl,
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
                      Colors.black.withValues(alpha: 0.46),
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
                      workoutName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HeroChip(label: durationLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: kIosChipBorderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WorkoutHistorySummaryCard extends StatelessWidget {
  const _WorkoutHistorySummaryCard({
    required this.completedLabel,
    required this.exercisesLabel,
    required this.totalSets,
    required this.totalRestLabel,
    required this.focusTags,
  });

  final String completedLabel;
  final String exercisesLabel;
  final int totalSets;
  final String totalRestLabel;
  final List<String> focusTags;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPLETED WORKOUT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.45,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            completedLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryStatCell(
                  label: 'Exercises',
                  value: exercisesLabel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatCell(label: 'Sets', value: '$totalSets'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryStatCell(label: 'Rest', value: totalRestLabel),
              ),
            ],
          ),
          if (focusTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'MUSCLES WORKED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.45,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: focusTags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kAccentColor.withValues(alpha: 0.08),
                        borderRadius: kIosChipBorderRadius,
                        border: Border.all(
                          color: kAccentColor.withValues(alpha: 0.12),
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
                  .toList(growable: false),
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

class _HistoryExerciseCard extends StatelessWidget {
  const _HistoryExerciseCard({
    required this.summary,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenDetails,
    required this.restFormatter,
  });

  final WorkoutHistoryExerciseSummary summary;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenDetails;
  final String Function(int seconds) restFormatter;

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
                        _ExerciseThumbnail(name: summary.exerciseName),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                summary.exerciseName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _ExerciseMetaChip(
                                    label: '${summary.setCount} SETS',
                                  ),
                                  if (summary.maxWeightKg > 0)
                                    _ExerciseMetaChip(
                                      label:
                                          '${summary.maxWeightKg.toStringAsFixed(0)}KG TOP SET',
                                    ),
                                ],
                              ),
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
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 28,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 8),
            if (summary.setRows.isNotEmpty)
              _SetHistoryTable(
                rows: summary.setRows,
                restFormatter: restFormatter,
              )
            else
              _LegacyExerciseBreakdown(summary: summary),
          ],
        ],
      ),
    );
  }
}

class _ExerciseThumbnail extends StatelessWidget {
  const _ExerciseThumbnail({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: kExerciseImageBorderRadius,
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(
          Radius.circular(kExerciseImageRadius - 1),
        ),
        child: Image.network(
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
                  size: 22,
                ),
              ),
        ),
      ),
    );
  }
}

class _ExerciseMetaChip extends StatelessWidget {
  const _ExerciseMetaChip({required this.label});

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
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SetHistoryTable extends StatelessWidget {
  const _SetHistoryTable({required this.rows, required this.restFormatter});

  final List<WorkoutHistorySetRow> rows;
  final String Function(int seconds) restFormatter;

  @override
  Widget build(BuildContext context) {
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

class _LegacyExerciseBreakdown extends StatelessWidget {
  const _LegacyExerciseBreakdown({required this.summary});

  final WorkoutHistoryExerciseSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: kIosControlBorderRadius,
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detailed set history is unavailable for this saved workout.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegacyBreakdownChip(label: 'SETS', value: '${summary.setCount}'),
              _LegacyBreakdownChip(
                label: 'REPS',
                value: '${summary.totalReps}',
              ),
              _LegacyBreakdownChip(
                label: 'VOLUME',
                value: '${summary.totalVolumeKg.toStringAsFixed(0)}KG',
              ),
              _LegacyBreakdownChip(
                label: 'TOP SET',
                value: '${summary.maxWeightKg.toStringAsFixed(0)}KG',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegacyBreakdownChip extends StatelessWidget {
  const _LegacyBreakdownChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: kIosChipBorderRadius,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(text: value, style: const TextStyle(color: kAccentColor)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistoryExercisesState extends StatelessWidget {
  const _EmptyHistoryExercisesState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'No recorded exercises',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'This workout ended before any completed sets were logged.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey.shade700,
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/workout/widgets/log_set_sheet.dart';
import 'package:lift/shared/exercise_demo_images.dart';
import 'package:lift/shared/models/machine.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/models/workout_set_entry.dart';
import 'package:lift/shared/workout_history_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:lift/shared/widgets/workout_detail_action_island.dart';

class _PastSetLine {
  const _PastSetLine({
    required this.workoutCompletedAt,
    required this.workoutName,
    required this.exerciseName,
    required this.row,
    required this.setIndexInExercise,
  });

  final DateTime workoutCompletedAt;
  final String workoutName;
  final String exerciseName;
  final WorkoutHistorySetRow row;
  final int setIndexInExercise;
}

List<_PastSetLine> _pastSetsForMachine(
  Machine machine,
  List<WorkoutHistoryEntry> history,
) {
  final supported = <String>{
    for (final e in machine.supportedExercises) e.trim().toLowerCase(),
  };
  if (supported.isEmpty) return const [];

  bool matches(String name) => supported.contains(name.trim().toLowerCase());

  final sorted = List<WorkoutHistoryEntry>.from(history)
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

  final out = <_PastSetLine>[];
  for (final entry in sorted) {
    for (final summary in entry.exerciseSummaries) {
      if (!matches(summary.exerciseName)) continue;
      if (summary.setRows.isEmpty) continue;
      var i = 0;
      for (final row in summary.setRows) {
        i++;
        out.add(
          _PastSetLine(
            workoutCompletedAt: entry.completedAt,
            workoutName: entry.workoutName,
            exerciseName: summary.exerciseName,
            row: row,
            setIndexInExercise: i,
          ),
        );
      }
    }
  }
  return out;
}

String _formatPastWorkoutDate(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

class MachineScreen extends StatefulWidget {
  const MachineScreen({
    super.key,
    required this.machine,
    this.returnExerciseOnTap = false,
  });

  final Machine machine;

  /// When true (e.g. opened from add/swap exercise), tapping a tile under
  /// "Exercises on this machine" pops this route with that exercise name.
  final bool returnExerciseOnTap;

  @override
  State<MachineScreen> createState() => _MachineScreenState();
}

class _MachineScreenState extends State<MachineScreen> {
  final List<WorkoutSetEntry> _sets = [];
  final ScrollController _scrollController = ScrollController();
  Timer? _restTimer;
  int _restRemaining = 0;
  late String _activeExerciseName;
  List<WorkoutHistoryEntry> _workoutHistory = const [];

  @override
  void initState() {
    super.initState();
    _activeExerciseName = _initialActiveExercise(widget.machine);
    _loadMachineScreenData();
  }

  Future<void> _loadMachineScreenData() async {
    await _loadPersistedSessionSets();
    await _loadWorkoutHistoryList();
  }

  String _sessionSetsStorageKey() {
    final d = DateTime.now();
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return 'lift_machine_session_sets_v1_${widget.machine.id}_$day';
  }

  Future<void> _loadPersistedSessionSets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionSetsStorageKey());
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = <WorkoutSetEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final e = WorkoutSetEntry.fromJsonMap(map);
        if (e != null) list.add(e);
      }
      if (!mounted || list.isEmpty) return;
      setState(() {
        if (_sets.isEmpty) {
          _sets.addAll(list);
        } else {
          for (final p in list) {
            if (!_sets.any((s) => _isSameLoggedSet(s, p))) {
              _sets.add(p);
            }
          }
          _sets.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      });
    } catch (_) {
      // Keep screen usable if session restore fails.
    }
  }

  bool _isSameLoggedSet(WorkoutSetEntry a, WorkoutSetEntry b) {
    return a.exerciseName == b.exerciseName &&
        a.weightKg == b.weightKg &&
        a.reps == b.reps &&
        a.createdAt.millisecondsSinceEpoch ==
            b.createdAt.millisecondsSinceEpoch;
  }

  void _persistSessionSets() {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _sessionSetsStorageKey();
        if (_sets.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setString(
            key,
            jsonEncode(_sets.map((e) => e.toJson()).toList(growable: false)),
          );
        }
      } catch (_) {}
    });
  }

  bool _isSameLocalCalendarDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  List<({DateTime at, String exerciseName, Widget row})> _todayDisplayRows(
    List<_PastSetLine> pastLines,
  ) {
    final now = DateTime.now();
    final out = <({DateTime at, String exerciseName, Widget row})>[];

    for (final line in pastLines) {
      if (!_isSameLocalCalendarDay(line.workoutCompletedAt, now)) continue;
      out.add((
        at: line.workoutCompletedAt,
        exerciseName: line.exerciseName,
        row: _PastLoggedSetRow(line: line),
      ));
    }
    for (final s in _sets) {
      out.add((
        at: s.createdAt,
        exerciseName: s.exerciseName,
        row: _MachineLoggedSetRow(set: s),
      ));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> _loadWorkoutHistoryList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kWorkoutHistoryStorageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <WorkoutHistoryEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final parsed = workoutHistoryEntryFromMap(map);
        if (parsed != null) restored.add(parsed);
      }
      if (!mounted) return;
      setState(() => _workoutHistory = restored);
    } catch (_) {
      // Keep screen usable if history cannot be read.
    }
  }

  String _initialActiveExercise(Machine m) {
    final list = m.supportedExercises;
    if (list.isEmpty) return '';
    final last = m.lastExerciseName?.trim();
    if (last != null && last.isNotEmpty && list.contains(last)) {
      return last;
    }
    return list.first;
  }

  WorkoutSetEntry? _lastSetForExercise(String exercise) {
    for (var i = _sets.length - 1; i >= 0; i--) {
      if (_sets[i].exerciseName == exercise) return _sets[i];
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _openLogSetSheet() async {
    final exercise =
        _activeExerciseName.trim().isNotEmpty
            ? _activeExerciseName.trim()
            : (widget.machine.supportedExercises.isNotEmpty
                ? widget.machine.supportedExercises.first
                : 'Set');
    final lastSame = _lastSetForExercise(exercise);
    final lastAny = _sets.isNotEmpty ? _sets.last : null;
    final last = lastSame ?? lastAny;
    final draft = await showLogSetSheet(
      context,
      initialWeightKg: last?.weightKg ?? widget.machine.lastWeightKg,
      initialReps: last?.reps ?? widget.machine.lastReps,
      initialRestSeconds:
          last?.restSecondsPlanned ?? widget.machine.defaultRestSeconds,
      exerciseTitle: exercise,
    );

    if (draft == null) return;

    setState(() {
      _sets.add(
        WorkoutSetEntry(
          setNumber: _sets.length + 1,
          exerciseName: exercise,
          weightKg: draft.weightKg,
          reps: draft.reps,
          createdAt: DateTime.now(),
          restSecondsPlanned: draft.restSeconds,
        ),
      );
    });
    _persistSessionSets();
    _startRestTimer(draft.restSeconds);
  }

  void _startRestTimer(int seconds) {
    _restTimer?.cancel();
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_restRemaining <= 1) {
        timer.cancel();
        setState(() => _restRemaining = 0);
        return;
      }
      setState(() => _restRemaining -= 1);
    });
  }

  void _adjustRest(int delta) {
    if (_restRemaining <= 0) return;
    setState(() => _restRemaining = (_restRemaining + delta).clamp(0, 3600));
  }

  void _repeatLastSet() {
    if (_sets.isEmpty) return;
    final last = _sets.last;
    setState(() {
      _sets.add(
        WorkoutSetEntry(
          setNumber: _sets.length + 1,
          exerciseName: last.exerciseName,
          weightKg: last.weightKg,
          reps: last.reps,
          createdAt: DateTime.now(),
          restSecondsPlanned: last.restSecondsPlanned,
        ),
      );
    });
    _persistSessionSets();
    _startRestTimer(last.restSecondsPlanned);
  }

  Future<void> _showMachineInfo(BuildContext buttonContext) async {
    final machine = widget.machine;

    final buttonBox = buttonContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) return;

    final buttonRect = Rect.fromPoints(
      buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      buttonBox.localToGlobal(
        buttonBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    final selection = await showMenu<_MachineInfoField>(
      context: context,
      position: RelativeRect.fromRect(
        buttonRect,
        Offset.zero & overlayBox.size,
      ),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      items: [
        PopupMenuItem<_MachineInfoField>(
          value: _MachineInfoField.brand,
          padding: EdgeInsets.zero,
          child: _MachineInfoMenuItem(
            iconAsset: MynauiGlyphs.tagHorizontal,
            label: 'Brand',
            value: machine.brand,
          ),
        ),
        PopupMenuItem<_MachineInfoField>(
          value: _MachineInfoField.machine,
          padding: EdgeInsets.zero,
          child: _MachineInfoMenuItem(
            iconAsset: MynauiGlyphs.machine,
            label: 'Machine',
            value: machine.fullName,
          ),
        ),
        PopupMenuItem<_MachineInfoField>(
          value: _MachineInfoField.id,
          padding: EdgeInsets.zero,
          child: _MachineInfoMenuItem(
            iconAsset: MynauiGlyphs.hashtagSquare,
            label: 'ID',
            value: machine.machineCode,
          ),
        ),
      ],
    );

    switch (selection) {
      case _MachineInfoField.brand:
        _copyMachineInfoField(label: 'Brand', value: machine.brand);
      case _MachineInfoField.machine:
        _copyMachineInfoField(label: 'Machine', value: machine.fullName);
      case _MachineInfoField.id:
        _copyMachineInfoField(label: 'ID', value: machine.machineCode);
      case null:
        break;
    }
  }

  Future<void> _copyMachineInfoField({
    required String label,
    required String value,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final machine = widget.machine;
    final pastLines = _pastSetsForMachine(machine, _workoutHistory);
    final todayRows = _todayDisplayRows(pastLines);
    const gapAboveBottomIsland = 10.0;

    /// Same idea as [TodayWorkoutDetailScreen]: island floats above home indicator
    /// with a margin; scroll padding clears the frosted bar + gap.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    const islandBottomMargin = 12.0;
    final islandBottomOffset = safeBottom + islandBottomMargin;
    final listBottomPadding =
        islandBottomOffset + kLiftIslandHeaderHeight + gapAboveBottomIsland;
    const islandTop = 16.0;
    const heroBelowHeaderGap = 12.0;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerTop = topInset + islandTop;
    final listTopPadding =
        headerTop + kLiftIslandHeaderHeight + heroBelowHeaderGap;
    return Scaffold(
      backgroundColor: liftCanvasColor(context, light: const Color(0xFFF8F8F8)),
      body: SafeArea(
        bottom: false,
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                clipBehavior: Clip.none,
                padding: EdgeInsets.only(
                  top: listTopPadding,
                  bottom: listBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPagePadding,
                      ),
                      child: _MachineHero(machine: machine),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPagePadding,
                      ),
                      child: Column(
                        children: [
                          _MachineSupportedExercisesSection(
                            exerciseNames: machine.supportedExercises,
                            selectedExerciseName: _activeExerciseName,
                            onPickExerciseForLogging:
                                widget.returnExerciseOnTap
                                    ? null
                                    : (name) => setState(
                                      () => _activeExerciseName = name,
                                    ),
                            onSelectExercise:
                                widget.returnExerciseOnTap
                                    ? (name) {
                                      Navigator.of(context).pop<String>(name);
                                    }
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          SectionBoundary(
                            borderRadius: kIosCornerRadius,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Last time',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      machine.lastUsedLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (machine.lastExerciseName != null &&
                                    machine.lastExerciseName!
                                        .trim()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    machine.lastExerciseName!.trim(),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _StatPill(
                                      label: 'Top set',
                                      value:
                                          '${machine.lastWeightKg.toStringAsFixed(0)} kg x ${machine.lastReps}',
                                    ),
                                    const SizedBox(width: 8),
                                    _StatPill(
                                      label: 'Zone',
                                      value: machine.zone,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SectionBoundary(
                            borderRadius: kIosCornerRadius,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Past sets',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      pastLines.isEmpty
                                          ? '—'
                                          : '${pastLines.length} logged',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (pastLines.isEmpty)
                                  Text(
                                    'When you finish workouts that use these movements, each set appears here.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: Colors.grey.shade600,
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < pastLines.length;
                                        i++
                                      ) ...[
                                        if (i == 0 ||
                                            pastLines[i].exerciseName !=
                                                pastLines[i - 1].exerciseName)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              bottom: 6,
                                              top: i == 0 ? 0 : 12,
                                            ),
                                            child: Text(
                                              pastLines[i].exerciseName,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.grey.shade700,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ),
                                        _PastLoggedSetRow(line: pastLines[i]),
                                        if (i != pastLines.length - 1)
                                          const SizedBox(height: 8),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_restRemaining > 0) ...[
                            _RestTimerStrip(
                              remaining: _formatSeconds(_restRemaining),
                              onAddThirty: () => _adjustRest(30),
                              onSkip: () => setState(() => _restRemaining = 0),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SectionBoundary(
                            borderRadius: kIosCornerRadius,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Today',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${todayRows.length} set${todayRows.length == 1 ? '' : 's'} logged',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (todayRows.isEmpty)
                                  SizedBox(
                                    height: 180,
                                    child: Center(
                                      child: Text(
                                        machine.supportedExercises.isEmpty
                                            ? 'No sets yet.\nTap Log Set to start.'
                                            : 'No sets yet.\nPick a movement above, then tap Log Set.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < todayRows.length;
                                        i++
                                      ) ...[
                                        if (i == 0 ||
                                            todayRows[i].exerciseName !=
                                                todayRows[i - 1].exerciseName)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              bottom: 6,
                                              top: i == 0 ? 0 : 12,
                                            ),
                                            child: Text(
                                              todayRows[i].exerciseName,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.grey.shade700,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ),
                                        todayRows[i].row,
                                        if (i != todayRows.length - 1)
                                          const SizedBox(height: 8),
                                      ],
                                    ],
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
            ),
            Positioned(
              top: headerTop,
              left: kPagePadding,
              right: kPagePadding,
              child: LiftIslandHeader(
                scrollController: _scrollController,
                title: machine.displayName,
                subtitle: machine.machineCode,
                leading: LiftIslandHeaderAction(
                  onTap: () => Navigator.pop(context),
                  child: const MynauiIcon(
                    MynauiGlyphs.altArrowLeft,
                    size: 24,
                    color: kLiftIslandOnFrosted,
                  ),
                ),
                trailing: LiftIslandHeaderIconAction(
                  onTapWithContext: _showMachineInfo,
                  iconWidget: const MynauiIcon(
                    MynauiGlyphs.infoCircle,
                    size: 26,
                    color: kLiftIslandOnFrosted,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              right: 4,
              bottom: islandBottomOffset,
              child: _MachineActionIsland(
                canRepeatLast: _sets.isNotEmpty,
                onRepeatLast: _repeatLastSet,
                onLogSet: _openLogSetSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineHero extends StatelessWidget {
  const _MachineHero({required this.machine});

  final Machine machine;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kIosCornerRadius),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: Image.network(
              machine.heroImageUrl,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    alignment: Alignment.center,
                    child: const MynauiIcon(
                      MynauiGlyphs.galleryMinimalistic,
                      size: 40,
                      color: Color(0xFF9CA3AF),
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
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machine.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      machine.muscleGroups
                          .map((group) => _DarkChip(label: group))
                          .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MachineSupportedExercisesSection extends StatelessWidget {
  const _MachineSupportedExercisesSection({
    required this.exerciseNames,
    this.selectedExerciseName,
    this.onPickExerciseForLogging,
    this.onSelectExercise,
  });

  final List<String> exerciseNames;
  final String? selectedExerciseName;
  final ValueChanged<String>? onPickExerciseForLogging;
  final ValueChanged<String>? onSelectExercise;

  @override
  Widget build(BuildContext context) {
    final selectionMode = onSelectExercise != null;
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Exercises on this machine',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${exerciseNames.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            selectionMode
                ? 'Tap a movement to add it to your workout.'
                : 'Tap a card to choose what you’re logging, then use Log Set.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: exerciseNames.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final name = exerciseNames[index];
                final selected =
                    !selectionMode &&
                    onPickExerciseForLogging != null &&
                    selectedExerciseName == name;
                return _MachineExerciseTile(
                  name: name,
                  selected: selected,
                  onSelect:
                      onSelectExercise != null
                          ? () => onSelectExercise!(name)
                          : onPickExerciseForLogging != null
                          ? () => onPickExerciseForLogging!(name)
                          : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MachineExerciseTile extends StatelessWidget {
  const _MachineExerciseTile({
    required this.name,
    this.selected = false,
    this.onSelect,
  });

  final String name;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: 164,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(kIosCornerRadius),
          border: Border.all(
            color: selected ? kAccentColor : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: double.infinity,
                  child: Image.network(
                    exerciseDemoImageUrl(name),
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: MynauiIcon(
                            MynauiGlyphs.galleryMinimalistic,
                            color: Colors.grey.shade500,
                            size: 28,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Machine movement',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );

    if (onSelect == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        child: card,
      ),
    );
  }
}

class _MachineLoggedSetRow extends StatelessWidget {
  const _MachineLoggedSetRow({required this.set});

  final WorkoutSetEntry set;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAccentColor.withValues(alpha: 0.10),
            ),
            alignment: Alignment.center,
            child: Text(
              '${set.setNumber}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${set.weightKg.toStringAsFixed(1)} kg x ${set.reps}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${set.restSecondsPlanned}s rest',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _PastLoggedSetRow extends StatelessWidget {
  const _PastLoggedSetRow({required this.line});

  final _PastSetLine line;

  @override
  Widget build(BuildContext context) {
    final row = line.row;
    final label =
        row.label.trim().isNotEmpty ? row.label : '${line.setIndexInExercise}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade600.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: label.length > 3 ? 9 : 12,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${row.weightKg.toStringAsFixed(1)} kg x ${row.reps}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${row.restSeconds}s rest',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${line.workoutName} · ${_formatPastWorkoutDate(line.workoutCompletedAt)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _MachineActionIsland extends StatelessWidget {
  const _MachineActionIsland({
    required this.canRepeatLast,
    required this.onRepeatLast,
    required this.onLogSet,
  });

  final bool canRepeatLast;
  final VoidCallback onRepeatLast;
  final VoidCallback onLogSet;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white.withValues(alpha: 0.96);
    return WorkoutDetailActionIsland(
      onSecondaryTap: canRepeatLast ? onRepeatLast : null,
      secondaryChild: MynauiIcon(
        MynauiGlyphs.restartCircle,
        size: 24,
        color:
            canRepeatLast
                ? Colors.black.withValues(alpha: 0.74)
                : Colors.black.withValues(alpha: 0.22),
      ),
      onPrimaryTap: onLogSet,
      primaryLabel: 'Log Set',
      primaryLeading: MynauiIcon(
        MynauiGlyphs.checkCircle,
        size: 20,
        color: white,
      ),
      primaryWidth: 172,
    );
  }
}

class _RestTimerStrip extends StatelessWidget {
  const _RestTimerStrip({
    required this.remaining,
    required this.onAddThirty,
    required this.onSkip,
  });

  final String remaining;
  final VoidCallback onAddThirty;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SectionBoundary(
      borderRadius: kIosCornerRadius,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kAccentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_outlined, color: kAccentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rest Timer',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  remaining,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onAddThirty, child: const Text('+30s')),
          TextButton(onPressed: onSkip, child: const Text('Skip')),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(kIosCornerRadius),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 3),
            Text(
              value.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MachineInfoField { brand, machine, id }

class _MachineInfoMenuItem extends StatelessWidget {
  const _MachineInfoMenuItem({
    required this.iconAsset,
    required this.label,
    required this.value,
  });

  final String iconAsset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 304,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: MynauiIcon(
                iconAsset,
                size: 22,
                color: const Color(0xFF161616),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF161616),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      height: 1.3,
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

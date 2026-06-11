import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lift/features/articles/articles_repository.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/articles/article_editor_screen.dart';
import 'package:lift/features/articles/articles_screen.dart';
import 'package:lift/features/machines/machine_scan_flow_screen.dart';
import 'package:lift/features/machines/mock_machines.dart';
import 'package:lift/features/pass/gym_pass_dialog.dart';
import 'package:lift/features/progress/progress_screen.dart';
import 'package:lift/features/calendar/training_calendar_screen.dart';
import 'package:lift/features/home/today_workout_detail_screen.dart';
import 'package:lift/features/settings/settings_screen.dart';
import 'package:lift/features/workout/mock_workout_templates.dart';
import 'package:lift/features/workout/workout_templates_flow.dart';
import 'package:lift/shared/models/article.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:lift/shared/models/workout_template.dart';
import 'package:lift/shared/widgets/stacked_workout_hero.dart';
import 'package:lift/shared/widgets/lift_floating_island.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';
import 'package:lift/shared/widgets/recovery_dial_card.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/stored_weekly_template_schedule.dart';
import 'package:lift/shared/widgets/workout_template_hero_image.dart';
import 'package:lift/shared/workout_history_codec.dart';
import 'package:lift/shared/weekly_default_template_schedule.dart';
import 'package:lift/shared/widgets/surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _TodayWorkoutExitAction { none, startLive, openEditor }

enum _LiveDockSnapSide { left, right }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.signedInUserGender,
    this.initialWorkoutHistory = const <WorkoutHistoryEntry>[],
    this.preloadedFromBootstrap = false,
  });

  final String? signedInUserGender;
  final List<WorkoutHistoryEntry> initialWorkoutHistory;
  final bool preloadedFromBootstrap;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _userGenderStorageKey = 'lift_user_gender';
  static const Duration _fullRecoveryWindow = Duration(hours: 72);
  static const Duration _kShellTabTransitionDuration = LiftMotion.emphasized;
  int _selectedIndex = 0;
  late int _selectedDay;

  /// Which workout in [_heroDayTemplates] is visible in the hero carousel.
  int _todayWorkoutCarouselIndex = 0;

  static const int _kWeekdaySlots = 7;
  static const List<String> _kScheduleWeekdayLabels = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  final List<WorkoutTemplate> _templateLibrary = MockWorkoutTemplates.seed();

  /// When null, [kWeeklyDefaultTemplateIds] is used until [loadWeeklyTemplateSchedule] runs.
  List<List<String>>? _weeklyTemplateIds;
  final List<WorkoutHistoryEntry> _workoutHistory = <WorkoutHistoryEntry>[];
  bool _hideWorkoutShellNav = false;
  bool _isProgressArrangeMode = false;
  WorkoutLiveDockHandle? _liveDockHandle;
  WorkoutLiveFullscreenHandle? _liveFullscreenHandle;
  _LiveDockSnapSide? _liveDockSnapSide;
  WorkoutFlowCommand? _pendingWorkoutCommand;
  bool _suppressLiveDockUnderRoute = false;
  int? _transitionFromIndex;
  _RecoveryUserGender _userGender = _RecoveryUserGender.male;
  late final AnimationController _shellTabTransitionController;
  final ProgressArrangeController _progressArrangeController =
      ProgressArrangeController();
  bool _shellWarmupStarted = false;
  final GlobalKey _workoutTemplatesFlowKey = GlobalKey();

  void _setStateSafely(VoidCallback update) {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(update);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(update);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDay = _weekdayIndexFor(DateTime.now());
    _shellTabTransitionController = AnimationController(
      vsync: this,
      duration: _kShellTabTransitionDuration,
    )..addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _transitionFromIndex = null);
    });
    if (widget.signedInUserGender != null) {
      _userGender = _RecoveryUserGenderX.fromRaw(widget.signedInUserGender!);
    }
    _workoutHistory.addAll(widget.initialWorkoutHistory);
    if (!widget.preloadedFromBootstrap) {
      _loadWorkoutHistory();
      _loadUserGender();
    }
    unawaited(_loadWeeklyTemplateSchedule());
    _warmShellContent();
  }

  void _onNavItemTapped(int index) {
    _switchToTab(index);
  }

  void _onDaySelected(int day) => setState(() {
    _selectedDay = day;
    _todayWorkoutCarouselIndex = 0;
  });
  bool get _showShellNav => !(_selectedIndex == 2 && _hideWorkoutShellNav);
  bool get _showProgressArrangeNav =>
      _showShellNav && _selectedIndex == 3 && _isProgressArrangeMode;
  bool get _showShellBottomNav => _showShellNav && !_showProgressArrangeNav;
  List<WorkoutTemplate> get _selectedDayTemplates {
    final weekly = _weeklyTemplateIds ?? kWeeklyDefaultTemplateIds;
    final ids = weekly[_selectedDay % weekly.length];
    return ids
        .map(
          (id) => _templateLibrary.firstWhere(
            (template) => template.id == id,
            orElse:
                () => _templateLibrary[_selectedDay % _templateLibrary.length],
          ),
        )
        .toList();
  }

  /// Templates for the stacked hero; if the weekly row has no IDs for this day,
  /// uses one library template so [StackedWorkoutHero] and [_activeDayTemplate] stay valid.
  List<WorkoutTemplate> get _heroDayTemplates {
    final list = _selectedDayTemplates;
    if (list.isNotEmpty) return list;
    if (_templateLibrary.isEmpty) return list;
    return [_templateLibrary.first];
  }

  WorkoutTemplate get _activeDayTemplate {
    final list = _heroDayTemplates;
    final i = _todayWorkoutCarouselIndex.clamp(0, list.length - 1);
    return list[i];
  }

  int _weekdayIndexFor(DateTime date) => (date.weekday - 1) % _kWeekdaySlots;

  /// Monday 00:00 of the week that contains [date] (weekday Mon–Sun).
  DateTime _mondayOfWeekContaining(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  void _syncSelectedDayToToday() {
    final todayIndex = _weekdayIndexFor(DateTime.now());
    if (_selectedDay == todayIndex) return;
    setState(() {
      _selectedDay = todayIndex;
      _todayWorkoutCarouselIndex = 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _selectedIndex == 0) {
      _syncSelectedDayToToday();
    }
  }

  List<_RecoveryMuscleStat> _recoveryStatsFor(WorkoutTemplate template) {
    final latestByMuscle = <String, DateTime>{};
    for (final entry in _workoutHistory) {
      final trainedMuscles = <String>{
        ...entry.muscleGroupVolumeKg.keys.map((group) => group.trim()),
        ...entry.exerciseSummaries.expand(
          (summary) => summary.muscleGroups.map((group) => group.trim()),
        ),
      }.where((group) => group.isNotEmpty);

      for (final group in trainedMuscles) {
        final current = latestByMuscle[group];
        if (current == null || entry.completedAt.isAfter(current)) {
          latestByMuscle[group] = entry.completedAt;
        }
      }
    }

    final targetOrder = <String>{
      ...template.focusTags
          .map((group) => group.trim())
          .where((group) => group.isNotEmpty),
    }.toList(growable: false);

    final knownMuscles = <String>{
      ...latestByMuscle.keys,
      ..._templateLibrary.expand(
        (item) => item.focusTags.map((group) => group.trim()),
      ),
      ...targetOrder,
    }.where((group) => group.isNotEmpty).toList(growable: false);

    final otherMuscles =
        knownMuscles.where((group) => !targetOrder.contains(group)).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final ordered = <String>[...targetOrder, ...otherMuscles];
    final now = DateTime.now();

    return ordered
        .map((muscle) {
          final lastTrainedAt = latestByMuscle[muscle];
          final recoveryPercent =
              lastTrainedAt == null
                  ? 100
                  : ((now.difference(lastTrainedAt).inSeconds /
                              _fullRecoveryWindow.inSeconds) *
                          100)
                      .clamp(0, 100)
                      .round();

          return _RecoveryMuscleStat(
            muscleGroup: muscle,
            recoveryPercent: recoveryPercent,
            lastTrainedAt: lastTrainedAt,
          );
        })
        .toList(growable: false);
  }

  Color _recoveryColor(int percent) {
    if (percent >= 80) return Colors.green.shade700;
    if (percent >= 50) return kRecoveryMidColor;
    return Colors.red.shade700;
  }

  Future<void> _openRecoveryHeatMap(
    _RecoveryMuscleStat stat,
    List<_RecoveryMuscleStat> allStats,
  ) async {
    final heatColor = _recoveryColor(stat.recoveryPercent);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      isScrollControlled: true,
      builder: (context) {
        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
        return FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          heightFactor: 0.72,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(kIosCornerRadius),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + bottomInset),
              child: _RecoveryHeatMapSheet(
                stat: stat,
                allStats: allStats,
                heatColor: heatColor,
                regions: _regionsForMuscle(stat.muscleGroup),
                userGender: _userGender,
              ),
            ),
          ),
        );
      },
    );
  }

  void _onWorkoutShellNavVisibilityChanged(bool shouldHide) {
    if (_hideWorkoutShellNav == shouldHide) return;
    _setStateSafely(() => _hideWorkoutShellNav = shouldHide);
  }

  void _onLiveDockChanged(WorkoutLiveDockHandle? handle) {
    if (_liveDockHandle == handle &&
        (handle != null || _liveDockSnapSide == null)) {
      return;
    }
    _setStateSafely(() {
      _liveDockHandle = handle;
      if (handle == null) {
        _liveDockSnapSide = null;
      }
    });
  }

  void _onLiveFullscreenChanged(WorkoutLiveFullscreenHandle? handle) {
    if (_liveFullscreenHandle == handle) return;
    _setStateSafely(() => _liveFullscreenHandle = handle);
  }

  void _setLiveDockSnapSide(_LiveDockSnapSide? side) {
    if (_liveDockHandle == null || _liveDockSnapSide == side) return;
    _setStateSafely(() => _liveDockSnapSide = side);
  }

  void _handleLiveDockSwipe(DragEndDetails details) {
    if (_liveDockHandle == null) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 360) return;

    final snapSide = _liveDockSnapSide;
    if (snapSide == null) {
      _setLiveDockSnapSide(
        velocity < 0 ? _LiveDockSnapSide.left : _LiveDockSnapSide.right,
      );
      return;
    }

    final shouldExpand =
        (snapSide == _LiveDockSnapSide.left && velocity > 0) ||
        (snapSide == _LiveDockSnapSide.right && velocity < 0);
    if (shouldExpand) {
      _setLiveDockSnapSide(null);
    }
  }

  void _switchToTab(int index, {bool animate = true}) {
    if (index < 0 || index > 3) return;
    final previousIndex = _selectedIndex;
    if (previousIndex == 3 && index != 3 && _isProgressArrangeMode) {
      _progressArrangeController.exitArrangeMode();
      _isProgressArrangeMode = false;
    }
    if (!animate) {
      setState(() {
        _selectedIndex = index;
        if (index != 3) {
          _isProgressArrangeMode = false;
        }
        if (index == 0) {
          _selectedDay = _weekdayIndexFor(DateTime.now());
        }
        _transitionFromIndex = null;
      });
      return;
    }
    if (previousIndex == index &&
        !_shellTabTransitionController.isAnimating &&
        _transitionFromIndex == null) {
      return;
    }

    _shellTabTransitionController.stop();
    setState(() {
      _transitionFromIndex = previousIndex;
      _selectedIndex = index;
      if (index != 3) {
        _isProgressArrangeMode = false;
      }
      if (index == 0 && previousIndex != 0) {
        _selectedDay = _weekdayIndexFor(DateTime.now());
      }
    });

    if (previousIndex != index) {
      _shellTabTransitionController.forward(from: 0);
    } else if (_transitionFromIndex != null) {
      setState(() => _transitionFromIndex = null);
    }
  }

  Future<void> _openSettings() async {
    _setStateSafely(() => _suppressLiveDockUnderRoute = true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(workoutHistory: _workoutHistory),
      ),
    );
    if (!mounted) return;
    _setStateSafely(() => _suppressLiveDockUnderRoute = false);
  }

  Future<void> _openTrainingCalendar() async {
    _setStateSafely(() => _suppressLiveDockUnderRoute = true);
    final flow = await Navigator.push<WorkoutFlowFromCalendar?>(
      context,
      MaterialPageRoute<WorkoutFlowFromCalendar?>(
        builder: (_) => const TrainingCalendarScreen(),
      ),
    );
    if (!mounted) return;
    _setStateSafely(() => _suppressLiveDockUnderRoute = false);
    unawaited(_loadWeeklyTemplateSchedule());
    if (flow == null) return;
    _switchToTab(2);
    final templateId = flow.templateId;
    final startLive = flow.startLive;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setStateSafely(() {
        _pendingWorkoutCommand = WorkoutFlowCommand(
          id: _nextWorkoutCommandId(),
          target:
              startLive
                  ? WorkoutFlowRouteTarget.live
                  : WorkoutFlowRouteTarget.editor,
          templateId: templateId,
        );
      });
    });
  }

  String _nextWorkoutCommandId() =>
      'workout_cmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _openArticleCreate() async {
    final filterOptions = await ArticlesRepository.instance.getFilterOptions();
    if (!mounted) return;
    final input = await Navigator.of(context).push<ArticleInput>(
      MaterialPageRoute(
        builder:
            (_) => ArticleEditorScreen(
              machineSuggestions: filterOptions.machineIds,
            ),
      ),
    );
    if (input == null) return;
    await ArticlesRepository.instance.createArticle(input);
  }

  Widget? _shellHeaderTrailingForIndex(int index) {
    if (index == 1) {
      if (!ArticlesRepository.instance.canCreate) return null;
      return LiftIslandHeaderIconAction(
        iconWidget: MynauiIcon(
          MynauiGlyphs.plus,
          size: 22,
          color: kLiftIslandOnFrosted,
        ),
        iconSize: 22,
        onTap: _openArticleCreate,
      );
    }

    return LiftIslandHeaderAction(
      onTap: _openSettings,
      child: const MynauiIcon(
        MynauiGlyphs.userNoCircle,
        size: kLiftIslandHeaderTrailingIconSize,
        color: kLiftIslandOnFrosted,
      ),
    );
  }

  Color _shellHeaderBackgroundForIndex(int index) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const Color(0xFF090A0C);
    }
    return switch (index) {
      1 => Colors.grey.shade50,
      3 => const Color(0xFFF2F2F7),
      _ => Colors.white,
    };
  }

  Color _shellTabBackgroundForIndex(int index) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const Color(0xFF090A0C);
    }
    return switch (index) {
      1 => Colors.grey.shade50,
      3 => const Color(0xFFF2F2F7),
      _ => Colors.white,
    };
  }

  Widget _buildShellHeaderOverlay() {
    final topInset = MediaQuery.paddingOf(context).top;
    final backgroundColor = _shellHeaderBackgroundForIndex(_selectedIndex);
    final headerTop = topInset + 16;
    final coverHeight = headerTop + kLiftIslandHeaderHeight + 14;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: coverHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    backgroundColor,
                    backgroundColor,
                    backgroundColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.82, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: headerTop,
            left: kPagePadding,
            right: kPagePadding,
            child: LiftIslandHeader(
              collapseOnScroll: false,
              trailingSlotWidth: 48,
              leading: LiftIslandHeaderAction(
                onTap: _showTopLeftActions,
                child: const MynauiIcon(
                  MynauiGlyphs.qrCode,
                  size: kLiftIslandHeaderLeadingIconSize,
                  color: kLiftIslandOnFrosted,
                ),
              ),
              trailing: _shellHeaderTrailingForIndex(_selectedIndex),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTodayWorkoutDetail() async {
    final template = _activeDayTemplate;
    var exitAction = _TodayWorkoutExitAction.none;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) => TodayWorkoutDetailScreen(
              template: template,
              history: _workoutHistory,
              onEdit: () {
                exitAction = _TodayWorkoutExitAction.openEditor;
              },
              onStart: () {
                exitAction = _TodayWorkoutExitAction.startLive;
              },
            ),
      ),
    );
    if (!mounted) return;
    if (exitAction == _TodayWorkoutExitAction.none) return;

    _switchToTab(2);
    final action = exitAction;
    final templateId = template.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setStateSafely(() {
        _pendingWorkoutCommand = WorkoutFlowCommand(
          id: _nextWorkoutCommandId(),
          target:
              action == _TodayWorkoutExitAction.startLive
                  ? WorkoutFlowRouteTarget.live
                  : WorkoutFlowRouteTarget.editor,
          templateId: templateId,
        );
      });
    });
  }

  Future<void> _loadWorkoutHistory() async {
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
        if (parsed != null) {
          restored.add(parsed);
        }
      }
      if (!mounted) return;
      setState(() {
        _workoutHistory
          ..clear()
          ..addAll(restored);
      });
    } catch (_) {
      // Keep app usable if persisted history cannot be parsed.
    }
  }

  Future<void> _persistWorkoutHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        _workoutHistory.map(_historyEntryToMap).toList(growable: false),
      );
      await prefs.setString(kWorkoutHistoryStorageKey, payload);
    } catch (_) {
      // Non-fatal local persistence failure.
    }
  }

  Future<void> _loadUserGender() async {
    try {
      if (widget.signedInUserGender != null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userGenderStorageKey);
      if (raw == null) return;
      final resolved = _RecoveryUserGenderX.fromRaw(raw);
      if (!mounted || resolved == _userGender) return;
      setState(() => _userGender = resolved);
    } catch (_) {
      // Keep app usable if user profile metadata isn't available.
    }
  }

  Future<void> _loadWeeklyTemplateSchedule() async {
    try {
      final ids = await loadWeeklyTemplateSchedule();
      if (!mounted) return;
      _setStateSafely(() => _weeklyTemplateIds = ids);
    } catch (_) {
      // Non-fatal local persistence failure.
    }
  }

  void _warmShellContent() {
    if (_shellWarmupStarted) return;
    _shellWarmupStarted = true;
    unawaited(_prewarmShellData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_precacheShellImages());
    });
  }

  Future<void> _prewarmShellData() async {
    try {
      await ArticlesRepository.instance.prewarm();
    } catch (_) {
      // Keep shell usable if warmup fails.
    }
  }

  Future<void> _precacheShellImages() async {
    final urls = <String>{
          ..._templateLibrary.map((template) => template.imageUrl.trim()),
          MockMachines.swivelHandleRow.imageUrl.trim(),
          ...ArticlesRepository.instance.cachedImageUrls,
        }
        .where((url) => url.isNotEmpty && workoutTemplateImageIsNetworkUrl(url))
        .take(16)
        .toList(growable: false);

    await Future.wait(
      urls.map((url) async {
        try {
          await precacheImage(
            NetworkImage(url),
            context,
            onError: (_, __) {
              // Ignore image warmup failures and render lazily instead.
            },
          );
        } catch (_) {
          // Ignore image warmup failures and render lazily instead.
        }
      }),
    );
  }

  void _onWorkoutCompleted(WorkoutHistoryEntry entry) {
    setState(() {
      _workoutHistory.removeWhere((value) => value.id == entry.id);
      _workoutHistory.add(entry);
      _workoutHistory.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    });
    _persistWorkoutHistory();
  }

  Map<String, dynamic> _historyEntryToMap(WorkoutHistoryEntry entry) {
    return <String, dynamic>{
      'id': entry.id,
      'workoutName': entry.workoutName,
      'startedAt': entry.startedAt.toIso8601String(),
      'completedAt': entry.completedAt.toIso8601String(),
      'durationMs': entry.duration.inMilliseconds,
      'totalVolumeKg': entry.totalVolumeKg,
      'totalReps': entry.totalReps,
      'exercisesCompleted': entry.exercisesCompleted,
      'totalExercises': entry.totalExercises,
      'prsAchieved': entry.prsAchieved,
      'exerciseSummaries': entry.exerciseSummaries
          .map(
            (summary) => <String, dynamic>{
              'exerciseName': summary.exerciseName,
              'setCount': summary.setCount,
              'totalReps': summary.totalReps,
              'totalVolumeKg': summary.totalVolumeKg,
              'maxWeightKg': summary.maxWeightKg,
              'muscleGroups': summary.muscleGroups,
              'setRows': summary.setRows
                  .map(
                    (row) => <String, dynamic>{
                      'label': row.label,
                      'reps': row.reps,
                      'weightKg': row.weightKg,
                      'restSeconds': row.restSeconds,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
      'muscleGroupVolumeKg': entry.muscleGroupVolumeKg,
    };
  }

  Future<void> _showTopLeftActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: LiftMenuSheet(
            title: 'Quick actions',
            subtitle: 'Gym access and machine tools',
            children: [
              LiftMenuActionTile(
                icon: MynauiIcon(
                  MynauiGlyphs.qrCode,
                  size: 28,
                  color: kAccentColor,
                ),
                title: 'Open gym pass',
                subtitle: 'QR + backup entry code',
                accent: kAccentColor,
                onTap: () {
                  Navigator.pop(sheetContext);
                  showGymPassDialog(context);
                },
              ),
              const SizedBox(height: 8),
              LiftMenuActionTile(
                icon: MynauiIcon(
                  MynauiGlyphs.qrCode,
                  size: 28,
                  color: const Color(0xFF0A7A6B),
                ),
                title: 'Simulate machine scan',
                subtitle: 'Open Swivel Handle Row machine screen',
                accent: const Color(0xFF0A7A6B),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder:
                          (_) => const MachineScanFlowScreen(
                            machine: MockMachines.swivelHandleRow,
                          ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shellTabTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shellTabs = <Widget>[
      _ShellTabKeepAlive(child: _buildHomeTab()),
      _ShellTabKeepAlive(
        child: ArticlesScreen(
          extraBottomInset: kShellTabContentBottomInset,
          onLeadingTap: _showTopLeftActions,
        ),
      ),
      _ShellTabKeepAlive(
        child: WorkoutTemplatesFlow(
          key: _workoutTemplatesFlowKey,
          onWorkoutCompleted: _onWorkoutCompleted,
          onHideShellNavChanged: _onWorkoutShellNavVisibilityChanged,
          onLiveDockChanged: _onLiveDockChanged,
          onLiveFullscreenChanged: _onLiveFullscreenChanged,
          onLeadingTap: _showTopLeftActions,
          externalCommand: _pendingWorkoutCommand,
          onExternalCommandHandled: (id) {
            _setStateSafely(() {
              if (_pendingWorkoutCommand?.id == id) {
                _pendingWorkoutCommand = null;
              }
            });
          },
        ),
      ),
      _ShellTabKeepAlive(
        child: ProgressScreen(
          history: _workoutHistory,
          extraBottomInset:
              (_showShellBottomNav || _showProgressArrangeNav)
                  ? kShellTabContentBottomInset
                  : 0,
          onLeadingTap: _showTopLeftActions,
          onArrangeModeChanged: (value) {
            _setStateSafely(() => _isProgressArrangeMode = value);
          },
          arrangeController: _progressArrangeController,
        ),
      ),
    ];

    return Scaffold(
      extendBody: false,

      /// Keep shell nav + overlays pinned; keyboard draws on top instead of
      /// compressing the body and floating bars into the middle of the screen.
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _shellTabTransitionController,
            builder: (context, _) {
              final t = _shellTabTransitionController.value;
              final isTransitioning = _transitionFromIndex != null;
              final fromIndex = _transitionFromIndex;
              final transitionDirection =
                  fromIndex == null
                      ? 0.0
                      : (_selectedIndex >= fromIndex ? 1.0 : -1.0);
              final fadeIn = Interval(
                0.06,
                1.0,
                curve: Curves.easeOutCubic,
              ).transform(t);
              final fadeOut = Curves.easeInCubic.transform(t);

              Widget buildLayer(int index, Widget child) {
                final isSelected = index == _selectedIndex;
                final isOutgoing = fromIndex != null && index == fromIndex;
                final isVisible = isSelected || isOutgoing;
                final tabSurface = _shellTabBackgroundForIndex(index);
                if (!isVisible) {
                  Widget hidden = Visibility(
                    visible: false,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: false,
                    child: RepaintBoundary(
                      child: ColoredBox(color: tabSurface, child: child),
                    ),
                  );
                  final keepHiddenWorkoutTickersAlive =
                      index == 2 &&
                      (_liveDockHandle != null ||
                          _liveFullscreenHandle != null);
                  if (keepHiddenWorkoutTickersAlive) {
                    hidden = TickerMode(enabled: true, child: hidden);
                  }
                  return Positioned.fill(child: hidden);
                }

                /// Keep the Workouts tab's tickers running while a live session
                /// exists so timers, rest countdown, and session state survive
                /// switching shell tabs (parent [TickerMode] is off when hidden).
                final keepWorkoutTabTickersAlive =
                    index == 2 &&
                    (_liveDockHandle != null || _liveFullscreenHandle != null);
                final tickerEnabled = isSelected || keepWorkoutTabTickersAlive;

                final opacity =
                    !isTransitioning
                        ? 1.0
                        : (isSelected
                            ? lerpDouble(0.98, 1.0, fadeIn) ?? 1.0
                            : 1.0);
                final dx =
                    !isTransitioning
                        ? 0.0
                        : (isSelected
                            ? 10.0 * transitionDirection * (1.0 - fadeIn)
                            : -4.0 * transitionDirection * fadeOut);
                final scale =
                    !isTransitioning
                        ? 1.0
                        : (isSelected ? 0.998 + (0.002 * fadeIn) : 1.0);

                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !isSelected,
                    child: TickerMode(
                      enabled: tickerEnabled,
                      child: ClipRect(
                        child: ColoredBox(
                          color: tabSurface,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: opacity.clamp(0.0, 1.0),
                                child: RepaintBoundary(child: child),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final layers = <Widget>[
                for (var i = 0; i < shellTabs.length; i++)
                  if (_transitionFromIndex != i && _selectedIndex != i)
                    buildLayer(i, shellTabs[i]),
              ];
              if (_transitionFromIndex != null) {
                layers.add(
                  buildLayer(
                    _transitionFromIndex!,
                    shellTabs[_transitionFromIndex!],
                  ),
                );
              }
              layers.add(buildLayer(_selectedIndex, shellTabs[_selectedIndex]));

              return Stack(children: layers);
            },
          ),
          if (_showShellNav) _buildShellHeaderOverlay(),
          if (_liveDockHandle != null && !_suppressLiveDockUnderRoute)
            Positioned(
              left: 16,
              right: 16,
              bottom:
                  _showShellNav
                      ? kShellLiveDockBottomOffset
                      : kShellStandaloneLiveDockBottomInset,
              child: SafeArea(
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final snapSide = _liveDockSnapSide;
                    final collapsed = snapSide != null;
                    final dockWidth =
                        collapsed
                            ? math.min(188.0, constraints.maxWidth)
                            : constraints.maxWidth;
                    final alignment = switch (snapSide) {
                      _LiveDockSnapSide.left => Alignment.bottomLeft,
                      _LiveDockSnapSide.right => Alignment.bottomRight,
                      null => Alignment.bottomCenter,
                    };

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: _handleLiveDockSwipe,
                      child: AnimatedAlign(
                        duration: LiftMotion.emphasized,
                        curve: Curves.easeOutCubic,
                        alignment: alignment,
                        child: AnimatedContainer(
                          duration: LiftMotion.emphasized,
                          curve: Curves.easeOutCubic,
                          width: dockWidth,
                          child: WorkoutLiveDock(
                            state: _liveDockHandle!.state,
                            compact: collapsed,
                            onTap: () {
                              _switchToTab(2);
                              _liveDockHandle!.onResume();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_showShellNav)
            Positioned(
              left: 16,
              right: 16,
              bottom: kShellFloatingNavBottomInset,
              child: SafeArea(
                top: false,
                bottom: false,
                child: IgnorePointer(
                  ignoring: !_showShellBottomNav,
                  child: AnimatedSlide(
                    duration: LiftMotion.emphasized,
                    curve: Curves.easeOutCubic,
                    offset:
                        _showShellBottomNav
                            ? Offset.zero
                            : const Offset(0, 0.12),
                    child: AnimatedOpacity(
                      duration: LiftMotion.emphasized,
                      curve: Curves.easeOutCubic,
                      opacity: _showShellBottomNav ? 1.0 : 0.0,
                      child: _FloatingIslandNav(
                        selectedIndex: _selectedIndex,
                        onTap: _onNavItemTapped,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _todayWorkoutHeroOverlay({required WorkoutTemplate template}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  template.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WorkoutStatChip(
                    icon: const MynauiIcon(
                      MynauiGlyphs.alarmPause,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: '${template.estimatedDurationMinutes} min',
                    dark: true,
                  ),
                  const SizedBox(width: 8),
                  _WorkoutStatChip(
                    icon: const MynauiIcon(
                      MynauiGlyphs.documents,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: '${template.exercises.length} exercises',
                    dark: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final recoveryStats = _recoveryStatsFor(_activeDayTemplate);
    const islandTop = 16.0;
    final listTopPadding =
        islandTop + kLiftIslandHeaderHeight + kIslandHeaderGap;
    final scheduleWeekMonday = _mondayOfWeekContaining(DateTime.now());

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: listTopPadding,
            child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              kPagePadding,
              listTopPadding,
              kPagePadding,
              104,
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 58,
                  child: StackedWorkoutHero(
                    key: ValueKey(_selectedDay),
                    templates: _heroDayTemplates,
                    borderRadius: kIosCornerRadius,
                    onPageChanged:
                        (i) => setState(() => _todayWorkoutCarouselIndex = i),
                    onTap: _openTodayWorkoutDetail,
                    overlayBuilder:
                        (context, template, _) =>
                            _todayWorkoutHeroOverlay(template: template),
                  ),
                ),
                const SizedBox(height: 14),
                SectionBoundary(
                  padding: EdgeInsets.zero,
                  child: LiftPressable(
                    onTap: _openTrainingCalendar,
                    borderRadius: kIosCornerRadius,
                    pressedScale: LiftMotion.gentlePressScale,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kPagePadding,
                        14,
                        kPagePadding,
                        14,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Week cells are equal width; circles are 36px centered in each cell.
                          // Inset the title so its left edge lines up with the first circle.
                          final cellW = constraints.maxWidth / _kWeekdaySlots;
                          const circleD = 36.0;
                          final scheduleTitleLeftInset = math.max(
                            0.0,
                            (cellW - circleD) / 2,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(width: scheduleTitleLeftInset),
                                  Expanded(
                                    child: Text(
                                      'Schedule',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                        height: 1.2,
                                        color: kScheduleTitleColor,
                                      ),
                                    ),
                                  ),
                                  MynauiIcon(
                                    MynauiGlyphs.altArrowRight,
                                    size: 22,
                                    color: kScheduleChevronColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: List.generate(_kWeekdaySlots, (
                                  index,
                                ) {
                                  final selected = _selectedDay == index;
                                  final dayDate = scheduleWeekMonday.add(
                                    Duration(days: index),
                                  );
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => _onDaySelected(index),
                                      behavior: HitTestBehavior.opaque,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            _kScheduleWeekdayLabels[index]
                                                .toUpperCase(),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight:
                                                  selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                              height: 1.1,
                                              letterSpacing: -0.1,
                                              color:
                                                  selected
                                                      ? kScheduleTitleColor
                                                      : kAccentMid.withValues(
                                                        alpha: 0.72,
                                                      ),
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          Center(
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color:
                                                    selected
                                                        ? kScheduleDayCircleFillSelected
                                                        : Colors.white,
                                                border: Border.all(
                                                  color:
                                                      selected
                                                          ? kAccentColor
                                                          : kScheduleDayCircleBorder,
                                                  width: selected ? 2 : 1.5,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '${dayDate.day}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1,
                                                  letterSpacing: -0.2,
                                                  color:
                                                      selected
                                                          ? kAccentColor
                                                          : kAccentMid,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF20141B), Color(0xFF0F1016)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: _RecoveryStatsCarousel(
                          stats: recoveryStats,
                          onTapStat:
                              (stat) =>
                                  _openRecoveryHeatMap(stat, recoveryStats),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: islandTop,
            left: kPagePadding,
            right: kPagePadding,
            child: LiftIslandHeader(
              collapseOnScroll: false,
              leading: LiftIslandHeaderAction(
                onTap: _showTopLeftActions,
                child: const MynauiIcon(
                  MynauiGlyphs.qrCode,
                  size: kLiftIslandHeaderLeadingIconSize,
                  color: kLiftIslandOnFrosted,
                ),
              ),
              trailing: LiftIslandHeaderAction(
                onTap: _openSettings,
                child: const MynauiIcon(
                  MynauiGlyphs.userNoCircle,
                  size: kLiftIslandHeaderTrailingIconSize,
                  color: kLiftIslandOnFrosted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellTabKeepAlive extends StatefulWidget {
  const _ShellTabKeepAlive({required this.child});

  final Widget child;

  @override
  State<_ShellTabKeepAlive> createState() => _ShellTabKeepAliveState();
}

class _ShellTabKeepAliveState extends State<_ShellTabKeepAlive>
    with AutomaticKeepAliveClientMixin<_ShellTabKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}

class _WorkoutStatChip extends StatelessWidget {
  const _WorkoutStatChip({
    required this.icon,
    required this.label,
    this.dark = false,
  });

  final Widget icon;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            dark
                ? Colors.black.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(
          color:
              dark
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryMuscleStat {
  const _RecoveryMuscleStat({
    required this.muscleGroup,
    required this.recoveryPercent,
    required this.lastTrainedAt,
  });

  final String muscleGroup;
  final int recoveryPercent;
  final DateTime? lastTrainedAt;
}

const Duration _recoveryWindowDuration = Duration(hours: 72);

Duration _remainingRecoveryDuration(DateTime? lastTrainedAt) {
  if (lastTrainedAt == null) return Duration.zero;
  final remaining = lastTrainedAt
      .add(_recoveryWindowDuration)
      .difference(DateTime.now());
  if (remaining.isNegative) return Duration.zero;
  return remaining;
}

String _daysUntilRecoveryText(DateTime? lastTrainedAt) {
  final remaining = _remainingRecoveryDuration(lastTrainedAt);
  if (remaining == Duration.zero) return '0.0 days';
  final days = remaining.inMinutes / Duration.minutesPerDay;
  final decimals = days >= 10 ? 0 : 1;
  return '${days.toStringAsFixed(decimals)} days';
}

String _lastWorkedText(DateTime? lastTrainedAt) {
  if (lastTrainedAt == null) return 'No history yet';
  final diff = DateTime.now().difference(lastTrainedAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = <String>[
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
  return '${months[lastTrainedAt.month - 1]} ${lastTrainedAt.day}';
}

const String _recoveryMannequinBasePath = 'assets/images/recovery/mannequins';

class _RecoveryStatsCarousel extends StatefulWidget {
  const _RecoveryStatsCarousel({required this.stats, required this.onTapStat});

  final List<_RecoveryMuscleStat> stats;
  final ValueChanged<_RecoveryMuscleStat> onTapStat;

  @override
  State<_RecoveryStatsCarousel> createState() => _RecoveryStatsCarouselState();
}

class _RecoveryStatsCarouselState extends State<_RecoveryStatsCarousel>
    with SingleTickerProviderStateMixin {
  int _currentPage = 0;
  late final PageController _pageController;

  /// Stops the swipe hand hint after the user touches the recovery tile area.
  bool _swipeHintDismissed = false;
  AnimationController? _swipeHintController;
  Animation<double>? _swipeHintShift;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ensureSwipeHintAnimation();
  }

  void _ensureSwipeHintAnimation() {
    if (widget.stats.length <= 1) {
      _disposeSwipeHintController();
      return;
    }
    if (_swipeHintDismissed) return;
    _swipeHintController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _swipeHintShift ??= Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _swipeHintController!, curve: Curves.easeInOut),
    );
    if (!_swipeHintController!.isAnimating) {
      _swipeHintController!.repeat(reverse: true);
    }
  }

  void _disposeSwipeHintController() {
    _swipeHintController?.dispose();
    _swipeHintController = null;
    _swipeHintShift = null;
  }

  void _onRecoveryTilePointerDown() {
    if (_swipeHintDismissed) return;
    _disposeSwipeHintController();
    setState(() => _swipeHintDismissed = true);
  }

  @override
  void didUpdateWidget(covariant _RecoveryStatsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stats.isEmpty) {
      _currentPage = 0;
      return;
    }
    if (_currentPage >= widget.stats.length) {
      _currentPage = widget.stats.length - 1;
      _pageController.jumpToPage(_currentPage);
    }
    _ensureSwipeHintAnimation();
  }

  @override
  void dispose() {
    _disposeSwipeHintController();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stats.isEmpty) {
      return Center(
        child: Text(
          'Recovery stats unavailable',
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onRecoveryTilePointerDown(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Row(
              children: [
                Text(
                  'RECOVERY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (widget.stats.length > 1 &&
                    !_swipeHintDismissed &&
                    _swipeHintShift != null)
                  SizedBox(
                    height: 22,
                    child: AnimatedBuilder(
                      animation: _swipeHintShift!,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(_swipeHintShift!.value, 0),
                          child: child,
                        );
                      },
                      child: MynauiIcon(
                        MynauiGlyphs.handMoveStreamlineTabler,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kIosCornerRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Shared dial and indicator, driven by _currentPage.
                  Builder(
                    builder: (context) {
                      final stat = widget.stats[_currentPage];
                      return IgnorePointer(
                        ignoring: true,
                        child: RecoveryDialCard(
                          muscleName: stat.muscleGroup,
                          percentage: stat.recoveryPercent,
                          recoveryEtaLabel:
                              '${_daysUntilRecoveryText(stat.lastTrainedAt)} to recovery',
                          lastHitLabel:
                              'Last hit ${_lastWorkedText(stat.lastTrainedAt).toLowerCase()}',
                          showDots: widget.stats.length > 1,
                          dotCount: widget.stats.length,
                          activeDotIndex: _currentPage,
                        ),
                      );
                    },
                  ),
                  // Invisible pages on top to handle swipe + tap.
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.stats.length,
                    physics: const ClampingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kIosCornerRadius),
                          onTap: () {
                            final stat = widget.stats[_currentPage];
                            widget.onTapStat(stat);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RecoveryBodyRegion {
  shoulders,
  chest,
  abs,
  back,
  lats,
  biceps,
  triceps,
  forearms,
  glutes,
  quads,
  hamstrings,
  calves,
}

enum _RecoveryUserGender { male, female }

enum _RecoveryState { recovered, mid, fatigued }

extension _RecoveryUserGenderX on _RecoveryUserGender {
  static _RecoveryUserGender fromRaw(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'female' ||
        normalized == 'f' ||
        normalized == 'woman' ||
        normalized == 'girl') {
      return _RecoveryUserGender.female;
    }
    return _RecoveryUserGender.male;
  }
}

Color _recoveryStateColor(_RecoveryState state) {
  switch (state) {
    case _RecoveryState.recovered:
      return Colors.green.shade500;
    case _RecoveryState.mid:
      return kRecoveryMidColor;
    case _RecoveryState.fatigued:
      return Colors.red.shade500;
  }
}

Color _recoveryOverlayColor(
  _RecoveryState state, {
  bool emphasized = false,
  double pulse = 0,
}) {
  final base = _recoveryStateColor(state);
  final pulseBoost = emphasized ? lerpDouble(0.62, 1.48, pulse)! : 1.0;
  double alpha;
  double maxAlpha;
  switch (state) {
    case _RecoveryState.recovered:
      alpha = emphasized ? 0.34 : 0.12;
      maxAlpha = emphasized ? 0.46 : 0.20;
      break;
    case _RecoveryState.mid:
      alpha = emphasized ? 0.62 : 0.46;
      maxAlpha = emphasized ? 0.64 : 0.50;
      break;
    case _RecoveryState.fatigued:
      alpha = emphasized ? 0.72 : 0.56;
      maxAlpha = emphasized ? 0.70 : 0.58;
      break;
  }
  final finalAlpha = (alpha * pulseBoost).clamp(0, maxAlpha).toDouble();
  return base.withValues(alpha: finalAlpha);
}

Color _recoveryOutlineColor(
  _RecoveryState state, {
  bool emphasized = false,
  double pulse = 0,
}) {
  final base = _recoveryStateColor(state);
  final pulseBoost = emphasized ? lerpDouble(0.55, 1.65, pulse)! : 1.0;
  double alpha;
  switch (state) {
    case _RecoveryState.recovered:
      alpha = emphasized ? 0.56 : 0.22;
      break;
    case _RecoveryState.mid:
      alpha = emphasized ? 0.68 : 0.34;
      break;
    case _RecoveryState.fatigued:
      alpha = emphasized ? 0.78 : 0.42;
      break;
  }
  return base.withValues(alpha: (alpha * pulseBoost).clamp(0, 1).toDouble());
}

int _recoveryStatePriority(_RecoveryState state) {
  switch (state) {
    case _RecoveryState.recovered:
      return 0;
    case _RecoveryState.mid:
      return 1;
    case _RecoveryState.fatigued:
      return 2;
  }
}

Set<_RecoveryBodyRegion> _regionsForMuscle(String muscleGroup) {
  final value = muscleGroup.toLowerCase();
  if (value.contains('quad')) {
    return {_RecoveryBodyRegion.quads};
  }
  if (value.contains('ham')) {
    return {_RecoveryBodyRegion.hamstrings};
  }
  if (value.contains('glute')) {
    return {_RecoveryBodyRegion.glutes};
  }
  if (value.contains('chest')) {
    return {_RecoveryBodyRegion.chest};
  }
  if (value.contains('shoulder')) {
    return {_RecoveryBodyRegion.shoulders};
  }
  if (value.contains('back')) {
    return {_RecoveryBodyRegion.back, _RecoveryBodyRegion.lats};
  }
  if (value.contains('lat')) {
    return {_RecoveryBodyRegion.lats};
  }
  if (value.contains('bicep')) {
    return {_RecoveryBodyRegion.biceps};
  }
  if (value.contains('tricep')) {
    return {_RecoveryBodyRegion.triceps};
  }
  if (value.contains('forearm') ||
      value.contains('wrist') ||
      value.contains('grip')) {
    return {_RecoveryBodyRegion.forearms};
  }
  if (value.contains('arm')) {
    return {
      _RecoveryBodyRegion.biceps,
      _RecoveryBodyRegion.triceps,
      _RecoveryBodyRegion.forearms,
    };
  }
  if (value.contains('core') || value.contains('ab')) {
    return {_RecoveryBodyRegion.abs};
  }
  if (value.contains('calf') || value.contains('calves')) {
    return {_RecoveryBodyRegion.calves};
  }
  return {_RecoveryBodyRegion.abs};
}

enum _RecoveryBodyType { male, female }

enum _RecoveryBodyView { front, back }

enum _RecoveryMuscleRegion {
  leftDeltoid,
  rightDeltoid,
  leftPectoralisMajor,
  rightPectoralisMajor,
  leftBicepsBrachii,
  rightBicepsBrachii,
  leftForearmAnterior,
  rightForearmAnterior,
  rectusAbdominis,
  leftExternalOblique,
  rightExternalOblique,
  leftQuadricepsFemoris,
  rightQuadricepsFemoris,
  leftTibialisAnterior,
  rightTibialisAnterior,
  leftUpperTrapezius,
  rightUpperTrapezius,
  leftLatissimusDorsi,
  rightLatissimusDorsi,
  leftTricepsBrachii,
  rightTricepsBrachii,
  leftForearmPosterior,
  rightForearmPosterior,
  leftGluteusMaximus,
  rightGluteusMaximus,
  leftHamstrings,
  rightHamstrings,
  leftGastrocnemius,
  rightGastrocnemius,
  erectorsSpinae,
}

class _RecoveryMuscleRegionPaths {
  _RecoveryMuscleRegionPaths() {
    _initializeFemaleFrontPaths();
    _initializeFemaleBackPaths();
    _initializeMaleFrontPaths();
    _initializeMaleBackPaths();
  }

  static const double designWidth = 930;
  static const double designHeight = 1300;

  final Map<String, Map<_RecoveryMuscleRegion, Path>> _paths = {};

  String _getKey(_RecoveryBodyType bodyType, _RecoveryBodyView view) =>
      '${bodyType.name}_${view.name}';

  Map<_RecoveryMuscleRegion, Path> getPaths(
    _RecoveryBodyType bodyType,
    _RecoveryBodyView view,
  ) {
    return _paths[_getKey(bodyType, view)] ??
        const <_RecoveryMuscleRegion, Path>{};
  }

  Path _roundedRect({
    required double left,
    required double top,
    required double width,
    required double height,
    double radius = kIosCornerRadius,
  }) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        Radius.circular(radius),
      ),
    );
  }

  Path _ellipse({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    return Path()..addOval(Rect.fromLTWH(left, top, width, height));
  }

  Path _rotatedRoundedRect({
    required double left,
    required double top,
    required double width,
    required double height,
    required double radius,
    required double angleRadians,
    double pivotXFactor = 0.5,
    double pivotYFactor = 0.5,
  }) {
    final path = _roundedRect(
      left: left,
      top: top,
      width: width,
      height: height,
      radius: radius,
    );
    final centerX = left + (width * pivotXFactor);
    final centerY = top + (height * pivotYFactor);
    final cosA = math.cos(angleRadians);
    final sinA = math.sin(angleRadians);
    final tx = centerX - (centerX * cosA) + (centerY * sinA);
    final ty = centerY - (centerX * sinA) - (centerY * cosA);
    return path.transform(
      Float64List.fromList([
        cosA,
        sinA,
        0,
        0,
        -sinA,
        cosA,
        0,
        0,
        0,
        0,
        1,
        0,
        tx,
        ty,
        0,
        1,
      ]),
    );
  }

  Map<_RecoveryMuscleRegion, Path> _cloneMap(
    Map<_RecoveryMuscleRegion, Path> source,
  ) {
    return source.map(
      (region, path) =>
          MapEntry<_RecoveryMuscleRegion, Path>(region, Path.from(path)),
    );
  }

  void _initializeFemaleFrontPaths() {
    final key = _getKey(_RecoveryBodyType.female, _RecoveryBodyView.front);
    final regionPaths = <_RecoveryMuscleRegion, Path>{
      _RecoveryMuscleRegion.leftDeltoid: _ellipse(
        left: 230,
        top: 228,
        width: 92,
        height: 86,
      ),
      _RecoveryMuscleRegion.rightDeltoid: _ellipse(
        left: 608,
        top: 228,
        width: 92,
        height: 86,
      ),
      _RecoveryMuscleRegion.leftPectoralisMajor: _ellipse(
        left: 317,
        top: 242,
        width: 132,
        height: 116,
      ),
      _RecoveryMuscleRegion.rightPectoralisMajor: _ellipse(
        left: 483,
        top: 242,
        width: 132,
        height: 116,
      ),
      _RecoveryMuscleRegion.leftBicepsBrachii: _ellipse(
        left: 190,
        top: 338,
        width: 86,
        height: 112,
      ),
      _RecoveryMuscleRegion.rightBicepsBrachii: _ellipse(
        left: 654,
        top: 338,
        width: 86,
        height: 112,
      ),
      _RecoveryMuscleRegion.leftForearmAnterior: _rotatedRoundedRect(
        left: 156,
        top: 456,
        width: 50,
        height: 142,
        radius: kIosCornerRadius,
        angleRadians: 0.46,
        pivotYFactor: 0.24,
      ),
      _RecoveryMuscleRegion.rightForearmAnterior: _rotatedRoundedRect(
        left: 716,
        top: 456,
        width: 50,
        height: 142,
        radius: kIosCornerRadius,
        angleRadians: -0.46,
        pivotYFactor: 0.24,
      ),
      _RecoveryMuscleRegion.rectusAbdominis: _roundedRect(
        left: 398,
        top: 390,
        width: 134,
        height: 184,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.leftExternalOblique: _ellipse(
        left: 326,
        top: 462,
        width: 74,
        height: 102,
      ),
      _RecoveryMuscleRegion.rightExternalOblique: _ellipse(
        left: 530,
        top: 462,
        width: 74,
        height: 102,
      ),
      _RecoveryMuscleRegion.leftQuadricepsFemoris: _roundedRect(
        left: 314,
        top: 646,
        width: 96,
        height: 194,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.rightQuadricepsFemoris: _roundedRect(
        left: 520,
        top: 646,
        width: 96,
        height: 194,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.leftTibialisAnterior: _roundedRect(
        left: 322,
        top: 950,
        width: 68,
        height: 230,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.rightTibialisAnterior: _roundedRect(
        left: 540,
        top: 950,
        width: 68,
        height: 230,
        radius: kIosCornerRadius,
      ),
    };
    _paths[key] = regionPaths;
  }

  void _initializeFemaleBackPaths() {
    final key = _getKey(_RecoveryBodyType.female, _RecoveryBodyView.back);
    final regionPaths = <_RecoveryMuscleRegion, Path>{
      _RecoveryMuscleRegion.leftDeltoid: _ellipse(
        left: 230,
        top: 228,
        width: 92,
        height: 86,
      ),
      _RecoveryMuscleRegion.rightDeltoid: _ellipse(
        left: 608,
        top: 228,
        width: 92,
        height: 86,
      ),
      _RecoveryMuscleRegion.leftUpperTrapezius: _ellipse(
        left: 304,
        top: 202,
        width: 112,
        height: 96,
      ),
      _RecoveryMuscleRegion.rightUpperTrapezius: _ellipse(
        left: 514,
        top: 202,
        width: 112,
        height: 96,
      ),
      _RecoveryMuscleRegion.leftLatissimusDorsi: _roundedRect(
        left: 278,
        top: 340,
        width: 112,
        height: 184,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.rightLatissimusDorsi: _roundedRect(
        left: 540,
        top: 340,
        width: 112,
        height: 184,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.leftTricepsBrachii: _ellipse(
        left: 188,
        top: 320,
        width: 88,
        height: 108,
      ),
      _RecoveryMuscleRegion.rightTricepsBrachii: _ellipse(
        left: 654,
        top: 320,
        width: 88,
        height: 108,
      ),
      _RecoveryMuscleRegion.leftForearmPosterior: _rotatedRoundedRect(
        left: 156,
        top: 458,
        width: 58,
        height: 142,
        radius: kIosCornerRadius,
        angleRadians: 0.40,
        pivotYFactor: 0.24,
      ),
      _RecoveryMuscleRegion.rightForearmPosterior: _rotatedRoundedRect(
        left: 716,
        top: 458,
        width: 58,
        height: 142,
        radius: kIosCornerRadius,
        angleRadians: -0.40,
        pivotYFactor: 0.24,
      ),
      _RecoveryMuscleRegion.erectorsSpinae: _roundedRect(
        left: 430,
        top: 304,
        width: 70,
        height: 286,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.leftGluteusMaximus: _ellipse(
        left: 316,
        top: 554,
        width: 136,
        height: 132,
      ),
      _RecoveryMuscleRegion.rightGluteusMaximus: _ellipse(
        left: 478,
        top: 554,
        width: 136,
        height: 132,
      ),
      _RecoveryMuscleRegion.leftHamstrings: _roundedRect(
        left: 308,
        top: 724,
        width: 94,
        height: 170,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.rightHamstrings: _roundedRect(
        left: 528,
        top: 724,
        width: 94,
        height: 170,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.leftGastrocnemius: _roundedRect(
        left: 322,
        top: 955,
        width: 68,
        height: 196,
        radius: kIosCornerRadius,
      ),
      _RecoveryMuscleRegion.rightGastrocnemius: _roundedRect(
        left: 540,
        top: 955,
        width: 68,
        height: 196,
        radius: kIosCornerRadius,
      ),
    };
    _paths[key] = regionPaths;
  }

  void _initializeMaleFrontPaths() {
    final key = _getKey(_RecoveryBodyType.male, _RecoveryBodyView.front);
    final base = getPaths(_RecoveryBodyType.female, _RecoveryBodyView.front);
    _paths[key] = _cloneMap(base);
  }

  void _initializeMaleBackPaths() {
    final key = _getKey(_RecoveryBodyType.male, _RecoveryBodyView.back);
    final base = getPaths(_RecoveryBodyType.female, _RecoveryBodyView.back);
    _paths[key] = _cloneMap(base);
  }
}

const Map<_RecoveryMuscleRegion, _RecoveryBodyRegion> _frontMuscleRegionMap = {
  _RecoveryMuscleRegion.leftDeltoid: _RecoveryBodyRegion.shoulders,
  _RecoveryMuscleRegion.rightDeltoid: _RecoveryBodyRegion.shoulders,
  _RecoveryMuscleRegion.leftPectoralisMajor: _RecoveryBodyRegion.chest,
  _RecoveryMuscleRegion.rightPectoralisMajor: _RecoveryBodyRegion.chest,
  _RecoveryMuscleRegion.leftBicepsBrachii: _RecoveryBodyRegion.biceps,
  _RecoveryMuscleRegion.rightBicepsBrachii: _RecoveryBodyRegion.biceps,
  _RecoveryMuscleRegion.leftForearmAnterior: _RecoveryBodyRegion.forearms,
  _RecoveryMuscleRegion.rightForearmAnterior: _RecoveryBodyRegion.forearms,
  _RecoveryMuscleRegion.rectusAbdominis: _RecoveryBodyRegion.abs,
  _RecoveryMuscleRegion.leftExternalOblique: _RecoveryBodyRegion.abs,
  _RecoveryMuscleRegion.rightExternalOblique: _RecoveryBodyRegion.abs,
  _RecoveryMuscleRegion.leftQuadricepsFemoris: _RecoveryBodyRegion.quads,
  _RecoveryMuscleRegion.rightQuadricepsFemoris: _RecoveryBodyRegion.quads,
  _RecoveryMuscleRegion.leftTibialisAnterior: _RecoveryBodyRegion.calves,
  _RecoveryMuscleRegion.rightTibialisAnterior: _RecoveryBodyRegion.calves,
};

const Map<_RecoveryMuscleRegion, _RecoveryBodyRegion> _backMuscleRegionMap = {
  _RecoveryMuscleRegion.leftDeltoid: _RecoveryBodyRegion.shoulders,
  _RecoveryMuscleRegion.rightDeltoid: _RecoveryBodyRegion.shoulders,
  _RecoveryMuscleRegion.leftUpperTrapezius: _RecoveryBodyRegion.back,
  _RecoveryMuscleRegion.rightUpperTrapezius: _RecoveryBodyRegion.back,
  _RecoveryMuscleRegion.erectorsSpinae: _RecoveryBodyRegion.back,
  _RecoveryMuscleRegion.leftLatissimusDorsi: _RecoveryBodyRegion.lats,
  _RecoveryMuscleRegion.rightLatissimusDorsi: _RecoveryBodyRegion.lats,
  _RecoveryMuscleRegion.leftTricepsBrachii: _RecoveryBodyRegion.triceps,
  _RecoveryMuscleRegion.rightTricepsBrachii: _RecoveryBodyRegion.triceps,
  _RecoveryMuscleRegion.leftForearmPosterior: _RecoveryBodyRegion.forearms,
  _RecoveryMuscleRegion.rightForearmPosterior: _RecoveryBodyRegion.forearms,
  _RecoveryMuscleRegion.leftGluteusMaximus: _RecoveryBodyRegion.glutes,
  _RecoveryMuscleRegion.rightGluteusMaximus: _RecoveryBodyRegion.glutes,
  _RecoveryMuscleRegion.leftHamstrings: _RecoveryBodyRegion.hamstrings,
  _RecoveryMuscleRegion.rightHamstrings: _RecoveryBodyRegion.hamstrings,
  _RecoveryMuscleRegion.leftGastrocnemius: _RecoveryBodyRegion.calves,
  _RecoveryMuscleRegion.rightGastrocnemius: _RecoveryBodyRegion.calves,
};

final _RecoveryMuscleRegionPaths _recoveryMuscleRegionPaths =
    _RecoveryMuscleRegionPaths();

class _RecoveryMannequinOverlayPainter extends CustomPainter {
  const _RecoveryMannequinOverlayPainter({
    required this.states,
    required this.activeRegions,
    required this.pulse,
    required this.bodyType,
    required this.view,
  });

  final Map<_RecoveryBodyRegion, _RecoveryState> states;
  final Set<_RecoveryBodyRegion> activeRegions;
  final double pulse;
  final _RecoveryBodyType bodyType;
  final _RecoveryBodyView view;

  Size _sourceImageSize() {
    switch (bodyType) {
      case _RecoveryBodyType.female:
        return const Size(1094, 2407);
      case _RecoveryBodyType.male:
        return const Size(1215, 2447);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final musclePaths = _recoveryMuscleRegionPaths.getPaths(bodyType, view);
    if (musclePaths.isEmpty || size.isEmpty) return;

    final mapping =
        view == _RecoveryBodyView.front
            ? _frontMuscleRegionMap
            : _backMuscleRegionMap;

    final outputRect = Offset.zero & size;
    final fitted = applyBoxFit(BoxFit.contain, _sourceImageSize(), size);
    final destinationRect = Alignment.topCenter.inscribe(
      fitted.destination,
      outputRect,
    );

    if (destinationRect.isEmpty) return;

    final scaleMatrix = Float64List.fromList([
      destinationRect.width / _RecoveryMuscleRegionPaths.designWidth,
      0,
      0,
      0,
      0,
      destinationRect.height / _RecoveryMuscleRegionPaths.designHeight,
      0,
      0,
      0,
      0,
      1,
      0,
      destinationRect.left,
      destinationRect.top,
      0,
      1,
    ]);

    final fillPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
    final outlinePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..isAntiAlias = true;
    final glowPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final orderedEntries = mapping.entries.toList(growable: false)
      ..sort((a, b) {
        final aState = states[a.value] ?? _RecoveryState.recovered;
        final bState = states[b.value] ?? _RecoveryState.recovered;
        return _recoveryStatePriority(
          aState,
        ).compareTo(_recoveryStatePriority(bState));
      });

    canvas.save();
    canvas.clipRect(destinationRect);
    for (final entry in orderedEntries) {
      final rawPath = musclePaths[entry.key];
      if (rawPath == null) continue;
      final region = entry.value;
      final state = states[region] ?? _RecoveryState.recovered;
      final emphasized = activeRegions.contains(region);
      final pulseT = emphasized ? Curves.easeInOut.transform(pulse) : 0.0;
      final scaledPath = rawPath.transform(scaleMatrix);
      var animatedPath = scaledPath;

      if (emphasized) {
        final bounds = scaledPath.getBounds();
        if (bounds.isFinite && !bounds.isEmpty) {
          final scale = 1 + (0.045 * pulseT);
          final tx = bounds.center.dx - (bounds.center.dx * scale);
          final ty = bounds.center.dy - (bounds.center.dy * scale);
          animatedPath = scaledPath.transform(
            Float64List.fromList([
              scale,
              0,
              0,
              0,
              0,
              scale,
              0,
              0,
              0,
              0,
              1,
              0,
              tx,
              ty,
              0,
              1,
            ]),
          );
        }

        glowPaint
          ..strokeWidth = 2.6 + (2.8 * pulseT)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 + (3.8 * pulseT))
          ..color = _recoveryStateColor(
            state,
          ).withValues(alpha: 0.22 + (0.30 * pulseT));
        canvas.drawPath(animatedPath, glowPaint);
      }

      fillPaint.color = _recoveryOverlayColor(
        state,
        emphasized: emphasized,
        pulse: pulseT,
      );
      outlinePaint.color = _recoveryOutlineColor(
        state,
        emphasized: emphasized,
        pulse: pulseT,
      );
      outlinePaint.strokeWidth = emphasized ? (1.2 + (1.6 * pulseT)) : 1;
      canvas.drawPath(animatedPath, fillPaint);
      canvas.drawPath(animatedPath, outlinePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RecoveryMannequinOverlayPainter oldDelegate) {
    return oldDelegate.states != states ||
        !setEquals(oldDelegate.activeRegions, activeRegions) ||
        oldDelegate.pulse != pulse ||
        oldDelegate.bodyType != bodyType ||
        oldDelegate.view != view;
  }
}

class _RecoveryHeatMapSheet extends StatefulWidget {
  const _RecoveryHeatMapSheet({
    required this.stat,
    required this.allStats,
    required this.heatColor,
    required this.regions,
    required this.userGender,
  });

  final _RecoveryMuscleStat stat;
  final List<_RecoveryMuscleStat> allStats;
  final Color heatColor;
  final Set<_RecoveryBodyRegion> regions;
  final _RecoveryUserGender userGender;

  @override
  State<_RecoveryHeatMapSheet> createState() => _RecoveryHeatMapSheetState();
}

class _RecoveryHeatMapSheetState extends State<_RecoveryHeatMapSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  _RecoveryState _stateFromPercent(int recoveryPercent) {
    if (recoveryPercent >= 80) return _RecoveryState.recovered;
    if (recoveryPercent >= 50) return _RecoveryState.mid;
    return _RecoveryState.fatigued;
  }

  Map<_RecoveryBodyRegion, _RecoveryState> _regionStates() {
    final regionStates = <_RecoveryBodyRegion, _RecoveryState>{
      for (final region in _RecoveryBodyRegion.values)
        region: _RecoveryState.recovered,
    };

    for (final muscleStat in widget.allStats) {
      final state = _stateFromPercent(muscleStat.recoveryPercent);
      final statRegions = _regionsForMuscle(muscleStat.muscleGroup);
      for (final region in statRegions) {
        final current = regionStates[region] ?? _RecoveryState.recovered;
        if (_recoveryStatePriority(state) >= _recoveryStatePriority(current)) {
          regionStates[region] = state;
        }
      }
    }

    return regionStates;
  }

  String _statusLabel() {
    if (widget.stat.recoveryPercent >= 80) return 'Recovered';
    if (widget.stat.recoveryPercent >= 50) return 'Recovering';
    return 'Fatigued';
  }

  String _detailEtaLabel() {
    if (widget.stat.recoveryPercent >= 100 ||
        _remainingRecoveryDuration(widget.stat.lastTrainedAt) ==
            Duration.zero) {
      return 'Recovered';
    }
    return _daysUntilRecoveryText(widget.stat.lastTrainedAt);
  }

  String _detailLastWorkedLabel() {
    return _lastWorkedText(widget.stat.lastTrainedAt);
  }

  Widget _detailInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(kIosCornerRadius),
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.3,
                    color: Colors.grey.shade900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(_RecoveryState state, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _recoveryStateColor(state),
            borderRadius: BorderRadius.circular(kIosCornerRadius),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final regionStates = _regionStates();

    return Column(
      children: [
        Container(
          width: 46,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(kIosCornerRadius),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.stat.muscleGroup} recovery',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${widget.stat.recoveryPercent}%',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: widget.heatColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _statusLabel(),
            style: TextStyle(
              fontSize: 13,
              color: widget.heatColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Row(
                children: [
                  Expanded(
                    child: _RecoveryMannequinFigure(
                      title: 'Front',
                      front: true,
                      states: regionStates,
                      activeRegions: widget.regions,
                      pulse: _pulse.value,
                      userGender: widget.userGender,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RecoveryMannequinFigure(
                      title: 'Back',
                      front: false,
                      states: regionStates,
                      activeRegions: widget.regions,
                      pulse: _pulse.value,
                      userGender: widget.userGender,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _detailInfoCard(
                icon: Icons.timelapse_rounded,
                label: 'Recovery ETA',
                value: _detailEtaLabel(),
                accent: widget.heatColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _detailInfoCard(
                icon: Icons.history_rounded,
                label: 'Last Worked',
                value: _detailLastWorkedLabel(),
                accent: const Color(0xFF5A6475),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.bottomCenter,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _legendItem(_RecoveryState.recovered, 'Recovered'),
              _legendItem(_RecoveryState.mid, 'Mid'),
              _legendItem(_RecoveryState.fatigued, 'Fatigued'),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecoveryMannequinFigure extends StatelessWidget {
  const _RecoveryMannequinFigure({
    required this.title,
    required this.front,
    required this.states,
    required this.activeRegions,
    required this.pulse,
    required this.userGender,
  });

  final String title;
  final bool front;
  final Map<_RecoveryBodyRegion, _RecoveryState> states;
  final Set<_RecoveryBodyRegion> activeRegions;
  final double pulse;
  final _RecoveryUserGender userGender;

  _RecoveryBodyType get _bodyType =>
      userGender == _RecoveryUserGender.female
          ? _RecoveryBodyType.female
          : _RecoveryBodyType.male;

  _RecoveryBodyView get _bodyView =>
      front ? _RecoveryBodyView.front : _RecoveryBodyView.back;

  String _mannequinAssetPath() {
    switch ((userGender, front)) {
      case (_RecoveryUserGender.female, true):
        return '$_recoveryMannequinBasePath/female_front.png';
      case (_RecoveryUserGender.female, false):
        return '$_recoveryMannequinBasePath/female_back.png';
      case (_RecoveryUserGender.male, true):
        return '$_recoveryMannequinBasePath/male_front.png';
      case (_RecoveryUserGender.male, false):
        return '$_recoveryMannequinBasePath/male_back.png';
    }
  }

  Widget _part({
    required double leftFactor,
    required double topFactor,
    required double widthFactor,
    required double heightFactor,
    required double radius,
    required Color color,
  }) {
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment(
          (leftFactor + (widthFactor / 2)) * 2 - 1,
          (topFactor + (heightFactor / 2)) * 2 - 1,
        ),
        widthFactor: widthFactor,
        heightFactor: heightFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }

  List<Widget> _fallbackBaseParts(Color baseColor) {
    return [
      _part(
        leftFactor: 0.43,
        topFactor: 0.06,
        widthFactor: 0.14,
        heightFactor: 0.09,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.40,
        topFactor: 0.15,
        widthFactor: 0.20,
        heightFactor: 0.26,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.22,
        topFactor: 0.16,
        widthFactor: 0.12,
        heightFactor: 0.30,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.66,
        topFactor: 0.16,
        widthFactor: 0.12,
        heightFactor: 0.30,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.35,
        topFactor: 0.41,
        widthFactor: 0.30,
        heightFactor: 0.11,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.39,
        topFactor: 0.52,
        widthFactor: 0.10,
        heightFactor: 0.30,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.51,
        topFactor: 0.52,
        widthFactor: 0.10,
        heightFactor: 0.30,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.39,
        topFactor: 0.83,
        widthFactor: 0.10,
        heightFactor: 0.14,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
      _part(
        leftFactor: 0.51,
        topFactor: 0.83,
        widthFactor: 0.10,
        heightFactor: 0.14,
        radius: kIosCornerRadius,
        color: baseColor,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.grey.withValues(alpha: 0.24);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.24)),
        color: const Color(0xFFF8F8F9),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 165,
                  maxHeight: 350,
                ),
                child: AspectRatio(
                  aspectRatio: 0.58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          _mannequinAssetPath(),
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) {
                            return Stack(
                              fit: StackFit.expand,
                              children: _fallbackBaseParts(baseColor),
                            );
                          },
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RecoveryMannequinOverlayPainter(
                            states: states,
                            activeRegions: activeRegions,
                            pulse: pulse,
                            bodyType: _bodyType,
                            view: _bodyView,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingIslandNav extends StatelessWidget {
  const _FloatingIslandNav({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static const Color _navBackground = Color(0xEAF7F7F7);
  static const Color _navBorder = Color(0x12000000);
  static const Color _navHighlight = Color(0xFF111111);
  static const double _navBorderRadius = 30.0;

  @override
  Widget build(BuildContext context) {
    final items = [
      (index: 0, assetPath: MynauiGlyphs.home, label: 'Home'),
      (index: 1, assetPath: MynauiGlyphs.guides, label: 'Guides'),
      (index: 2, assetPath: MynauiGlyphs.weightlifting, label: 'Workouts'),
      (index: 3, assetPath: MynauiGlyphs.progress, label: 'Progress'),
    ];

    return SizedBox(
      height: kShellFloatingNavBarHeight,
      child: LiftFloatingIslandSurface(
        borderRadius: _navBorderRadius,
        backgroundColor: _navBackground,
        borderColor: _navBorder,
        blurSigma: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: items
                .map(
                  (item) => _NavItem(
                    index: item.index,
                    selectedIndex: selectedIndex,
                    onTap: onTap,
                    iconAssetPath: item.assetPath,
                    label: item.label,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.selectedIndex,
    required this.onTap,
    required this.iconAssetPath,
    required this.label,
  });

  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final String iconAssetPath;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    final iconColor =
        isSelected
            ? Colors.white.withValues(alpha: 0.96)
            : Colors.black.withValues(alpha: 0.74);

    return AnimatedContainer(
      duration: LiftMotion.emphasized,
      curve: Curves.easeOutCubic,
      width: isSelected ? 138 : 42,
      height: 42,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowLabel = isSelected && constraints.maxWidth >= 88;
          return LiftPressable(
            onTap: () => onTap(index),
            borderRadius: kIosControlRadius,
            pressedScale:
                isSelected
                    ? LiftMotion.gentlePressScale
                    : LiftMotion.pressScale,
            child: Ink(
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? _FloatingIslandNav._navHighlight
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(kIosControlRadius),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: canShowLabel ? 10 : 0,
                vertical: 5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Center(
                      child: MynauiIcon(
                        iconAssetPath,
                        color: iconColor,
                        size: 19,
                      ),
                    ),
                  ),
                  Flexible(
                    child: AnimatedSize(
                      duration: LiftMotion.emphasized,
                      curve: Curves.easeOutCubic,
                      child:
                          canShowLabel
                              ? Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 4,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.96),
                                    height: 1.0,
                                    letterSpacing: -0.08,
                                  ),
                                ),
                              )
                              : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lift/app/app_bootstrap.dart';
import 'package:lift/features/home/today_workout_detail_screen.dart';
import 'package:lift/app/theme.dart';
import 'package:lift/features/machines/machine_scan_flow_screen.dart';
import 'package:lift/features/machines/mock_machines.dart';
import 'package:lift/features/pass/gym_pass_dialog.dart';
import 'package:lift/features/settings/settings_screen.dart';
import 'package:lift/features/workout/mock_workout_templates.dart';
import 'package:lift/shared/icons/mynaui_glyphs.dart';
import 'package:lift/shared/icons/mynaui_icon.dart';
import 'package:lift/shared/models/workout_template.dart';
import 'package:lift/shared/widgets/lift_island_header.dart';
import 'package:lift/shared/widgets/lift_menu_sheet.dart';
import 'package:lift/shared/widgets/lift_pressable.dart';
import 'package:lift/shared/widgets/stacked_workout_hero.dart';
import 'package:lift/shared/stored_weekly_template_schedule.dart';
import 'package:lift/shared/weekly_default_template_schedule.dart';
import 'package:lift/shared/widgets/workout_detail_action_island.dart';
import 'package:lift/shared/widgets/workout_template_hero_image.dart';

const _monthShort = <String>[
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

const _monthLong = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Monday-first weekday labels (matches home week strip).
const _kWeekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Short labels for timeline (Mon–Sun, [weekday] → index with DateTime.weekday).
const _kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Height of one workout tile; day letter badge is square with this side length.
const double _kScheduleTileExtent = 76;

/// Vertical padding on the drag-target [AnimatedContainer] (`vertical: 2` × 2).
const double _kDayRowDragChromePadV = 4.0;

/// Small guard for fractional row heights so edit-mode schedule tiles do not
/// overflow by a pixel after AnimatedSize / border rounding.
const double _kDayRowOverflowGuardV = 1.5;

/// Taller than [kLiftIslandHeaderHeight] so month-view hint text can wrap fully.
const double _kMonthGridIslandHintBarHeight = 72.0;

/// Tile layout for one week row — must match [_DayScheduleRow] math.
({double vPad, double tileH, double tileGap, double innerH}) _metricsForDayRow(
  double rowHeight,
  int slotCount,
) {
  final vPad = (rowHeight * 0.08).clamp(4.0, 10.0);
  final innerH = (rowHeight -
          2 * vPad -
          _kDayRowDragChromePadV -
          _kDayRowOverflowGuardV)
      .clamp(0.0, double.infinity);
  final n = slotCount == 0 ? 1 : slotCount;
  final tileGap = n > 1 ? (innerH * 0.06).clamp(2.0, 8.0) : 0.0;
  final tileH =
      slotCount > 0
          ? ((innerH - (n - 1) * tileGap) / n).clamp(24.0, _kScheduleTileExtent)
          : 24.0;
  return (vPad: vPad, tileH: tileH, tileGap: tileGap, innerH: innerH);
}

bool _shouldShowHoverInsertGap({
  required int dayIndex,
  required int insertPosition,
  required int slotCount,
  required _DragPayload? drag,
  required int? hoverDay,
  required int? hoverInsert,
}) {
  if (slotCount == 0) return false;
  if (hoverDay != dayIndex || hoverInsert == null) return false;
  if (hoverInsert != insertPosition) return false;
  if (drag?.dayIndex == dayIndex && drag?.slotIndex == insertPosition) {
    return false;
  }
  return true;
}

/// Unified week list — warm paper + soft chrome (timeline-inspired).
const Color _kWeekListOuterBorder = Color(0xFFD4CFC8);
const Color _kWeekListRowSeparator = Color(0xFFE8E4DE);
const Color _kWeekListPanelBg = Color(0xFFFBFAF8);
const Color _kTimelineLine = Color(0xFFC9C2BA);
const Color _kDayDotNumberFill = Color(0xFF3A3632);
const Color _kDayDotNumberBorder = Color(0xFFE8E4DE);
const Color _kWorkoutTileBorder = Color(0xFFE0DAD2);
const Color _kMetaText = Color(0xFF6B6560);

/// High-contrast left stripe (like the light reference’s white rail on dark cards).
const Color _kTileAccentBar = Color(0xFF2A2626);

DateTime _mondayOfWeekContaining(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final offset = day.weekday - DateTime.monday;
  return day.subtract(Duration(days: offset));
}

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

/// Share vertical space: REST / 1 workout = light, 2 = medium, 3 (max) = heavy.
int _weekRowWeight(int slotCount) {
  if (slotCount <= 0) return 1;
  return slotCount.clamp(1, 3);
}

/// Partitions [budget] (sum of row heights only, excluding separators) across 7 days.
List<double> _weightedWeekRowHeights({
  required double budget,
  required List<List<_ScheduledSlot>> schedule,
}) {
  const minRow = 30.0;
  final weights = List<int>.generate(
    7,
    (i) => _weekRowWeight(schedule[i].length),
  );
  final sumW = weights.fold<int>(0, (a, b) => a + b);
  final heights = List<double>.generate(7, (i) => budget * weights[i] / sumW);
  for (var round = 0; round < 16; round++) {
    final low = heights.indexWhere((h) => h < minRow - 0.5);
    if (low < 0) break;
    final need = minRow - heights[low];
    heights[low] = minRow;
    var high = -1;
    var hi = -1.0;
    for (var j = 0; j < 7; j++) {
      if (heights[j] > hi) {
        hi = heights[j];
        high = j;
      }
    }
    if (high < 0) break;
    final give = math.min(need, hi - minRow);
    if (give <= 0) break;
    heights[high] -= give;
  }
  final s = heights.fold<double>(0, (a, b) => a + b);
  if (s <= 0) return List<double>.filled(7, budget / 7);
  final scale = budget / s;
  return heights.map((h) => h * scale).toList();
}

double _weekRowTop(List<double> rowHeights, double separatorH, int index) {
  var y = 0.0;
  for (var j = 0; j < index; j++) {
    y += rowHeights[j] + separatorH;
  }
  return y;
}

/// Identifies a draggable workout slot on the week grid.
class _ScheduledSlot {
  _ScheduledSlot({required this.id, required this.templateId});

  final String id;
  final String templateId;

  _ScheduledSlot copy() => _ScheduledSlot(id: id, templateId: templateId);
}

/// Payload while dragging a workout chip between days.
class _DragPayload {
  _DragPayload({required this.dayIndex, required this.slotIndex});

  final int dayIndex;
  final int slotIndex;
}

/// Weekly + monthly training calendar.
class TrainingCalendarScreen extends StatefulWidget {
  const TrainingCalendarScreen({
    super.key,
    this.showBack = false,
    this.showProfileAction = true,
    this.onBack,
    this.onProfileTap,
  });

  final bool showBack;
  final bool showProfileAction;
  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;

  @override
  State<TrainingCalendarScreen> createState() => _TrainingCalendarScreenState();
}

enum _CalendarSurface { weekList, monthGrid }

/// Popped from [TrainingCalendarScreen] when user confirms Start or Edit from
/// [TodayWorkoutDetailScreen] so [HomeScreen] can open the workout flow.
class WorkoutFlowFromCalendar {
  const WorkoutFlowFromCalendar({
    required this.templateId,
    required this.startLive,
  });

  final String templateId;

  /// `true` = live workout, `false` = template editor.
  final bool startLive;
}

class _TrainingCalendarScreenState extends State<TrainingCalendarScreen>
    with SingleTickerProviderStateMixin {
  final List<WorkoutTemplate> _library = MockWorkoutTemplates.seed();
  late List<List<_ScheduledSlot>> _schedule;
  late List<List<_ScheduledSlot>> _scheduleBackup;
  late DateTime _weekStart;
  late DateTime _monthCursor;
  _CalendarSurface _surface = _CalendarSurface.weekList;
  bool _editing = false;
  DateTime? _selectedMonthDay;

  int _slotSeq = 0;
  late final AnimationController _jiggleController;

  /// Local calendar dates (midnight) that have at least one completed session.
  final Set<DateTime> _completedLocalDays = <DateTime>{};

  _DragPayload? _draggingPayload;
  int? _dragHoverDayIndex;
  int? _dragHoverInsertIndex;

  /// Drag avatar sits above the bar — use this + on-trash [onMove] for visible delete hints.
  bool _dragOverTrash = false;

  String _allocSlotId() => 's${_slotSeq++}';

  bool _hasCompletedWorkoutOn(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _completedLocalDays.contains(key);
  }

  Future<void> _loadCompletedHistory() async {
    final list = await loadStoredWorkoutHistory();
    if (!mounted) return;
    setState(() {
      _completedLocalDays
        ..clear()
        ..addAll({
          for (final e in list)
            DateTime(
              e.completedAt.year,
              e.completedAt.month,
              e.completedAt.day,
            ),
        });
    });
  }

  @override
  void initState() {
    super.initState();
    _jiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    final today = DateTime.now();
    _weekStart = _mondayOfWeekContaining(today);
    _monthCursor = DateTime(today.year, today.month);
    _schedule = _defaultWeekSchedule();
    _scheduleBackup = _cloneSchedule(_schedule);
    _selectedMonthDay = DateTime(today.year, today.month, today.day);
    _loadCompletedHistory();
    unawaited(_loadPersistedSchedule());
  }

  @override
  void dispose() {
    _jiggleController.dispose();
    super.dispose();
  }

  void _applyJiggle(bool active) {
    if (active) {
      _jiggleController.repeat(reverse: true);
    } else {
      _jiggleController.stop();
      _jiggleController.value = 0;
    }
  }

  List<List<_ScheduledSlot>> _defaultWeekSchedule() {
    return List<List<_ScheduledSlot>>.generate(
      7,
      (i) => kWeeklyDefaultTemplateIds[i]
          .map((id) => _ScheduledSlot(id: _allocSlotId(), templateId: id))
          .toList(growable: true),
      growable: true,
    );
  }

  List<List<_ScheduledSlot>> _cloneSchedule(List<List<_ScheduledSlot>> source) {
    return source
        .map((day) => day.map((s) => s.copy()).toList(growable: true))
        .toList(growable: true);
  }

  List<List<String>> _scheduleToTemplateIds(List<List<_ScheduledSlot>> s) =>
      s.map((d) => d.map((slot) => slot.templateId).toList()).toList();

  Future<void> _loadPersistedSchedule() async {
    try {
      final ids = await loadWeeklyTemplateSchedule();
      if (!mounted) return;
      setState(() {
        _slotSeq = 0;
        _schedule = List<List<_ScheduledSlot>>.generate(
          7,
          (i) => ids[i]
              .map((id) => _ScheduledSlot(id: _allocSlotId(), templateId: id))
              .toList(growable: true),
          growable: true,
        );
        _scheduleBackup = _cloneSchedule(_schedule);
      });
    } catch (_) {
      // Keep calendar usable if local schedule cannot be read.
    }
  }

  WorkoutTemplate? _lookupTemplate(String id) {
    for (final t in _library) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _openWorkoutDetailForSlot(
    WorkoutTemplate template,
    DateTime calendarDay,
  ) async {
    final history = await loadStoredWorkoutHistory();
    if (!mounted) return;
    final now = DateTime.now();
    final dayLocal = DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
    );
    final todayLocal = DateTime(now.year, now.month, now.day);
    final allowStart = dayLocal == todayLocal;

    WorkoutFlowFromCalendar? pending;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => TodayWorkoutDetailScreen(
              template: template,
              history: history,
              allowStart: allowStart,
              heroUnderHeader: false,
              onEdit: () {
                pending = WorkoutFlowFromCalendar(
                  templateId: template.id,
                  startLive: false,
                );
              },
              onStart: () {
                pending = WorkoutFlowFromCalendar(
                  templateId: template.id,
                  startLive: true,
                );
              },
            ),
      ),
    );
    if (!mounted) return;
    final result = pending;
    if (result != null) {
      Navigator.pop(context, result);
    }
  }

  void _enterEdit() {
    setState(() {
      _scheduleBackup = _cloneSchedule(_schedule);
      _editing = true;
    });
    _applyJiggle(true);
  }

  void _cancelEdit() {
    setState(() {
      _schedule = _cloneSchedule(_scheduleBackup);
      _editing = false;
    });
    _applyJiggle(false);
  }

  Future<void> _saveEdit() async {
    try {
      await saveWeeklyTemplateSchedule(_scheduleToTemplateIds(_schedule));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: kLiftSnackBarDuration,
          content: const Text('Could not save schedule'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _scheduleBackup = _cloneSchedule(_schedule);
      _editing = false;
    });
    _applyJiggle(false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: kLiftSnackBarDuration,
        content: const Text('Schedule updated'),
      ),
    );
  }

  void _moveSlotToDay(
    _DragPayload payload,
    int targetDayIndex,
    int insertIndex,
  ) {
    setState(() {
      final p = payload.slotIndex;
      final from = payload.dayIndex;
      final slot = _schedule[from].removeAt(p);
      final list = _schedule[targetDayIndex];
      var j = insertIndex;
      if (from == targetDayIndex && insertIndex > p) {
        j -= 1;
      }
      j = j.clamp(0, list.length);
      list.insert(j, slot);
    });
  }

  void _onScheduleDragStarted(_DragPayload payload) {
    setState(() {
      _draggingPayload = payload;
      _dragHoverDayIndex = null;
      _dragHoverInsertIndex = null;
      _dragOverTrash = false;
    });
  }

  void _onScheduleDragEnded() {
    setState(() {
      _draggingPayload = null;
      _dragHoverDayIndex = null;
      _dragHoverInsertIndex = null;
      _dragOverTrash = false;
    });
  }

  void _setTrashHover(bool value) {
    if (_dragOverTrash == value) return;
    setState(() => _dragOverTrash = value);
  }

  void _onScheduleDragHover(int dayIndex, int insertIndex) {
    setState(() {
      _dragHoverDayIndex = dayIndex;
      _dragHoverInsertIndex = insertIndex;
    });
  }

  void _onScheduleDragLeaveDay(int dayIndex) {
    if (_dragHoverDayIndex == dayIndex) {
      setState(() {
        _dragHoverDayIndex = null;
        _dragHoverInsertIndex = null;
      });
    }
  }

  void _onScheduleDrop(_DragPayload payload, int targetDayIndex) {
    final insert =
        (_dragHoverDayIndex == targetDayIndex && _dragHoverInsertIndex != null)
            ? _dragHoverInsertIndex!
            : _schedule[targetDayIndex].length;
    _moveSlotToDay(payload, targetDayIndex, insert);
  }

  void _prevWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
  }

  void _prevMonth() {
    setState(() {
      _monthCursor = DateTime(_monthCursor.year, _monthCursor.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + 1);
    });
  }

  String _weekRangeLabel() {
    final start = _weekStart;
    final end = _weekStart.add(const Duration(days: 6));
    final a = '${start.day} ${_monthShort[start.month - 1]}';
    final b = '${end.day} ${_monthShort[end.month - 1]}';
    return '$a - $b';
  }

  List<WorkoutTemplate> _templatesForCalendarDay(DateTime day) {
    final monday = _mondayOfWeekContaining(day);
    final index = day.difference(monday).inDays;
    if (index < 0 || index > 6) return [];
    final slots = _schedule[index];
    if (slots.isEmpty) return [];
    return slots
        .map((s) => _lookupTemplate(s.templateId))
        .whereType<WorkoutTemplate>()
        .toList();
  }

  void _dismissStandaloneCalendar() {
    if (_editing) {
      _cancelEdit();
    }
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _onSecondaryIslandTap() {
    if (_editing) {
      _showAddWorkoutToWeekSheet();
    } else {
      _dismissStandaloneCalendar();
    }
  }

  Future<void> _showAddWorkoutToWeekSheet() async {
    final templateId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (sheetContext) {
        return _AddWorkoutPickerSheet(
          templates: _library,
          onSelect: (id) => Navigator.pop(sheetContext, id),
          onDismiss: () => Navigator.pop(sheetContext),
        );
      },
    );
    if (templateId == null || !mounted) return;

    final dayIndex = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Assign to day'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(7, (i) {
                final d = _weekStart.add(Duration(days: i));
                final label =
                    '${_kWeekdayShort[i]} · ${d.day} ${_monthShort[d.month - 1]}';
                return ListTile(
                  title: Text(label),
                  onTap: () => Navigator.pop(dialogContext, i),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (dayIndex == null || !mounted) return;
    setState(() {
      _schedule[dayIndex].add(
        _ScheduledSlot(id: _allocSlotId(), templateId: templateId),
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  /// Same quick actions as [HomeScreen] shell / recovery header (QR menu).
  Future<void> _showQuickActions() async {
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
                  Navigator.of(context).push<void>(
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

  void _onPrimaryIslandAction() {
    if (_editing) {
      unawaited(_saveEdit());
    } else {
      _enterEdit();
    }
  }

  String get _islandPrimaryLabel => _editing ? 'Save' : 'Edit';

  double get _islandPrimaryWidth {
    if (_islandCompactEditChrome) return 48;
    if (_editing) return 148;
    return 52;
  }

  /// Mynaui edit icon instead of the "Edit" label on the primary island pill.
  Widget? get _islandPrimaryChildWidget {
    if (_islandCompactEditChrome) return null;
    final label = _islandPrimaryLabel;
    final white = Colors.white.withValues(alpha: 0.96);
    if (label == 'Edit') {
      return MynauiIcon(MynauiGlyphs.editOne, size: 22, color: white);
    }
    return null;
  }

  /// Month grid: no edit affordance — user switches via the header week toggle.
  Widget _monthViewIslandHint() {
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          'Return to the week view to make changes.',
          textAlign: TextAlign.center,
          maxLines: 4,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black.withValues(alpha: 0.55),
            height: 1.3,
          ),
        ),
      ),
    );
  }

  /// Week list in edit mode: trash + check icon strip instead of wide "Save" label.
  bool get _islandCompactEditChrome =>
      _editing && _surface == _CalendarSurface.weekList;

  void _onDeleteWorkoutFromIsland() {
    if (!_editing) return;
    final entries = <({int dayIndex, int slotIndex, String title})>[];
    for (var d = 0; d < 7; d++) {
      final daySlots = _schedule[d];
      for (var s = 0; s < daySlots.length; s++) {
        final t = _lookupTemplate(daySlots[s].templateId);
        final title = t?.name ?? daySlots[s].templateId;
        entries.add((dayIndex: d, slotIndex: s, title: title));
      }
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: kLiftSnackBarDuration,
          content: const Text('No workouts to remove this week'),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Remove workout',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: MynauiIcon(
                              MynauiGlyphs.closeCircle,
                              size: 22,
                              color: Colors.grey.shade600,
                            ),
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: entries.length,
                        separatorBuilder:
                            (_, __) => Divider(
                              height: 1,
                              color: Theme.of(context).dividerTheme.color,
                            ),
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final date = _weekStart.add(
                            Duration(days: e.dayIndex),
                          );
                          final dayLabel =
                              '${_kWeekdayShort[e.dayIndex]} ${date.day} ${_monthShort[date.month - 1]}';
                          return ListTile(
                            title: Text(
                              e.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            trailing: IconButton(
                              icon: MynauiIcon(
                                MynauiGlyphs.trashBin,
                                size: 24,
                                color: Colors.grey.shade700,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _schedule[e.dayIndex].removeAt(e.slotIndex);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _removeWorkoutSlot(_DragPayload payload) {
    setState(() {
      _schedule[payload.dayIndex].removeAt(payload.slotIndex);
    });
  }

  /// Red trash + [DragTarget]: scales and highlights while a workout hovers over it.
  Widget _buildTrashIslandTarget() {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (_) => _editing,
      onMove: (_) => _setTrashHover(true),
      onLeave: (_) => _setTrashHover(false),
      onAcceptWithDetails: (details) {
        _removeWorkoutSlot(details.data);
        _onScheduleDragEnded();
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return LiftPressable(
          onTap: _onDeleteWorkoutFromIsland,
          borderRadius: kIosControlRadius,
          pressedScale: LiftMotion.gentlePressScale,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Center(
              child: AnimatedScale(
                scale: hot ? 1.22 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hot ? const Color(0xFFFFEBEE) : Colors.transparent,
                    boxShadow:
                        hot
                            ? [
                              BoxShadow(
                                color: const Color(
                                  0xFFE53935,
                                ).withValues(alpha: 0.38),
                                blurRadius: 10,
                                spreadRadius: 0,
                              ),
                            ]
                            : null,
                  ),
                  child: MynauiIcon(
                    MynauiGlyphs.trashBin,
                    size: 22,
                    color:
                        hot ? const Color(0xFFB71C1C) : const Color(0xFFE53935),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    /// Clears the floating [WorkoutDetailActionIsland]: `bottom` offset + its height +
    /// a thin gap. Do **not** add [MediaQuery.padding.bottom] here — the bar already
    /// sits above the home indicator (`Positioned(bottom: kShellFloatingNavBottomInset)`),
    /// and padding.bottom would duplicate safe-area space and leave a large empty band.
    const gapAboveIsland = 10.0;
    final isMonthGrid = _surface == _CalendarSurface.monthGrid;
    final islandBarHeight =
        isMonthGrid ? _kMonthGridIslandHintBarHeight : kLiftIslandHeaderHeight;
    final islandBottomReserve =
        kShellFloatingNavBottomInset + islandBarHeight + gapAboveIsland;

    return Scaffold(
      /// Match [HomeScreen] shell scaffold (`Colors.white`).
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  /// Shell header on home uses `topInset + 16` from the screen top;
                  /// inside [SafeArea] that reads as 16 below the status bar.
                  padding: const EdgeInsets.fromLTRB(
                    kPagePadding,
                    16,
                    kPagePadding,
                    0,
                  ),
                  child: LiftIslandHeader(
                    collapseOnScroll: false,
                    leading: LiftIslandHeaderAction(
                      onTap:
                          widget.showBack
                              ? (widget.onBack ??
                                  () => Navigator.of(context).pop())
                              : _showQuickActions,
                      child: MynauiIcon(
                        widget.showBack
                            ? MynauiGlyphs.altArrowLeft
                            : MynauiGlyphs.qrCode,
                        size:
                            widget.showBack
                                ? 22
                                : kLiftIslandHeaderLeadingIconSize,
                        color: kLiftIslandOnFrosted,
                      ),
                    ),
                    trailing:
                        widget.showProfileAction
                            ? LiftIslandHeaderAction(
                              onTap: widget.onProfileTap ?? _openSettings,
                              child: const MynauiIcon(
                                MynauiGlyphs.userNoCircle,
                                size: kLiftIslandHeaderTrailingIconSize,
                                color: kLiftIslandOnFrosted,
                              ),
                            )
                            : null,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: islandBottomReserve),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kPagePadding,
                      ),
                      child:
                          _surface == _CalendarSurface.weekList
                              ? _buildWeekListView()
                              : _buildMonthGridView(),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: kShellFloatingNavBottomInset,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child:
                          _islandCompactEditChrome && _dragOverTrash
                              ? Padding(
                                key: const ValueKey('trash_hint'),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: Material(
                                    color: const Color(0xFFE53935),
                                    borderRadius: BorderRadius.circular(20),
                                    elevation: 3,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          MynauiIcon(
                                            MynauiGlyphs.trashBin,
                                            size: 18,
                                            color: Colors.white.withValues(
                                              alpha: 0.95,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Release to delete',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.96,
                                              ),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              : const SizedBox.shrink(
                                key: ValueKey('no_trash_hint'),
                              ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color:
                              _islandCompactEditChrome && _dragOverTrash
                                  ? const Color(0xFFE53935)
                                  : Colors.transparent,
                          width:
                              _islandCompactEditChrome && _dragOverTrash
                                  ? 2.5
                                  : 0,
                        ),
                        boxShadow:
                            _islandCompactEditChrome && _dragOverTrash
                                ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFE53935,
                                    ).withValues(alpha: 0.42),
                                    blurRadius: 20,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                                : null,
                      ),
                      child: WorkoutDetailActionIsland(
                        height:
                            isMonthGrid ? _kMonthGridIslandHintBarHeight : null,
                        showSecondary: _editing || !widget.showBack,
                        onSecondaryTap: _onSecondaryIslandTap,
                        onPrimaryTap:
                            isMonthGrid ? () {} : _onPrimaryIslandAction,
                        primaryReplacement:
                            isMonthGrid ? _monthViewIslandHint() : null,
                        primaryLabel:
                            _islandCompactEditChrome
                                ? null
                                : (isMonthGrid
                                    ? null
                                    : (_islandPrimaryChildWidget == null
                                        ? _islandPrimaryLabel
                                        : null)),
                        primaryIcon: null,
                        primaryChild:
                            _islandCompactEditChrome
                                ? MynauiIcon(
                                  MynauiGlyphs.checkCircle,
                                  size: 22,
                                  color: Colors.white.withValues(alpha: 0.96),
                                )
                                : (isMonthGrid
                                    ? null
                                    : _islandPrimaryChildWidget),
                        primaryWidth:
                            _islandCompactEditChrome ? 48 : _islandPrimaryWidth,
                        middle:
                            _islandCompactEditChrome
                                ? _buildTrashIslandTarget()
                                : null,
                        secondaryIcon: Icons.insights_rounded,
                        secondaryChild:
                            _editing
                                ? MynauiIcon(
                                  MynauiGlyphs.addCircle,
                                  size: 23,
                                  color: Colors.black.withValues(alpha: 0.74),
                                )
                                : MynauiIcon(
                                  widget.showBack
                                      ? MynauiGlyphs.altArrowLeft
                                      : MynauiGlyphs.home,
                                  size: 23,
                                  color: Colors.black.withValues(alpha: 0.74),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekNavBar(
          label: _weekRangeLabel(),
          onPrev: _editing ? null : _prevWeek,
          onNext: _editing ? null : _nextWeek,
          trailing: MynauiIcon(
            MynauiGlyphs.calendarMark,
            size: 22,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onTrailing:
              _editing
                  ? null
                  : () => setState(() {
                    _surface = _CalendarSurface.monthGrid;
                    _monthCursor = DateTime(_weekStart.year, _weekStart.month);
                  }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final usableH = constraints.maxHeight;
              const separatorH = 1.0;
              final budget =
                  usableH > 0
                      ? (usableH - 6 * separatorH).clamp(0.0, double.infinity)
                      : 0.0;
              final rowHeights =
                  budget > 0
                      ? _weightedWeekRowHeights(
                        budget: budget,
                        schedule: _schedule,
                      )
                      : List<double>.filled(7, 48.0);
              final stackH =
                  rowHeights.fold<double>(0, (a, h) => a + h) + 6 * separatorH;
              final lineTop = rowHeights[0] / 2;
              final lineBottom =
                  _weekRowTop(rowHeights, separatorH, 6) + rowHeights[6] / 2;
              final lineHeight = (lineBottom - lineTop).clamp(
                0.0,
                double.infinity,
              );
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: _kWeekListPanelBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _kWeekListOuterBorder.withValues(alpha: 0.85),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: stackH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 52,
                          top: lineTop,
                          width: 2,
                          height: lineHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _kTimelineLine.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                        for (int i = 0; i < 7; i++)
                          Positioned(
                            left: 49,
                            top:
                                _weekRowTop(rowHeights, separatorH, i) +
                                rowHeights[i] / 2 -
                                4,
                            width: 8,
                            height: 8,
                            child: Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _kWeekListPanelBg,
                                  border: Border.all(
                                    color: _kTimelineLine.withValues(
                                      alpha: 0.95,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Column(
                          children: [
                            for (int index = 0; index < 7; index++) ...[
                              if (index > 0)
                                Container(
                                  height: separatorH,
                                  width: double.infinity,
                                  color: _kWeekListRowSeparator,
                                ),
                              SizedBox(
                                height: rowHeights[index],
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 52,
                                      child: _DayTimelineDot(
                                        date: _weekStart.add(
                                          Duration(days: index),
                                        ),
                                        rowHeight: rowHeights[index],
                                        hasCompletedWorkout:
                                            _hasCompletedWorkoutOn(
                                              _weekStart.add(
                                                Duration(days: index),
                                              ),
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _DayScheduleRow(
                                        dayIndex: index,
                                        slots: _schedule[index],
                                        rowHeight: rowHeights[index],
                                        editing: _editing,
                                        jiggleAnimation: _jiggleController,
                                        lookupTemplate: _lookupTemplate,
                                        draggingPayload: _draggingPayload,
                                        hoverDayIndex: _dragHoverDayIndex,
                                        hoverInsertIndex: _dragHoverInsertIndex,
                                        onDragStarted: _onScheduleDragStarted,
                                        onDragEnded: _onScheduleDragEnded,
                                        onDragHover: _onScheduleDragHover,
                                        onDragLeaveDay: _onScheduleDragLeaveDay,
                                        onDrop: _onScheduleDrop,
                                        onWorkoutTap:
                                            _editing
                                                ? null
                                                : (template) =>
                                                    _openWorkoutDetailForSlot(
                                                      template,
                                                      _weekStart.add(
                                                        Duration(days: index),
                                                      ),
                                                    ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildMonthGridView() {
    final y = _monthCursor.year;
    final m = _monthCursor.month;
    final dim = _daysInMonth(y, m);
    final firstWeekday = DateTime(y, m, 1).weekday;
    final leading = firstWeekday - DateTime.monday;
    final cells = leading + dim;
    final rows = (cells / 7).ceil();
    final monthTopInset = rows <= 5 ? 22.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: monthTopInset),
        _WeekNavBar(
          label: _monthLong[m - 1].toUpperCase(),
          onPrev: _prevMonth,
          onNext: _nextMonth,
          trailing: const MynauiIcon(MynauiGlyphs.viewAgenda, size: 24),
          onTrailing:
              () => setState(() => _surface = _CalendarSurface.weekList),
        ),
        const SizedBox(height: 14),
        Row(
          children:
              _kWeekdayLetters
                  .map(
                    (l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: rows * 7,
            itemBuilder: (context, i) {
              final dayNumber = i - leading + 1;
              if (i < leading || dayNumber < 1 || dayNumber > dim) {
                return const SizedBox.shrink();
              }
              final date = DateTime(y, m, dayNumber);
              final sel =
                  _selectedMonthDay != null &&
                  _selectedMonthDay!.year == date.year &&
                  _selectedMonthDay!.month == date.month &&
                  _selectedMonthDay!.day == date.day;
              final hasCompleted = _hasCompletedWorkoutOn(date);
              return GestureDetector(
                onTap: () => setState(() => _selectedMonthDay = date),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kIosCornerRadius),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kIosCornerRadius),
                      border: Border.all(
                        color:
                            sel
                                ? kAccentColor
                                : (hasCompleted
                                    ? const Color(0xFF66BB6A)
                                    : Colors.black.withValues(alpha: 0.08)),
                        width: sel ? 2 : (hasCompleted ? 1.5 : 1),
                      ),
                      color:
                          sel
                              ? kAccentColor.withValues(alpha: 0.06)
                              : (hasCompleted
                                  ? const Color(0xFFE8F5E9)
                                  : Colors.white),
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: sel ? kAccentColor : const Color(0xFF171717),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        _SelectedDayPreview(
          date: _selectedMonthDay,
          templates:
              _selectedMonthDay == null
                  ? null
                  : _templatesForCalendarDay(_selectedMonthDay!),
          showCompletedTick:
              _selectedMonthDay != null &&
              _hasCompletedWorkoutOn(_selectedMonthDay!),
        ),
      ],
    );
  }
}

class _WeekNavBar extends StatelessWidget {
  const _WeekNavBar({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.trailing,
    required this.onTrailing,
  });

  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Widget trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // App [iconButtonTheme] adds a filled “pill” behind every icon; use a flat style here.
    final navIconStyle = IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      foregroundColor: onSurface,
      disabledForegroundColor: onSurface.withValues(alpha: 0.38),
      side: BorderSide.none,
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      overlayColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    );

    return Row(
      children: [
        IconButton(
          style: navIconStyle,
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        IconButton(
          style: navIconStyle,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded, size: 28),
        ),
        IconButton(style: navIconStyle, onPressed: onTrailing, icon: trailing),
      ],
    );
  }
}

/// Weekday label above a circled calendar date (timeline marker).
class _DayTimelineDot extends StatelessWidget {
  const _DayTimelineDot({
    required this.date,
    required this.rowHeight,
    this.hasCompletedWorkout = false,
  });

  final DateTime date;
  final double rowHeight;
  final bool hasCompletedWorkout;

  @override
  Widget build(BuildContext context) {
    final label = _kWeekdayShort[date.weekday - 1];
    final dayNum = '${date.day}';
    final diameter = (rowHeight * 0.34).clamp(22.0, 34.0);
    final labelSize = (rowHeight * 0.13).clamp(8.5, 11.0);
    final gap = (rowHeight * 0.035).clamp(2.0, 5.0);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
                color: _kMetaText,
              ),
            ),
            SizedBox(height: gap),
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kDayDotNumberFill,
                border: Border.all(
                  color:
                      hasCompletedWorkout
                          ? const Color(0xFF66BB6A)
                          : _kDayDotNumberBorder,
                  width: hasCompletedWorkout ? 2 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                dayNum,
                style: TextStyle(
                  fontSize: (diameter * 0.38).clamp(10.0, 14.0),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: const Color(0xFFF7F4F0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Workout column for one day (timeline dot + rail live in the parent [Row]).
class _DayScheduleRow extends StatefulWidget {
  const _DayScheduleRow({
    required this.dayIndex,
    required this.slots,
    required this.rowHeight,
    required this.editing,
    required this.jiggleAnimation,
    required this.lookupTemplate,
    required this.draggingPayload,
    required this.hoverDayIndex,
    required this.hoverInsertIndex,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDragHover,
    required this.onDragLeaveDay,
    required this.onDrop,
    this.onWorkoutTap,
  });

  final int dayIndex;
  final List<_ScheduledSlot> slots;
  final double rowHeight;
  final bool editing;
  final Animation<double> jiggleAnimation;
  final WorkoutTemplate? Function(String templateId) lookupTemplate;
  final _DragPayload? draggingPayload;
  final int? hoverDayIndex;
  final int? hoverInsertIndex;
  final void Function(_DragPayload payload) onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(int dayIndex, int insertIndex) onDragHover;
  final void Function(int dayIndex) onDragLeaveDay;
  final void Function(_DragPayload payload, int targetDayIndex) onDrop;

  /// View mode: opens workout detail (edit / start depends on calendar day vs today).
  final void Function(WorkoutTemplate template)? onWorkoutTap;

  @override
  State<_DayScheduleRow> createState() => _DayScheduleRowState();
}

class _DayScheduleRowState extends State<_DayScheduleRow> {
  final GlobalKey _columnKey = GlobalKey();

  bool _shouldShowHoverInsertGapAt(int insertPosition) {
    return _shouldShowHoverInsertGap(
      dayIndex: widget.dayIndex,
      insertPosition: insertPosition,
      slotCount: widget.slots.length,
      drag: widget.draggingPayload,
      hoverDay: widget.hoverDayIndex,
      hoverInsert: widget.hoverInsertIndex,
    );
  }

  /// True when a hover "drop slot" is shown — it adds a full tile height, so
  /// [tileH] must be recomputed for `slotCount + 1` rows or the column overflows.
  bool _anyHoverInsertGap() {
    final slotCount = widget.slots.length;
    if (slotCount == 0) return false;
    for (var i = 0; i <= slotCount; i++) {
      if (_shouldShowHoverInsertGapAt(i)) return true;
    }
    return false;
  }

  /// Layout row count for splitting [innerH] across tiles + optional hover gap.
  int _layoutRowCount() {
    final slotCount = widget.slots.length;
    if (slotCount == 0) return 1;
    return slotCount + (_anyHoverInsertGap() ? 1 : 0);
  }

  int _slotInsertIndexFromLocalY(double localY) {
    final slotCount = widget.slots.length;
    if (slotCount == 0) return 0;

    final layoutRows = _layoutRowCount();
    final m = _metricsForDayRow(widget.rowHeight, layoutRows);
    final th = m.tileH;
    final tg = m.tileGap;
    final drag = widget.draggingPayload;
    final day = widget.dayIndex;

    var y = 0.0;
    for (var i = 0; i <= slotCount; i++) {
      if (_shouldShowHoverInsertGapAt(i)) {
        if (localY < y + th / 2) return i;
        y += th;
        if (i < slotCount) y += tg;
      }
      if (i < slotCount) {
        final h = (drag?.dayIndex == day && drag?.slotIndex == i) ? 0.0 : th;
        if (localY < y + h / 2) return i;
        y += h;
        final gapAfterSlot =
            i < slotCount - 1 || _shouldShowHoverInsertGapAt(slotCount);
        if (gapAfterSlot) y += tg;
      }
    }
    return slotCount;
  }

  void _handleDragMove(DragTargetDetails<_DragPayload> details) {
    final box = _columnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final dy = local.dy.clamp(0.0, box.size.height);

    final n = widget.slots.length;
    if (n == 0) {
      widget.onDragHover(widget.dayIndex, 0);
      return;
    }

    widget.onDragHover(widget.dayIndex, _slotInsertIndexFromLocalY(dy));
  }

  Widget _hoverInsertGap(double tileH) {
    return Container(
      height: tileH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: kAccentColor.withValues(alpha: 0.38),
          width: 1.2,
        ),
        color: kAccentColor.withValues(alpha: 0.07),
      ),
    );
  }

  Widget _buildSlotTile({
    required int slotIndex,
    required double tileH,
    required double tileGap,
    required bool isLast,
  }) {
    final slot = widget.slots[slotIndex];
    final template = widget.lookupTemplate(slot.templateId);
    final title = template?.name.toUpperCase() ?? slot.templateId.toUpperCase();
    final minutes =
        template?.estimatedDurationMinutes ?? template?.durationMinutes ?? 0;
    final exCount = template?.exercises.length ?? 0;
    final subtitle =
        template == null ? '' : '$minutes min · $exCount exercises';

    final tile = _ScheduleWorkoutTile(
      tileHeight: tileH,
      title: title,
      subtitle: subtitle,
      imageUrl: template?.imageUrl,
      editing: widget.editing,
      dashed: widget.editing,
      isPlaceholder: false,
      onTap:
          widget.editing || template == null
              ? null
              : () => widget.onWorkoutTap?.call(template),
    );

    Widget content =
        widget.editing
            ? AnimatedBuilder(
              animation: widget.jiggleAnimation,
              builder: (context, child) {
                final wave = 0.004 + (widget.jiggleAnimation.value * 0.008);
                final angle = slotIndex.isEven ? wave : -wave;
                return Transform.rotate(
                  angle: angle,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: tile,
            )
            : tile;

    if (widget.editing) {
      final payload = _DragPayload(
        dayIndex: widget.dayIndex,
        slotIndex: slotIndex,
      );
      content = LongPressDraggable<_DragPayload>(
        data: payload,
        delay: const Duration(milliseconds: 120),
        onDragStarted: () => widget.onDragStarted(payload),
        onDragEnd: (_) => widget.onDragEnded(),
        onDraggableCanceled: (_, __) => widget.onDragEnded(),
        feedback: Material(
          color: Colors.transparent,
          elevation: 10,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 280,
            child: _ScheduleWorkoutTile(
              tileHeight: tileH,
              title: title,
              subtitle: subtitle,
              imageUrl: template?.imageUrl,
              editing: false,
              dashed: false,
              isPlaceholder: false,
              onTap: null,
            ),
          ),
        ),
        childWhenDragging: const SizedBox.shrink(),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : tileGap),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vPad = (widget.rowHeight * 0.08).clamp(4.0, 10.0);
    final hPad = (widget.rowHeight * 0.08).clamp(8.0, 14.0);
    final innerH = (widget.rowHeight -
            2 * vPad -
            _kDayRowDragChromePadV -
            _kDayRowOverflowGuardV)
        .clamp(0.0, double.infinity);
    final layoutRows = _layoutRowCount();
    final n = layoutRows;
    final tileGap = n > 1 ? (innerH * 0.06).clamp(2.0, 8.0) : 0.0;
    final tileH =
        n > 0
            ? ((innerH - (n - 1) * tileGap) / n).clamp(
              24.0,
              _kScheduleTileExtent,
            )
            : 24.0;

    return Padding(
      padding: EdgeInsets.only(right: hPad, top: vPad, bottom: vPad),
      child: DragTarget<_DragPayload>(
        onWillAcceptWithDetails: (details) => widget.editing,
        onMove: widget.editing ? _handleDragMove : null,
        onLeave:
            widget.editing
                ? (_) => widget.onDragLeaveDay(widget.dayIndex)
                : null,
        onAcceptWithDetails: (details) {
          widget.onDrop(details.data, widget.dayIndex);
        },
        builder: (context, candidate, rejected) {
          final highlight = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color:
                  highlight
                      ? kAccentColor.withValues(alpha: 0.08)
                      : Colors.transparent,
            ),
            child:
                widget.slots.isEmpty
                    ? _ScheduleWorkoutTile(
                      tileHeight: tileH,
                      title: widget.editing ? 'Drop workouts here' : 'REST',
                      subtitle: '',
                      imageUrl: null,
                      editing: widget.editing,
                      dashed: widget.editing,
                      isPlaceholder: true,
                    )
                    : AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        key: _columnKey,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: () {
                          final out = <Widget>[];
                          final slotCount = widget.slots.length;
                          final gapAfterLastSlot = _shouldShowHoverInsertGapAt(
                            slotCount,
                          );
                          for (var i = 0; i <= slotCount; i++) {
                            if (_shouldShowHoverInsertGapAt(i)) {
                              out.add(
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: i < slotCount ? tileGap : 0,
                                  ),
                                  child: _hoverInsertGap(tileH),
                                ),
                              );
                            }
                            if (i < slotCount) {
                              out.add(
                                _buildSlotTile(
                                  slotIndex: i,
                                  tileH: tileH,
                                  tileGap: tileGap,
                                  isLast:
                                      i == slotCount - 1 && !gapAfterLastSlot,
                                ),
                              );
                            }
                          }
                          return out;
                        }(),
                      ),
                    ),
          );
        },
      ),
    );
  }
}

class _ScheduleWorkoutTile extends StatelessWidget {
  const _ScheduleWorkoutTile({
    required this.tileHeight,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.editing,
    required this.dashed,
    required this.isPlaceholder,
    this.onTap,
  });

  final double tileHeight;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool editing;
  final bool dashed;
  final bool isPlaceholder;
  final VoidCallback? onTap;

  bool get _hasImage =>
      !isPlaceholder && imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    const dashedInset = 1.5;
    final innerBudget = dashed ? (tileHeight - 2 * dashedInset) : tileHeight;

    final titleSize = (innerBudget * 0.19).clamp(8.5, 12.0);
    final subSize = (innerBudget * 0.16).clamp(7.5, 11.0);
    final hInset = (innerBudget * 0.14).clamp(6.0, 12.0);
    final vInset = (innerBudget * 0.1).clamp(3.0, 8.0);
    // Inline row (title + meta) is tight on short week rows; shave padding so text fits.
    final vPad = subtitle.isEmpty ? vInset : (vInset - 2).clamp(1.0, 8.0);
    final corner = (innerBudget * 0.12).clamp(4.0, 8.0);

    final showAccentBar = !isPlaceholder;
    final onPhoto = _hasImage;

    final titleStyle = TextStyle(
      fontSize: titleSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      height: 1.1,
      color: onPhoto ? Colors.white : const Color(0xFF2C2925),
      shadows:
          onPhoto
              ? const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 4,
                  color: Color(0x99000000),
                ),
              ]
              : null,
    );
    final subStyle = TextStyle(
      fontSize: subSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.1,
      color: onPhoto ? Colors.white.withValues(alpha: 0.9) : _kMetaText,
      shadows:
          onPhoto
              ? const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Color(0x88000000),
                ),
              ]
              : null,
    );
    final inlineGap = (innerBudget * 0.06).clamp(4.0, 10.0);

    final maxContentH = (innerBudget - 2 * vPad).clamp(0.0, double.infinity);

    final textBlock =
        subtitle.isEmpty
            ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            )
            : SizedBox(
              height: maxContentH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle.copyWith(height: 1.05),
                    ),
                  ),
                  SizedBox(width: inlineGap),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: subStyle.copyWith(height: 1.05),
                  ),
                ],
              ),
            );

    final paddedBody = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showAccentBar)
          SizedBox(
            width: 3,
            child: ColoredBox(
              color:
                  onPhoto
                      ? Colors.white.withValues(alpha: 0.9)
                      : _kTileAccentBar,
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hInset, vertical: vPad),
            child: textBlock,
          ),
        ),
      ],
    );

    final radius = BorderRadius.circular(corner);

    Widget clipChild({required double height}) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isPlaceholder || !onPhoto)
                const ColoredBox(color: Colors.white)
              else
                WorkoutTemplateHeroImage(
                  imageUrl: imageUrl!.trim(),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.12),
                  filterQuality: FilterQuality.medium,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const ColoredBox(color: Colors.white);
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(color: Colors.white);
                  },
                ),
              if (onPhoto)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Strong scrim so white label text stays readable on busy photos.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.38),
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                ),
              Align(alignment: Alignment.centerLeft, child: paddedBody),
            ],
          ),
        ),
      );
    }

    final framed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: _kWorkoutTileBorder),
      ),
      child: clipChild(height: innerBudget),
    );

    if (dashed) {
      return SizedBox(
        height: tileHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: const Color(0xFF9CA3AF).withValues(alpha: 0.65),
            strokeWidth: 1.0,
            borderRadius: corner,
          ),
          child: Padding(
            padding: const EdgeInsets.all(dashedInset),
            child: framed,
          ),
        ),
      );
    }

    Widget interactive = SizedBox(
      height: tileHeight,
      width: double.infinity,
      child: framed,
    );
    if (onTap != null) {
      interactive = LiftPressable(
        onTap: onTap,
        borderRadius: corner,
        child: interactive,
      );
    }
    return interactive;
  }
}

/// Dashed stroked rounded rect (edit mode), drawn to match tile corners.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
  });

  final Color color;
  final double strokeWidth;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    final path = Path()..addRRect(rrect);
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}

/// Month preview hero — slightly taller to use vertical space under the grid.
const double _kSelectedDayPreviewHeight = 204.0;

/// Inset so the completion tick stays inside [kIosCornerRadius] and below wallet peek strips.
const double _kSelectedDayCompletedTickInset = 14.0;

class _SelectedDayPreview extends StatelessWidget {
  const _SelectedDayPreview({
    required this.date,
    required this.templates,
    this.showCompletedTick = false,
  });

  final DateTime? date;

  /// When [date] is set, workouts scheduled that day (empty list = REST).
  final List<WorkoutTemplate>? templates;
  final bool showCompletedTick;

  @override
  Widget build(BuildContext context) {
    final selectedDate = date;
    if (selectedDate == null || templates == null) {
      return SizedBox(
        height: _kSelectedDayPreviewHeight,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(kIosCornerRadius),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Center(
            child: Text(
              'Select a day',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      );
    }

    final dayLabel =
        '${selectedDate.day} ${_monthShort[selectedDate.month - 1]}';
    final scheduled = templates!;
    final completedTickTop =
        stackedWorkoutFrontCardTopInset(
          maxHeight: _kSelectedDayPreviewHeight,
          templateCount: scheduled.length,
        ) +
        _kSelectedDayCompletedTickInset;

    if (scheduled.isEmpty) {
      return _SelectedDayRestCard(
        dayLabel: dayLabel,
        showCompletedTick: showCompletedTick,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(kIosCornerRadius),
      child: SizedBox(
        height: _kSelectedDayPreviewHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: StackedWorkoutHero(
                key: ValueKey(
                  '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                ),
                templates: scheduled,
                borderRadius: kIosCornerRadius,
                interactive: false,
                onTap: () {},
                overlayBuilder:
                    (context, heroTemplate, _) => Container(
                      padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0),
                            Colors.black.withValues(alpha: 0.28),
                            Colors.black.withValues(alpha: 0.48),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dayLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            heroTemplate.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _MonthPreviewStatChip(
                                icon: Icons.schedule_rounded,
                                label:
                                    '${heroTemplate.estimatedDurationMinutes} min',
                              ),
                              const SizedBox(width: 8),
                              _MonthPreviewStatChip(
                                icon: Icons.list_alt_rounded,
                                label:
                                    '${heroTemplate.exercises.length} exercises',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ),
            ),
            if (showCompletedTick)
              Positioned(
                right: _kSelectedDayCompletedTickInset,
                top: completedTickTop,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: MynauiIcon(
                    MynauiGlyphs.checkUnread,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            Positioned(
              right: _kSelectedDayCompletedTickInset,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SELECTED DAY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.85,
                    color: Colors.white.withValues(alpha: 0.95),
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

class _SelectedDayRestCard extends StatelessWidget {
  const _SelectedDayRestCard({
    required this.dayLabel,
    required this.showCompletedTick,
  });

  final String dayLabel;
  final bool showCompletedTick;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kIosCornerRadius),
      child: SizedBox(
        height: _kSelectedDayPreviewHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kAccentDark, kAccentMid, kAccentLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (showCompletedTick)
              Positioned(
                right: _kSelectedDayCompletedTickInset,
                top: _kSelectedDayCompletedTickInset,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: MynauiIcon(
                    MynauiGlyphs.checkUnread,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.28),
                      Colors.black.withValues(alpha: 0.48),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'REST',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: _kSelectedDayCompletedTickInset,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SELECTED DAY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.85,
                    color: Colors.white.withValues(alpha: 0.95),
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

/// Mirrors [_WorkoutStatChip] on [HomeScreen] (dark chips on photo).
class _MonthPreviewStatChip extends StatelessWidget {
  const _MonthPreviewStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(kIosCornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted “Add workout” picker — thumbnails, cards, and icon-only dismiss.
class _AddWorkoutPickerSheet extends StatelessWidget {
  const _AddWorkoutPickerSheet({
    required this.templates,
    required this.onSelect,
    required this.onDismiss,
  });

  final List<WorkoutTemplate> templates;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final topRadius = BorderRadius.only(
      topLeft: Radius.circular(kIosSurfaceRadius),
      topRight: Radius.circular(kIosSurfaceRadius),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: topRadius,
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
            borderRadius: topRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _kWeekListPanelBg.withValues(alpha: 0.97),
                      const Color(0xFFF5F3F0).withValues(alpha: 0.98),
                      const Color(0xFFEFEAE4).withValues(alpha: 0.96),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
                child: SizedBox(
                  height: h * 0.68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add workout',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.6,
                                      height: 1.15,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Choose a template, then pick a day for this week.',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                      color: _kMetaText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            LiftPressable(
                              onTap: onDismiss,
                              borderRadius: 22,
                              pressedScale: LiftMotion.gentlePressScale,
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: MynauiIcon(
                                    MynauiGlyphs.x,
                                    size: 22,
                                    color: Colors.black.withValues(alpha: 0.42),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: templates.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final t = templates[i];
                            return _AddWorkoutTemplateCard(
                              template: t,
                              onTap: () => onSelect(t.id),
                            );
                          },
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
  }
}

class _AddWorkoutTemplateCard extends StatelessWidget {
  const _AddWorkoutTemplateCard({required this.template, required this.onTap});

  final WorkoutTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const metaStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: _kMetaText,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _kWorkoutTileBorder.withValues(alpha: 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: WorkoutTemplateHeroImage(
                      imageUrl: template.imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kAccentDark, kAccentMid, kAccentLight],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.25,
                          height: 1.2,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: _kMetaText,
                          ),
                          Text(
                            '${template.estimatedDurationMinutes} min',
                            style: metaStyle,
                          ),
                          Text('·', style: metaStyle),
                          Icon(
                            Icons.list_alt_rounded,
                            size: 16,
                            color: _kMetaText,
                          ),
                          Text(
                            '${template.exercises.length} exercises',
                            style: metaStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: Colors.black.withValues(alpha: 0.14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

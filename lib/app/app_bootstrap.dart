import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lift/app/app_appearance.dart';
import 'package:lift/features/articles/articles_repository.dart';
import 'package:lift/shared/models/workout_history_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiftAppBootstrapData {
  const LiftAppBootstrapData({
    required this.workoutHistory,
    required this.themeMode,
    this.userGenderRaw,
  });

  final List<WorkoutHistoryEntry> workoutHistory;
  final ThemeMode themeMode;
  final String? userGenderRaw;
}

const String _kWorkoutHistoryStorageKey = 'lift_workout_history_v1';
const String _kUserGenderStorageKey = 'lift_user_gender';

Future<LiftAppBootstrapData> loadLiftAppBootstrapData() async {
  final prefsFuture = SharedPreferences.getInstance();
  final articlesWarmupFuture = ArticlesRepository.instance.prewarm();

  final prefs = await prefsFuture;
  final workoutHistory = _restoreWorkoutHistory(
    prefs.getString(_kWorkoutHistoryStorageKey),
  );
  final userGenderRaw = prefs.getString(_kUserGenderStorageKey);
  final themeMode = liftThemeModeFromString(
    prefs.getString(kLiftThemeModeStorageKey),
  );

  try {
    await articlesWarmupFuture;
  } catch (_) {
    // Keep launch resilient if optional warmup sources fail.
  }

  return LiftAppBootstrapData(
    workoutHistory: workoutHistory,
    themeMode: themeMode,
    userGenderRaw: userGenderRaw,
  );
}

List<WorkoutHistoryEntry> _restoreWorkoutHistory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <WorkoutHistoryEntry>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <WorkoutHistoryEntry>[];
    final restored = <WorkoutHistoryEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final parsed = _historyEntryFromMap(map);
      if (parsed != null) {
        restored.add(parsed);
      }
    }
    return restored;
  } catch (_) {
    return const <WorkoutHistoryEntry>[];
  }
}

WorkoutHistoryEntry? _historyEntryFromMap(Map<String, dynamic> map) {
  try {
    final startedAt = DateTime.tryParse('${map['startedAt'] ?? ''}');
    final completedAt = DateTime.tryParse('${map['completedAt'] ?? ''}');
    if (startedAt == null || completedAt == null) return null;

    final summariesRaw = map['exerciseSummaries'];
    final summaries = <WorkoutHistoryExerciseSummary>[];
    if (summariesRaw is List) {
      for (final item in summariesRaw) {
        if (item is! Map) continue;
        final summaryMap = item.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final exerciseName = '${summaryMap['exerciseName'] ?? ''}'.trim();
        if (exerciseName.isEmpty) continue;
        final setRowsRaw = summaryMap['setRows'];
        final setRows = <WorkoutHistorySetRow>[];
        if (setRowsRaw is List) {
          for (final row in setRowsRaw) {
            if (row is! Map) continue;
            final rowMap = row.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            setRows.add(
              WorkoutHistorySetRow(
                label: '${rowMap['label'] ?? ''}'.trim(),
                reps: (rowMap['reps'] as num?)?.toInt() ?? 0,
                weightKg: (rowMap['weightKg'] as num?)?.toDouble() ?? 0,
                restSeconds: (rowMap['restSeconds'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        summaries.add(
          WorkoutHistoryExerciseSummary(
            exerciseName: exerciseName,
            setCount: (summaryMap['setCount'] as num?)?.toInt() ?? 0,
            totalReps: (summaryMap['totalReps'] as num?)?.toInt() ?? 0,
            totalVolumeKg:
                (summaryMap['totalVolumeKg'] as num?)?.toDouble() ?? 0,
            maxWeightKg: (summaryMap['maxWeightKg'] as num?)?.toDouble() ?? 0,
            muscleGroups:
                (summaryMap['muscleGroups'] is List)
                    ? (summaryMap['muscleGroups'] as List)
                        .whereType<String>()
                        .toList(growable: false)
                    : const <String>[],
            setRows: List<WorkoutHistorySetRow>.unmodifiable(setRows),
          ),
        );
      }
    }

    final muscleRaw = map['muscleGroupVolumeKg'];
    final muscleVolume = <String, double>{};
    if (muscleRaw is Map) {
      for (final entry in muscleRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is num) {
          muscleVolume[key] = value.toDouble();
        }
      }
    }

    final id = '${map['id'] ?? ''}'.trim();
    final workoutName = '${map['workoutName'] ?? ''}'.trim();
    if (id.isEmpty || workoutName.isEmpty) return null;

    return WorkoutHistoryEntry(
      id: id,
      workoutName: workoutName,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: Duration(
        milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
      ),
      totalVolumeKg: (map['totalVolumeKg'] as num?)?.toDouble() ?? 0,
      totalReps: (map['totalReps'] as num?)?.toInt() ?? 0,
      exercisesCompleted: (map['exercisesCompleted'] as num?)?.toInt() ?? 0,
      totalExercises: (map['totalExercises'] as num?)?.toInt() ?? 0,
      prsAchieved: (map['prsAchieved'] as num?)?.toInt() ?? 0,
      exerciseSummaries: summaries,
      muscleGroupVolumeKg: muscleVolume,
    );
  } catch (_) {
    return null;
  }
}

/// Same persisted history as [LiftAppBootstrapData.workoutHistory] / [HomeScreen].
Future<List<WorkoutHistoryEntry>> loadStoredWorkoutHistory() async {
  final prefs = await SharedPreferences.getInstance();
  return _restoreWorkoutHistory(prefs.getString(_kWorkoutHistoryStorageKey));
}

Future<void> saveStoredWorkoutHistory(List<WorkoutHistoryEntry> history) async {
  final prefs = await SharedPreferences.getInstance();
  final payload = jsonEncode(
    history.map(_historyEntryToMap).toList(growable: false),
  );
  await prefs.setString(_kWorkoutHistoryStorageKey, payload);
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

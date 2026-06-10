import 'dart:convert';

import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/user_profile.dart';

enum WorkoutPhase { idle, countdown, active }

class WorkoutSegment {
  const WorkoutSegment({
    required this.exercise,
    required this.startedAt,
    required this.endedAt,
    required this.repetitions,
    required this.unstableDuration,
  });

  final ExerciseType exercise;
  final DateTime startedAt;
  final DateTime endedAt;
  final int repetitions;
  final Duration unstableDuration;

  Duration get duration => endedAt.difference(startedAt);

  bool get wasUnstable => unstableDuration > Duration.zero;

  double get unstableRatio {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }
    return unstableDuration.inMilliseconds / duration.inMilliseconds;
  }
}

final Map<int, ExerciseType> protocolMovementExercises = <int, ExerciseType>{
  0: exerciseCatalog[0],
  1: exerciseCatalog[3],
  2: exerciseCatalog[6],
  3: exerciseCatalog[2],
  4: exerciseCatalog[5],
  5: exerciseCatalog[4],
  6: exerciseCatalog[7],
  7: exerciseCatalog[1],
};

ExerciseType exerciseForProtocolMovement(int movementId) {
  return protocolMovementExercises[movementId] ?? exerciseCatalog.first;
}

class MovementSummary {
  const MovementSummary({
    required this.movementId,
    required this.exerciseLabel,
    required this.reps,
    required this.sets,
  });

  final int movementId;
  final String exerciseLabel;
  final int reps;
  final int sets;

  bool get hasWork => reps > 0 || sets > 0;

  factory MovementSummary.fromProtocol({
    required int movementId,
    required int reps,
    required int sets,
  }) {
    return MovementSummary(
      movementId: movementId,
      exerciseLabel: exerciseForProtocolMovement(movementId).label,
      reps: reps,
      sets: sets,
    );
  }

  factory MovementSummary.fromJson(Map<String, dynamic> json) {
    final int movementId = _asInt(json['movementId'], 0);
    return MovementSummary(
      movementId: movementId,
      exerciseLabel: json['exerciseLabel'] is String
          ? json['exerciseLabel'] as String
          : exerciseForProtocolMovement(movementId).label,
      reps: _asInt(json['reps'], 0),
      sets: _asInt(json['sets'], 0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'movementId': movementId,
      'exerciseLabel': exerciseLabel,
      'reps': reps,
      'sets': sets,
    };
  }
}

class WorkoutHistoryEntry {
  const WorkoutHistoryEntry({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.totalMovementCount,
    required this.movements,
    required this.vo2Min,
    required this.vo2Max,
    required this.vo2Avg,
    required this.vo2SampleCount,
    required this.rpeMin,
    required this.rpeMax,
    required this.rpeAvg,
    required this.rpeSampleCount,
    required this.loadStatus,
    this.recommendationInput,
  });

  final String id;
  final String profileId;
  final String profileName;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final int totalMovementCount;
  final List<MovementSummary> movements;
  final double vo2Min;
  final double vo2Max;
  final double vo2Avg;
  final int vo2SampleCount;
  final int rpeMin;
  final int rpeMax;
  final int rpeAvg;
  final int rpeSampleCount;
  final int loadStatus;
  final WorkoutRecommendationInput? recommendationInput;

  int get totalReps {
    return movements.fold<int>(0, (int total, MovementSummary movement) {
      return total + movement.reps;
    });
  }

  List<MovementSummary> get activeMovements {
    final List<MovementSummary> active = movements
        .where((MovementSummary movement) => movement.hasWork)
        .toList();
    return active.isEmpty ? movements.take(3).toList() : active;
  }

  String get durationLabel {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds.remainder(60);
    if (minutes <= 0) {
      return '$seconds 秒';
    }
    return '$minutes 分 $seconds 秒';
  }

  factory WorkoutHistoryEntry.fromProtocol({
    required WorkoutSummaryPayload summary,
    required UserProfile profile,
    RecommendationInputPayload? recommendationInput,
    DateTime? savedAt,
  }) {
    final DateTime fallbackEnd = savedAt ?? DateTime.now();
    final DateTime startedAt = summary.workoutStartTsMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(summary.workoutStartTsMs)
        : fallbackEnd.subtract(Duration(milliseconds: summary.durationMs));
    final DateTime endedAt = summary.workoutEndTsMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(summary.workoutEndTsMs)
        : fallbackEnd;
    return WorkoutHistoryEntry(
      id: 'workout-${endedAt.microsecondsSinceEpoch}',
      profileId: profile.id,
      profileName: profile.displayName,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: Duration(milliseconds: summary.durationMs),
      totalMovementCount: summary.totalMovementCount,
      movements: List<MovementSummary>.generate(8, (int index) {
        return MovementSummary.fromProtocol(
          movementId: index,
          reps: summary.repsByMovement[index],
          sets: summary.setsByMovement[index],
        );
      }),
      vo2Min: summary.vo2Min,
      vo2Max: summary.vo2Max,
      vo2Avg: summary.vo2Avg,
      vo2SampleCount: summary.vo2SampleCount,
      rpeMin: summary.rpeMin,
      rpeMax: summary.rpeMax,
      rpeAvg: summary.rpeAvg,
      rpeSampleCount: summary.rpeSampleCount,
      loadStatus: summary.loadStatus,
      recommendationInput: recommendationInput == null
          ? null
          : WorkoutRecommendationInput.fromProtocol(recommendationInput),
    );
  }

  factory WorkoutHistoryEntry.fallbackFromLive({
    required UserProfile profile,
    required DateTime startedAt,
    required DateTime endedAt,
    required int movementId,
    required int reps,
    required int sets,
    required double? vo2,
    required RpeAlertPayload? rpeAlert,
    RecommendationInputPayload? recommendationInput,
  }) {
    final List<MovementSummary> movements = List<MovementSummary>.generate(
      8,
      (int index) => MovementSummary.fromProtocol(
        movementId: index,
        reps: index == movementId ? reps : 0,
        sets: index == movementId ? sets : 0,
      ),
    );
    final int rpe = rpeAlert?.rpe ?? 0;
    final double vo2Value = vo2 ?? 0;
    return WorkoutHistoryEntry(
      id: 'workout-${endedAt.microsecondsSinceEpoch}',
      profileId: profile.id,
      profileName: profile.displayName,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: endedAt.difference(startedAt),
      totalMovementCount: reps > 0 ? 1 : 0,
      movements: movements,
      vo2Min: vo2Value,
      vo2Max: vo2Value,
      vo2Avg: vo2Value,
      vo2SampleCount: vo2 == null ? 0 : 1,
      rpeMin: rpe,
      rpeMax: rpe,
      rpeAvg: rpe,
      rpeSampleCount: rpeAlert == null ? 0 : 1,
      loadStatus: 0,
      recommendationInput: recommendationInput == null
          ? null
          : WorkoutRecommendationInput.fromProtocol(recommendationInput),
    );
  }

  factory WorkoutHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WorkoutHistoryEntry(
      id: json['id'] is String ? json['id'] as String : 'workout-unknown',
      profileId: json['profileId'] is String ? json['profileId'] as String : '',
      profileName: json['profileName'] is String
          ? json['profileName'] as String
          : '使用者',
      startedAt: _dateFromMs(json['startedAtMs']),
      endedAt: _dateFromMs(json['endedAtMs']),
      duration: Duration(milliseconds: _asInt(json['durationMs'], 0)),
      totalMovementCount: _asInt(json['totalMovementCount'], 0),
      movements: _movementList(json['movements']),
      vo2Min: _asDouble(json['vo2Min'], 0),
      vo2Max: _asDouble(json['vo2Max'], 0),
      vo2Avg: _asDouble(json['vo2Avg'], 0),
      vo2SampleCount: _asInt(json['vo2SampleCount'], 0),
      rpeMin: _asInt(json['rpeMin'], 0),
      rpeMax: _asInt(json['rpeMax'], 0),
      rpeAvg: _asInt(json['rpeAvg'], 0),
      rpeSampleCount: _asInt(json['rpeSampleCount'], 0),
      loadStatus: _asInt(json['loadStatus'], 0),
      recommendationInput: json['recommendationInput'] is Map
          ? WorkoutRecommendationInput.fromJson(
              Map<String, dynamic>.from(json['recommendationInput'] as Map),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'profileId': profileId,
      'profileName': profileName,
      'startedAtMs': startedAt.millisecondsSinceEpoch,
      'endedAtMs': endedAt.millisecondsSinceEpoch,
      'durationMs': duration.inMilliseconds,
      'totalMovementCount': totalMovementCount,
      'movements': movements.map((MovementSummary movement) {
        return movement.toJson();
      }).toList(),
      'vo2Min': vo2Min,
      'vo2Max': vo2Max,
      'vo2Avg': vo2Avg,
      'vo2SampleCount': vo2SampleCount,
      'rpeMin': rpeMin,
      'rpeMax': rpeMax,
      'rpeAvg': rpeAvg,
      'rpeSampleCount': rpeSampleCount,
      'loadStatus': loadStatus,
      if (recommendationInput != null)
        'recommendationInput': recommendationInput!.toJson(),
    };
  }
}

class WorkoutRecommendationInput {
  const WorkoutRecommendationInput({
    required this.recommendationStatus,
    required this.hasLowRpeInterval,
    required this.hasHighRpeInterval,
    required this.loadStatus,
    required this.vo2Trend,
    required this.lowRpeTotalMs,
    required this.highRpeTotalMs,
  });

  final int recommendationStatus;
  final bool hasLowRpeInterval;
  final bool hasHighRpeInterval;
  final int loadStatus;
  final int vo2Trend;
  final int lowRpeTotalMs;
  final int highRpeTotalMs;

  factory WorkoutRecommendationInput.fromProtocol(
    RecommendationInputPayload payload,
  ) {
    return WorkoutRecommendationInput(
      recommendationStatus: payload.recommendationStatus,
      hasLowRpeInterval: payload.hasLowRpeInterval,
      hasHighRpeInterval: payload.hasHighRpeInterval,
      loadStatus: payload.loadStatus,
      vo2Trend: payload.vo2Trend,
      lowRpeTotalMs: payload.lowRpeTotalMs,
      highRpeTotalMs: payload.highRpeTotalMs,
    );
  }

  factory WorkoutRecommendationInput.fromJson(Map<String, dynamic> json) {
    return WorkoutRecommendationInput(
      recommendationStatus: _asInt(json['recommendationStatus'], 0),
      hasLowRpeInterval: json['hasLowRpeInterval'] == true,
      hasHighRpeInterval: json['hasHighRpeInterval'] == true,
      loadStatus: _asInt(json['loadStatus'], 0),
      vo2Trend: _asInt(json['vo2Trend'], 0),
      lowRpeTotalMs: _asInt(json['lowRpeTotalMs'], 0),
      highRpeTotalMs: _asInt(json['highRpeTotalMs'], 0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'recommendationStatus': recommendationStatus,
      'hasLowRpeInterval': hasLowRpeInterval,
      'hasHighRpeInterval': hasHighRpeInterval,
      'loadStatus': loadStatus,
      'vo2Trend': vo2Trend,
      'lowRpeTotalMs': lowRpeTotalMs,
      'highRpeTotalMs': highRpeTotalMs,
    };
  }
}

String encodeWorkoutHistory(List<WorkoutHistoryEntry> entries) {
  return jsonEncode(
    entries.map((WorkoutHistoryEntry entry) {
      return entry.toJson();
    }).toList(),
  );
}

List<WorkoutHistoryEntry> decodeWorkoutHistory(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) {
    return const <WorkoutHistoryEntry>[];
  }
  try {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      return const <WorkoutHistoryEntry>[];
    }
    return decoded.whereType<Map>().map((Map item) {
      return WorkoutHistoryEntry.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  } catch (_) {
    return const <WorkoutHistoryEntry>[];
  }
}

List<MovementSummary> _movementList(Object? value) {
  if (value is! List) {
    return List<MovementSummary>.generate(8, (int index) {
      return MovementSummary.fromProtocol(movementId: index, reps: 0, sets: 0);
    });
  }
  return value.whereType<Map>().map((Map item) {
    return MovementSummary.fromJson(Map<String, dynamic>.from(item));
  }).toList();
}

DateTime _dateFromMs(Object? value) {
  return DateTime.fromMillisecondsSinceEpoch(_asInt(value, 0));
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

double _asDouble(Object? value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return fallback;
}

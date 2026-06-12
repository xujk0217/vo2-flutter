import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/user_profile.dart';

const UserProfile _profile = UserProfile(
  id: 'kai',
  displayName: 'Kai',
  heightCm: 180,
  weightKg: 75,
  age: 35,
  sex: UserSex.male,
);

void main() {
  group('WorkoutSegment', () {
    test('reports duration and instability semantics', () {
      final DateTime startedAt = DateTime(2026, 1, 1, 10, 0, 0);
      final DateTime endedAt = startedAt.add(const Duration(seconds: 20));
      final WorkoutSegment segment = WorkoutSegment(
        exercise: exerciseCatalog.first,
        startedAt: startedAt,
        endedAt: endedAt,
        repetitions: 12,
        unstableDuration: const Duration(seconds: 5),
      );

      expect(segment.duration, const Duration(seconds: 20));
      expect(segment.wasUnstable, isTrue);
      expect(segment.unstableRatio, 0.25);
    });

    test('reports stable segments correctly', () {
      final DateTime startedAt = DateTime(2026, 1, 1, 10, 0, 0);
      final DateTime endedAt = startedAt.add(const Duration(seconds: 10));
      final WorkoutSegment segment = WorkoutSegment(
        exercise: exerciseCatalog.first,
        startedAt: startedAt,
        endedAt: endedAt,
        repetitions: 8,
        unstableDuration: Duration.zero,
      );

      expect(segment.wasUnstable, isFalse);
      expect(segment.unstableRatio, 0);
    });
  });

  group('protocol movement labels', () {
    test('keeps fitness ids 0 through 7 and excludes other', () {
      expect(
        protocolMovementExercises.keys,
        orderedEquals(<int>[0, 1, 2, 3, 4, 5, 6, 7]),
      );
      expect(
        protocolMovementExercises,
        isNot(contains(protocolOtherMovementId)),
      );
      expect(exerciseForProtocolMovement(0), exerciseCatalog[0]);
      expect(exerciseForProtocolMovement(7)!.label, '單手啞鈴划船');
      expect(exerciseForProtocolMovement(protocolOtherMovementId), isNull);
    });

    test('labels other and unknown without falling back to first exercise', () {
      final MovementSummary otherSummary = MovementSummary.fromProtocol(
        movementId: protocolOtherMovementId,
        reps: 9,
        sets: 2,
      );
      final MovementSummary staleJsonSummary =
          MovementSummary.fromJson(<String, dynamic>{
            'movementId': protocolOtherMovementId,
            'exerciseLabel': exerciseCatalog.first.label,
            'reps': 9,
            'sets': 2,
          });

      expect(
        movementLabelForProtocolMovement(protocolOtherMovementId),
        protocolOtherMovementLabel,
      );
      expect(
        movementLabelForProtocolMovement(42),
        protocolUnknownMovementLabel,
      );
      expect(otherSummary.exerciseLabel, protocolOtherMovementLabel);
      expect(otherSummary.reps, 0);
      expect(otherSummary.sets, 0);
      expect(staleJsonSummary.exerciseLabel, protocolOtherMovementLabel);
      expect(staleJsonSummary.reps, 0);
      expect(staleJsonSummary.sets, 0);
    });
  });

  group('WorkoutHistoryEntry', () {
    test('fromProtocol always builds eight fitness movement summaries', () {
      final WorkoutHistoryEntry entry = WorkoutHistoryEntry.fromProtocol(
        profile: _profile,
        savedAt: DateTime(2026, 1, 1, 10, 5),
        summary: const WorkoutSummaryPayload(
          workoutStartTsMs: 0,
          workoutEndTsMs: 0,
          durationMs: 300000,
          totalMovementCount: 8,
          repsByMovement: <int>[1, 2, 3, 4, 5, 6, 7, 8],
          setsByMovement: <int>[8, 7, 6, 5, 4, 3, 2, 1],
          vo2Min: 30,
          vo2Max: 42,
          vo2Avg: 36,
          vo2SampleCount: 5,
          rpeMin: 3,
          rpeMax: 8,
          rpeAvg: 6,
          rpeSampleCount: 5,
          loadStatus: 0,
        ),
      );

      expect(entry.movements, hasLength(8));
      expect(
        entry.movements.map((MovementSummary movement) => movement.movementId),
        orderedEquals(<int>[0, 1, 2, 3, 4, 5, 6, 7]),
      );
      expect(entry.movements.last.exerciseLabel, '單手啞鈴划船');
      expect(entry.totalReps, 36);
    });

    test('fallbackFromLive does not assign other reps to fitness rows', () {
      final DateTime startedAt = DateTime(2026, 1, 1, 10);
      final WorkoutHistoryEntry entry = WorkoutHistoryEntry.fallbackFromLive(
        profile: _profile,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 5)),
        movementId: protocolOtherMovementId,
        reps: 12,
        sets: 3,
        vo2: 40,
        rpeAlert: null,
      );

      expect(entry.movements, hasLength(8));
      expect(entry.totalMovementCount, 0);
      expect(entry.totalReps, 0);
      expect(
        entry.movements.every(
          (MovementSummary movement) =>
              movement.reps == 0 && movement.sets == 0,
        ),
        isTrue,
      );
    });

    test('fallbackFromLive still assigns valid fitness movement rows', () {
      final DateTime startedAt = DateTime(2026, 1, 1, 10);
      final WorkoutHistoryEntry entry = WorkoutHistoryEntry.fallbackFromLive(
        profile: _profile,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 5)),
        movementId: 1,
        reps: 12,
        sets: 3,
        vo2: 40,
        rpeAlert: null,
      );

      expect(entry.movements, hasLength(8));
      expect(entry.totalMovementCount, 1);
      expect(entry.movements[1].reps, 12);
      expect(entry.movements[1].sets, 3);
      expect(entry.totalReps, 12);
    });
  });
}

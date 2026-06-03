import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/models/workout_models.dart';

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
}

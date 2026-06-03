import 'package:vo2_flutter/exercise_catalog.dart';

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

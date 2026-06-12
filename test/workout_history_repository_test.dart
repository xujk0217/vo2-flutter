import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/workout_history_repository.dart';

WorkoutHistoryEntry _entry(int index) {
  final DateTime endedAt = DateTime(
    2026,
    1,
    1,
    10,
    0,
  ).add(Duration(minutes: index));
  return WorkoutHistoryEntry(
    id: 'entry-$index',
    profileId: 'kai',
    profileName: 'Kai',
    startedAt: endedAt.subtract(const Duration(minutes: 12)),
    endedAt: endedAt,
    duration: const Duration(minutes: 12),
    totalMovementCount: 1,
    movements: <MovementSummary>[
      MovementSummary.fromProtocol(movementId: 0, reps: index, sets: 1),
    ],
    vo2Min: 30,
    vo2Max: 44,
    vo2Avg: 36 + index / 10,
    vo2SampleCount: 5,
    rpeMin: 4,
    rpeMax: 8,
    rpeAvg: 6,
    rpeSampleCount: 5,
    loadStatus: 0,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists latest workouts and caps history to 100 entries', () async {
    const WorkoutHistoryRepository repository = WorkoutHistoryRepository();

    for (int i = 0; i < 105; i += 1) {
      await repository.add(_entry(i));
    }

    final List<WorkoutHistoryEntry> entries = await repository.load();
    expect(entries, hasLength(WorkoutHistoryRepository.maxEntries));
    expect(entries.first.id, 'entry-104');
    expect(entries.last.id, 'entry-5');
  });

  test('explicit protocol movement mapping does not follow catalog order', () {
    expect(exerciseForProtocolMovement(1)!.label, '啞鈴二頭彎舉');
    expect(
      exerciseForProtocolMovement(1)!.label,
      isNot(exerciseCatalog[1].label),
    );
    expect(exerciseForProtocolMovement(7)!.label, '單手啞鈴划船');
  });
}

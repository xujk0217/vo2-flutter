import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/models/workout_models.dart';

class WorkoutHistoryRepository {
  const WorkoutHistoryRepository();

  static const int maxEntries = 100;
  static const String _historyKey = 'workout_history_entries_json';

  Future<List<WorkoutHistoryEntry>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<WorkoutHistoryEntry> entries = decodeWorkoutHistory(
      prefs.getString(_historyKey),
    ).toList();
    entries.sort(
      (WorkoutHistoryEntry a, WorkoutHistoryEntry b) =>
          b.endedAt.compareTo(a.endedAt),
    );
    return entries.take(maxEntries).toList();
  }

  Future<void> saveAll(List<WorkoutHistoryEntry> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<WorkoutHistoryEntry> capped = entries.toList()
      ..sort(
        (WorkoutHistoryEntry a, WorkoutHistoryEntry b) =>
            b.endedAt.compareTo(a.endedAt),
      );
    await prefs.setString(
      _historyKey,
      encodeWorkoutHistory(capped.take(maxEntries).toList()),
    );
  }

  Future<WorkoutHistoryEntry> add(WorkoutHistoryEntry entry) async {
    final List<WorkoutHistoryEntry> entries = await load();
    await saveAll(<WorkoutHistoryEntry>[entry, ...entries]);
    return entry;
  }

  Future<WorkoutHistoryEntry?> latest() async {
    final List<WorkoutHistoryEntry> entries = await load();
    return entries.isEmpty ? null : entries.first;
  }

  Future<WorkoutHistoryEntry?> findById(String id) async {
    final List<WorkoutHistoryEntry> entries = await load();
    for (final WorkoutHistoryEntry entry in entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}

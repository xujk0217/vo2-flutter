import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/history_page.dart';
import 'package:vo2_flutter/screens/live_fitness_page.dart';
import 'package:vo2_flutter/screens/workout_review_page.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/workout_history_repository.dart';
import 'package:vo2_flutter/workout_recommendation.dart';

class _FakeWriter implements DeviceProtocolFrameWriter {
  final List<DeviceFrame> writtenFrames = <DeviceFrame>[];

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    writtenFrames.add(frame);
  }
}

ReceiverDataEvent _bleDataEvent(int messageType, int seq, List<int> payload) {
  return ReceiverDataEvent(
    payload: jsonEncode(<String, dynamic>{
      'messageType': messageType,
      'flags': 0,
      'seq': seq,
      'payloadBase64': base64Encode(Uint8List.fromList(payload)),
    }),
  );
}

Uint8List _classifierPayload({
  int mode = 1,
  int movementId = 1,
  int reps = 12,
  int sets = 3,
}) {
  final Uint8List payload = Uint8List(14);
  ByteData.sublistView(payload)
    ..setUint64(0, 123456, Endian.little)
    ..setUint8(8, mode)
    ..setUint8(9, movementId)
    ..setUint16(10, reps, Endian.little)
    ..setUint16(12, sets, Endian.little);
  return payload;
}

Uint8List _vo2Payload(double value) {
  final Uint8List payload = Uint8List(12);
  ByteData.sublistView(payload)
    ..setUint64(0, 123456789, Endian.little)
    ..setFloat32(8, value, Endian.little);
  return payload;
}

Uint8List _summaryPayload() {
  final Uint8List payload = Uint8List(77);
  final ByteData data = ByteData.sublistView(payload);
  data
    ..setUint64(
      0,
      DateTime(2026, 1, 1, 10).millisecondsSinceEpoch,
      Endian.little,
    )
    ..setUint64(
      8,
      DateTime(2026, 1, 1, 10, 12).millisecondsSinceEpoch,
      Endian.little,
    )
    ..setUint64(16, 720000, Endian.little)
    ..setUint8(24, 1)
    ..setUint16(27, 12, Endian.little)
    ..setUint16(43, 3, Endian.little)
    ..setFloat32(57, 30, Endian.little)
    ..setFloat32(61, 44, Endian.little)
    ..setFloat32(65, 38, Endian.little)
    ..setUint16(69, 8, Endian.little)
    ..setUint8(71, 4)
    ..setUint8(72, 8)
    ..setUint8(73, 6)
    ..setUint16(74, 8, Endian.little);
  return payload;
}

Widget _wrap(Widget child, {Map<String, WidgetBuilder>? routes}) {
  return MaterialApp(home: child, routes: routes ?? <String, WidgetBuilder>{});
}

Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 100));
}

WorkoutHistoryEntry _entry({
  String id = 'entry-1',
  int rpeAvg = 6,
  WorkoutRecommendationInput? recommendationInput,
}) {
  return WorkoutHistoryEntry(
    id: id,
    profileId: 'kai',
    profileName: 'Kai',
    startedAt: DateTime(2026, 1, 1, 10),
    endedAt: DateTime(2026, 1, 1, 10, 12),
    duration: const Duration(minutes: 12),
    totalMovementCount: 1,
    movements: <MovementSummary>[
      MovementSummary.fromProtocol(movementId: 1, reps: 12, sets: 3),
    ],
    vo2Min: 30,
    vo2Max: 44,
    vo2Avg: 38,
    vo2SampleCount: 8,
    rpeMin: 4,
    rpeMax: 8,
    rpeAvg: rpeAvg,
    rpeSampleCount: 8,
    loadStatus: 0,
    recommendationInput: recommendationInput,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('recommendation builder returns deterministic Chinese coaching', () {
    final WorkoutRecommendation recommendation =
        const WorkoutRecommendationBuilder().build(
          _entry(
            recommendationInput: const WorkoutRecommendationInput(
              recommendationStatus: 1,
              hasLowRpeInterval: false,
              hasHighRpeInterval: true,
              loadStatus: 0,
              vo2Trend: 0,
              lowRpeTotalMs: 0,
              highRpeTotalMs: 30000,
            ),
          ),
        );

    expect(recommendation.headline, contains('強度偏高'));
    expect(recommendation.nextWorkoutText, contains('總組數減少一組'));
  });

  testWidgets('live page waits for delayed summary before saving review', (
    WidgetTester tester,
  ) async {
    final _FakeWriter writer = _FakeWriter();
    final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
    const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
    const UserProfile profile = UserProfile(
      id: 'kai',
      displayName: 'Kai',
      heightCm: 180,
      weightKg: 75,
      age: 35,
      sex: UserSex.male,
    );
    addTearDown(session.dispose);

    await session.handleDataEvent(
      _bleDataEvent(
        DeviceMessageType.classifierResult,
        1,
        _classifierPayload(),
      ),
    );
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.vo2Prediction, 2, _vo2Payload(42.5)),
    );

    await _pumpTall(
      tester,
      _wrap(
        LiveFitnessPage(
          protocolSession: session,
          profile: profile,
          historyRepository: repository,
        ),
        routes: <String, WidgetBuilder>{
          WorkoutReviewPage.routeName: (_) => const WorkoutReviewPage(),
        },
      ),
    );

    expect(find.text('啞鈴二頭彎舉'), findsOneWidget);
    expect(find.text('42.5'), findsOneWidget);

    await tester.tap(find.text('開始訓練'));
    await tester.pump();
    await tester.tap(find.text('結束並查看回顧'));
    await tester.pump();

    expect(writer.writtenFrames, hasLength(2));
    expect(
      writer.writtenFrames[0].payload.first,
      FitnessCommand.startWorkout.value,
    );
    expect(
      writer.writtenFrames[1].payload.first,
      FitnessCommand.endWorkout.value,
    );
    expect(find.text('等待手環摘要'), findsOneWidget);
    expect(find.text('訓練回顧'), findsNothing);
    expect(await repository.load(), isEmpty);

    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.workoutSummary, 3, _summaryPayload()),
    );
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.workoutSummary, 4, _summaryPayload()),
    );
    await tester.pumpAndSettle();

    expect(find.text('訓練回顧'), findsOneWidget);
    expect(find.textContaining('完成一堂'), findsOneWidget);
    final List<WorkoutHistoryEntry> entries = await repository.load();
    expect(entries, hasLength(1));
    expect(entries.single.vo2Avg, closeTo(38, 0.001));
  });

  testWidgets('live page renders other as non-fitness state', (
    WidgetTester tester,
  ) async {
    final DeviceProtocolSession session = DeviceProtocolSession();
    const UserProfile profile = UserProfile(
      id: 'kai',
      displayName: 'Kai',
      heightCm: 180,
      weightKg: 75,
      age: 35,
      sex: UserSex.male,
    );
    addTearDown(session.dispose);

    await session.handleDataEvent(
      _bleDataEvent(
        DeviceMessageType.classifierResult,
        1,
        _classifierPayload(mode: 0, movementId: 255, reps: 12, sets: 3),
      ),
    );

    await _pumpTall(
      tester,
      _wrap(LiveFitnessPage(protocolSession: session, profile: profile)),
    );

    expect(find.text('其他'), findsWidgets);
    expect(find.text('啞鈴臥推'), findsNothing);
    expect(find.text('非 8 種訓練動作，不計入組數'), findsOneWidget);
    expect(
      find.text('這個狀態會保留即時 VO2 與 RPE，但不會把次數或組數歸到任何一個健身動作。'),
      findsOneWidget,
    );
  });

  testWidgets('live page saves fallback only after summary timeout', (
    WidgetTester tester,
  ) async {
    final _FakeWriter writer = _FakeWriter();
    final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
    const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
    const UserProfile profile = UserProfile(
      id: 'kai',
      displayName: 'Kai',
      heightCm: 180,
      weightKg: 75,
      age: 35,
      sex: UserSex.male,
    );
    addTearDown(session.dispose);

    await session.handleDataEvent(
      _bleDataEvent(
        DeviceMessageType.classifierResult,
        1,
        _classifierPayload(),
      ),
    );
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.vo2Prediction, 2, _vo2Payload(42.5)),
    );

    await _pumpTall(
      tester,
      _wrap(
        LiveFitnessPage(
          protocolSession: session,
          profile: profile,
          historyRepository: repository,
        ),
        routes: <String, WidgetBuilder>{
          WorkoutReviewPage.routeName: (_) => const WorkoutReviewPage(),
        },
      ),
    );

    await tester.tap(find.text('開始訓練'));
    await tester.pump();
    await tester.tap(find.text('結束並查看回顧'));
    await tester.pump();

    expect(find.text('等待手環摘要'), findsOneWidget);
    expect(await repository.load(), isEmpty);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(
      writer.writtenFrames[1].payload.first,
      FitnessCommand.endWorkout.value,
    );
    expect(find.text('訓練回顧'), findsOneWidget);
    final List<WorkoutHistoryEntry> entries = await repository.load();
    expect(entries, hasLength(1));
    expect(entries.single.vo2Avg, closeTo(42.5, 0.001));
  });

  testWidgets('review page renders summary and recommendation CTAs', (
    WidgetTester tester,
  ) async {
    await _pumpTall(tester, _wrap(WorkoutReviewPage(entry: _entry())));

    expect(find.text('訓練回顧'), findsOneWidget);
    expect(find.text('動作拆解'), findsOneWidget);
    expect(find.text('教練建議'), findsOneWidget);
    expect(find.text('啞鈴二頭彎舉'), findsOneWidget);
    expect(find.text('查看歷史'), findsOneWidget);
  });

  testWidgets('history page renders empty and list/trend states', (
    WidgetTester tester,
  ) async {
    const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
    await _pumpTall(tester, _wrap(HistoryPage(key: UniqueKey())));
    expect(find.text('還沒有訓練紀錄'), findsOneWidget);

    await repository.add(_entry(id: 'entry-2'));
    await _pumpTall(
      tester,
      _wrap(
        HistoryPage(key: UniqueKey()),
        routes: <String, WidgetBuilder>{
          WorkoutReviewPage.routeName: (_) => const WorkoutReviewPage(),
        },
      ),
    );

    expect(find.text('VO2 趨勢'), findsOneWidget);
    expect(find.textContaining('12 下'), findsOneWidget);
  });
}

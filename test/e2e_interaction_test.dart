import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/app.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/history_page.dart';
import 'package:vo2_flutter/screens/live_fitness_page.dart';
import 'package:vo2_flutter/screens/onboarding_screen.dart';
import 'package:vo2_flutter/screens/training_home_screen.dart';
import 'package:vo2_flutter/screens/workout_review_page.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/workout_history_repository.dart';

class _FakeReceiverTransport implements ReceiverTransport {
  _FakeReceiverTransport();

  final StreamController<ReceiverTransportEvent> eventController =
      StreamController<ReceiverTransportEvent>.broadcast();
  final ReceiverTransportKind transportKind = ReceiverTransportKind.ble;
  final String deviceName = DeviceBleUuids.advertisedName;
  final String deviceId = 'ble-1';
  int requestPermissionsCalls = 0;
  int isEnabledCalls = 0;
  int getDevicesCalls = 0;
  bool disconnected = false;

  @override
  Future<void> connect(String deviceId) async {
    eventController.add(
      const ReceiverStatusEvent(state: 'connected', message: 'BLE 已連線。'),
    );
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Stream<ReceiverTransportEvent> events() => eventController.stream;

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() async {
    getDevicesCalls += 1;
    return <ReceiverDeviceInfo>[
      ReceiverDeviceInfo(
        name: deviceName,
        id: deviceId,
        transportKind: transportKind,
      ),
    ];
  }

  @override
  Future<bool> isEnabled() async {
    isEnabledCalls += 1;
    return true;
  }

  @override
  Future<bool> requestPermissions() async {
    requestPermissionsCalls += 1;
    return true;
  }
}

class _FakeWritableReceiverTransport extends _FakeReceiverTransport
    implements DeviceProtocolFrameWriter {
  final List<DeviceFrame> writtenFrames = <DeviceFrame>[];

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    writtenFrames.add(frame);
  }
}

class _FakeWriter implements DeviceProtocolFrameWriter {
  final List<DeviceFrame> writtenFrames = <DeviceFrame>[];

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    writtenFrames.add(frame);
  }
}

const UserProfile _kaiProfile = UserProfile(
  id: 'kai',
  displayName: 'Kai 測試',
  heightCm: 180,
  weightKg: 75,
  age: 35,
  sex: UserSex.male,
  vo2Max: 44,
);

Widget _wrap(Widget child, {Map<String, WidgetBuilder>? routes}) {
  return MaterialApp(
    key: UniqueKey(),
    home: child,
    routes: routes ?? <String, WidgetBuilder>{},
  );
}

Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 100));
}

void testWidgetsWithSemantics(
  String description,
  WidgetTesterCallback callback,
) {
  testWidgets(description, (WidgetTester tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await callback(tester);
    } finally {
      semanticsHandle.dispose();
    }
  });
}

void _expectSemanticTap(
  WidgetTester tester,
  Pattern label, {
  required bool enabled,
}) {
  final Finder finder = find.bySemanticsLabel(label);
  expect(finder, findsOneWidget);
  final SemanticsData data = tester.getSemantics(finder).getSemanticsData();
  expect(data.hasAction(SemanticsAction.tap), enabled);
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

Uint8List _calibrationProgressPayload({
  required int elapsedMs,
  required int hrEstimate,
}) {
  final Uint8List payload = Uint8List(5);
  ByteData.sublistView(payload)
    ..setUint32(0, elapsedMs, Endian.little)
    ..setUint8(4, hrEstimate);
  return payload;
}

Uint8List _calibrationDonePayload({
  int avgHrBpm = 70,
  int qualityScore = 92,
  int sampleCount = 128,
  int durationMs = 30000,
  int status = 0,
}) {
  final Uint8List payload = Uint8List(9);
  ByteData.sublistView(payload)
    ..setUint8(0, avgHrBpm)
    ..setUint8(1, qualityScore)
    ..setUint16(2, sampleCount, Endian.little)
    ..setUint32(4, durationMs, Endian.little)
    ..setUint8(8, status);
  return payload;
}

Uint8List _classifierPayload({
  int movementId = 1,
  int reps = 12,
  int sets = 3,
}) {
  final Uint8List payload = Uint8List(14);
  ByteData.sublistView(payload)
    ..setUint64(0, 123456, Endian.little)
    ..setUint8(8, 1)
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

WorkoutHistoryEntry _entry({
  String id = 'entry-1',
  DateTime? startedAt,
  DateTime? endedAt,
  int reps = 12,
  double vo2Avg = 38,
  int rpeAvg = 6,
  WorkoutRecommendationInput? recommendationInput,
}) {
  final DateTime start = startedAt ?? DateTime(2026, 1, 1, 10);
  final DateTime end = endedAt ?? DateTime(2026, 1, 1, 10, 12);
  return WorkoutHistoryEntry(
    id: id,
    profileId: _kaiProfile.id,
    profileName: _kaiProfile.displayName,
    startedAt: start,
    endedAt: end,
    duration: end.difference(start),
    totalMovementCount: 1,
    movements: <MovementSummary>[
      MovementSummary.fromProtocol(movementId: 1, reps: reps, sets: 3),
    ],
    vo2Min: 30,
    vo2Max: 44,
    vo2Avg: vo2Avg,
    vo2SampleCount: 8,
    rpeMin: 4,
    rpeMax: 8,
    rpeAvg: rpeAvg,
    rpeSampleCount: 8,
    loadStatus: 0,
    recommendationInput: recommendationInput,
  );
}

Future<DeviceProtocolSession> _seedLiveSession(_FakeWriter writer) async {
  final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
  await session.handleDataEvent(
    _bleDataEvent(DeviceMessageType.classifierResult, 1, _classifierPayload()),
  );
  await session.handleDataEvent(
    _bleDataEvent(DeviceMessageType.vo2Prediction, 2, _vo2Payload(42.5)),
  );
  return session;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgetsWithSemantics(
    'new profile validates, persists, and enters BLE connection',
    (WidgetTester tester) async {
      final _FakeWritableReceiverTransport transport =
          _FakeWritableReceiverTransport();
      addTearDown(transport.eventController.close);

      await _pumpTall(tester, Vo2MotionApp(transportFactory: (_) => transport));

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('建立使用者'), findsOneWidget);
      _expectSemanticTap(tester, '儲存並連接 BLE', enabled: true);

      await tester.tap(find.text('儲存並連接 BLE'));
      await tester.pump();
      expect(find.text('請填寫此欄位'), findsAtLeastNWidgets(1));
      expect(find.byType(ConnectionScreen), findsNothing);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        _kaiProfile.displayName,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '180');
      await tester.enterText(find.byType(TextFormField).at(2), '75');
      await tester.enterText(find.byType(TextFormField).at(3), '35');
      await tester.tap(find.text('女'));
      await tester.pump();
      await tester.tap(find.text('男'));
      await tester.enterText(find.byType(TextFormField).at(4), '44');
      await tester.tap(find.text('儲存並連接 BLE'));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(find.text('裝置連線'), findsWidgets);
      expect(find.text(_kaiProfile.displayName), findsOneWidget);
      _expectSemanticTap(tester, '重新整理', enabled: true);

      final UserProfile selected = await UserProfile.loadSelectedProfile();
      expect(selected.displayName, _kaiProfile.displayName);
      expect(selected.sex, UserSex.male);
      expect(selected.vo2Max, 44);
    },
  );

  testWidgetsWithSemantics(
    'existing profile selection uses seeded preferences',
    (WidgetTester tester) async {
      const UserProfile lina = UserProfile(
        id: 'lina',
        displayName: 'Lina 長名字測試',
        heightCm: 168,
        weightKg: 58,
        age: 29,
        sex: UserSex.female,
        vo2Max: 47,
      );
      final _FakeWritableReceiverTransport transport =
          _FakeWritableReceiverTransport();
      addTearDown(transport.eventController.close);
      await UserProfile.saveProfiles(<UserProfile>[_kaiProfile, lina]);
      await UserProfile.saveSelectedProfileId(lina.id);

      await _pumpTall(tester, Vo2MotionApp(transportFactory: (_) => transport));

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('選擇使用者'), findsOneWidget);
      _expectSemanticTap(tester, RegExp('Kai 測試.*180 cm'), enabled: true);
      _expectSemanticTap(tester, '使用此資料連接 BLE', enabled: true);

      await tester.tap(find.text(_kaiProfile.displayName));
      await tester.pump();
      await tester.tap(find.text('使用此資料連接 BLE'));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(find.text(_kaiProfile.displayName), findsOneWidget);
      final UserProfile selected = await UserProfile.loadSelectedProfile();
      expect(selected.id, _kaiProfile.id);
    },
  );

  testWidgetsWithSemantics(
    'fake BLE connect writes profile and enters calibration route',
    (WidgetTester tester) async {
      final _FakeWritableReceiverTransport transport =
          _FakeWritableReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: transport,
      );
      addTearDown(() async {
        await controller.disposeAsync();
        await transport.eventController.close();
        session.dispose();
      });

      await _pumpTall(
        tester,
        _wrap(
          ConnectionScreen(
            connectionController: controller,
            transportKind: ReceiverTransportKind.ble,
            protocolSession: session,
            profile: _kaiProfile,
          ),
          routes: <String, WidgetBuilder>{
            CalibrationScreen.routeName: (_) => CalibrationScreen(
              protocolSession: session,
              profile: _kaiProfile,
            ),
          },
        ),
      );

      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(find.text(transport.deviceName), findsOneWidget);
      _expectSemanticTap(tester, RegExp(transport.deviceName), enabled: true);

      await tester.tap(find.text(transport.deviceName));
      await tester.pumpAndSettle();

      expect(find.byType(CalibrationScreen), findsOneWidget);
      expect(find.text('30 秒靜止校正'), findsOneWidget);
      expect(transport.writtenFrames, isNotEmpty);
      expect(
        transport.writtenFrames.first.messageType,
        DeviceMessageType.profile,
      );
      expect(transport.writtenFrames.first.payload.last, _kaiProfile.vo2Max);
    },
  );

  testWidgetsWithSemantics(
    'calibration start updates progress and routes to live workout',
    (WidgetTester tester) async {
      final _FakeWriter writer = _FakeWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
      );
      addTearDown(session.dispose);

      await _pumpTall(
        tester,
        _wrap(
          CalibrationScreen(protocolSession: session, profile: _kaiProfile),
          routes: <String, WidgetBuilder>{
            LiveFitnessPage.routeName: (_) =>
                LiveFitnessPage(protocolSession: session, profile: _kaiProfile),
          },
        ),
      );

      expect(find.byType(CalibrationScreen), findsOneWidget);
      _expectSemanticTap(tester, '開始校正', enabled: true);
      _expectSemanticTap(tester, '跳過校正', enabled: true);

      await tester.tap(find.text('開始校正'));
      await tester.pump();

      expect(writer.writtenFrames, hasLength(2));
      expect(writer.writtenFrames[0].messageType, DeviceMessageType.profile);
      expect(
        writer.writtenFrames[1].messageType,
        DeviceMessageType.calibrationStart,
      );
      expect(find.text('校正中，請保持靜止...'), findsOneWidget);

      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.calibrationProgress,
          3,
          _calibrationProgressPayload(elapsedMs: 15000, hrEstimate: 72),
        ),
      );
      await tester.pump();
      expect(find.text('已進行 15 秒'), findsOneWidget);
      expect(find.text('心率估計：72 bpm'), findsOneWidget);

      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.calibrationDone,
          4,
          _calibrationDonePayload(),
        ),
      );
      await tester.pump();
      expect(find.text('校正完成！'), findsOneWidget);
      expect(find.text('品質分數：92'), findsOneWidget);
      expect(find.text('樣本數：128'), findsOneWidget);
      _expectSemanticTap(tester, '開始即時訓練', enabled: true);

      await tester.tap(find.text('開始即時訓練'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveFitnessPage), findsOneWidget);
    },
  );

  testWidgetsWithSemantics(
    'calibration skip writes command and no-writer boundary disables controls',
    (WidgetTester tester) async {
      final _FakeWriter writer = _FakeWriter();
      final DeviceProtocolSession writableSession = DeviceProtocolSession(
        writer: writer,
      );
      addTearDown(writableSession.dispose);

      await _pumpTall(
        tester,
        _wrap(
          CalibrationScreen(
            protocolSession: writableSession,
            profile: _kaiProfile,
          ),
          routes: <String, WidgetBuilder>{
            LiveFitnessPage.routeName: (_) => LiveFitnessPage(
              protocolSession: writableSession,
              profile: _kaiProfile,
            ),
          },
        ),
      );

      await tester.tap(find.text('跳過校正'));
      await tester.pumpAndSettle();

      expect(writer.writtenFrames, hasLength(1));
      expect(
        writer.writtenFrames.single.messageType,
        DeviceMessageType.fitnessCommand,
      );
      expect(
        writer.writtenFrames.single.payload.first,
        FitnessCommand.skipCalibration.value,
      );
      expect(find.byType(LiveFitnessPage), findsOneWidget);

      final DeviceProtocolSession readOnlySession = DeviceProtocolSession();
      addTearDown(readOnlySession.dispose);
      await _pumpTall(
        tester,
        _wrap(
          CalibrationScreen(
            protocolSession: readOnlySession,
            profile: _kaiProfile,
          ),
        ),
      );

      expect(find.byType(CalibrationScreen), findsOneWidget);
      expect(
        find.textContaining('需要可寫入的 DeviceProtocolSession'),
        findsOneWidget,
      );
      expect(
        find.text('跳過校正也必須透過 BLE fitness command 傳送，現在無法使用。'),
        findsOneWidget,
      );
      _expectSemanticTap(tester, '開始校正', enabled: false);
      _expectSemanticTap(tester, '跳過校正', enabled: false);
    },
  );

  testWidgetsWithSemantics(
    'live workout writes commands, waits for summary, and diagnostics does not save',
    (WidgetTester tester) async {
      final _FakeWriter writer = _FakeWriter();
      final DeviceProtocolSession session = await _seedLiveSession(writer);
      const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
      final _FakeReceiverTransport diagnosticsTransport =
          _FakeReceiverTransport();
      final ReceiverConnectionController diagnosticsController =
          ReceiverConnectionController(transport: diagnosticsTransport);
      addTearDown(() async {
        await diagnosticsController.disposeAsync();
        await diagnosticsTransport.eventController.close();
        session.dispose();
      });

      await _pumpTall(
        tester,
        _wrap(
          LiveFitnessPage(
            protocolSession: session,
            profile: _kaiProfile,
            historyRepository: repository,
          ),
          routes: <String, WidgetBuilder>{
            DashboardPage.routeName: (_) => DashboardPage(
              connectionController: diagnosticsController,
              protocolSession: session,
              profile: _kaiProfile,
            ),
            WorkoutReviewPage.routeName: (_) => const WorkoutReviewPage(),
          },
        ),
      );

      expect(find.byType(LiveFitnessPage), findsOneWidget);
      expect(find.text('啞鈴二頭彎舉'), findsOneWidget);
      expect(find.text('42.5'), findsOneWidget);
      _expectSemanticTap(tester, '開始訓練', enabled: true);
      _expectSemanticTap(tester, '結束並查看回顧', enabled: false);

      await tester.tap(find.text('診斷'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('BLE protocol monitoring'), findsOneWidget);
      expect(await repository.load(), isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('開始訓練'));
      await tester.pump();
      expect(
        writer.writtenFrames.single.payload.first,
        FitnessCommand.startWorkout.value,
      );
      _expectSemanticTap(tester, '開始訓練', enabled: false);
      _expectSemanticTap(tester, '結束並查看回顧', enabled: true);

      await tester.tap(find.text('結束並查看回顧'));
      await tester.pump();
      expect(writer.writtenFrames, hasLength(2));
      expect(
        writer.writtenFrames[1].payload.first,
        FitnessCommand.endWorkout.value,
      );
      expect(find.text('等待手環摘要'), findsOneWidget);
      expect(await repository.load(), isEmpty);

      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.workoutSummary, 3, _summaryPayload()),
      );
      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.workoutSummary, 4, _summaryPayload()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutReviewPage), findsOneWidget);
      expect(find.text('訓練回顧'), findsOneWidget);
      final List<WorkoutHistoryEntry> entries = await repository.load();
      expect(entries, hasLength(1));
      expect(entries.single.vo2Avg, closeTo(38, 0.001));
    },
  );

  testWidgetsWithSemantics(
    'live workout fallback saves only after ten seconds',
    (WidgetTester tester) async {
      final _FakeWriter writer = _FakeWriter();
      final DeviceProtocolSession session = await _seedLiveSession(writer);
      const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
      addTearDown(session.dispose);

      await _pumpTall(
        tester,
        _wrap(
          LiveFitnessPage(
            protocolSession: session,
            profile: _kaiProfile,
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
      await tester.pump(const Duration(seconds: 8));
      expect(find.byType(WorkoutReviewPage), findsNothing);
      expect(await repository.load(), isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(
        writer.writtenFrames[0].payload.first,
        FitnessCommand.startWorkout.value,
      );
      expect(
        writer.writtenFrames[1].payload.first,
        FitnessCommand.endWorkout.value,
      );
      expect(find.byType(WorkoutReviewPage), findsOneWidget);
      final List<WorkoutHistoryEntry> entries = await repository.load();
      expect(entries, hasLength(1));
      expect(entries.single.vo2Avg, closeTo(42.5, 0.001));
    },
  );

  testWidgetsWithSemantics(
    'history rows and review CTAs navigate through review, live, history, and home',
    (WidgetTester tester) async {
      const WorkoutHistoryRepository repository = WorkoutHistoryRepository();
      final _FakeWriter writer = _FakeWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
      );
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);
      addTearDown(() async {
        session.dispose();
        await controller.disposeAsync();
        await transport.eventController.close();
      });

      await _pumpTall(tester, _wrap(const HistoryPage()));
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.text('還沒有訓練紀錄'), findsOneWidget);

      final WorkoutHistoryEntry older = _entry(
        id: 'older',
        endedAt: DateTime(2026, 1, 1, 10, 12),
        reps: 8,
        vo2Avg: 35,
      );
      final WorkoutHistoryEntry latest = _entry(
        id: 'latest',
        startedAt: DateTime(2026, 1, 2, 10),
        endedAt: DateTime(2026, 1, 2, 10, 12),
        reps: 12,
        vo2Avg: 38,
        recommendationInput: const WorkoutRecommendationInput(
          recommendationStatus: 1,
          hasLowRpeInterval: false,
          hasHighRpeInterval: true,
          loadStatus: 0,
          vo2Trend: 0,
          lowRpeTotalMs: 0,
          highRpeTotalMs: 30000,
        ),
      );
      await repository.saveAll(<WorkoutHistoryEntry>[older, latest]);

      await _pumpTall(
        tester,
        _wrap(
          const HistoryPage(),
          routes: <String, WidgetBuilder>{
            WorkoutReviewPage.routeName: (_) => const WorkoutReviewPage(),
            LiveFitnessPage.routeName: (_) =>
                LiveFitnessPage(protocolSession: session, profile: _kaiProfile),
            TrainingHomeScreen.routeName: (_) => TrainingHomeScreen(
              connectionController: controller,
              protocolSession: session,
              profile: _kaiProfile,
            ),
            HistoryPage.routeName: (_) => const HistoryPage(),
          },
        ),
      );

      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.text('VO2 趨勢'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('VO2 趨勢圖.*最近 2 堂訓練')),
        findsOneWidget,
      );
      expect(find.textContaining('12 下'), findsOneWidget);
      _expectSemanticTap(tester, RegExp('12 分 0 秒.*12 下'), enabled: true);

      await tester.tap(find.textContaining('12 下').first);
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutReviewPage), findsOneWidget);
      expect(find.text('教練建議'), findsOneWidget);
      expect(find.textContaining('強度偏高'), findsOneWidget);
      _expectSemanticTap(tester, '查看歷史', enabled: true);
      _expectSemanticTap(tester, '再練一組', enabled: true);
      _expectSemanticTap(tester, '回首頁', enabled: true);

      await tester.tap(find.text('查看歷史'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('再練一組'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveFitnessPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('回首頁'));
      await tester.pumpAndSettle();
      expect(find.byType(TrainingHomeScreen), findsOneWidget);
    },
  );
}

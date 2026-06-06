import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/app.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/user_profile.dart';

class _FakeReceiverTransport implements ReceiverTransport {
  _FakeReceiverTransport();

  final StreamController<ReceiverTransportEvent> eventController =
      StreamController<ReceiverTransportEvent>.broadcast();
  final ReceiverTransportKind transportKind = ReceiverTransportKind.ble;
  final String deviceName = DeviceBleUuids.advertisedName;
  final String deviceId = 'ble-1';
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
    return <ReceiverDeviceInfo>[
      ReceiverDeviceInfo(
        name: deviceName,
        id: deviceId,
        transportKind: transportKind,
      ),
    ];
  }

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<bool> requestPermissions() async => true;
}

class _FakeWritableReceiverTransport extends _FakeReceiverTransport
    implements DeviceProtocolFrameWriter {
  final List<DeviceFrame> writtenFrames = <DeviceFrame>[];

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    writtenFrames.add(frame);
  }
}

class _FakeDeviceProtocolFrameWriter implements DeviceProtocolFrameWriter {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('default app starts with user creation and BLE transport', (
    WidgetTester tester,
  ) async {
    final List<ReceiverTransportKind> requestedKinds = <ReceiverTransportKind>[];

    await _pumpTall(
      tester,
      Vo2MotionApp(
        transportFactory: (ReceiverTransportKind kind) {
          requestedKinds.add(kind);
          return _FakeWritableReceiverTransport();
        },
      ),
    );

    expect(requestedKinds, <ReceiverTransportKind>[ReceiverTransportKind.ble]);
    expect(find.text('先選擇使用者'), findsOneWidget);
    expect(find.text('建立使用者'), findsOneWidget);
    expect(find.text('儲存並連接 BLE'), findsOneWidget);
    expect(find.textContaining('Classic'), findsNothing);
  });

  testWidgets('creating a user navigates to BLE connection', (
    WidgetTester tester,
  ) async {
    await _pumpTall(
      tester,
      Vo2MotionApp(
        transportFactory: (_) {
          return _FakeWritableReceiverTransport();
        },
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Kai');
    await tester.enterText(find.byType(TextFormField).at(1), '180');
    await tester.enterText(find.byType(TextFormField).at(2), '75');
    await tester.enterText(find.byType(TextFormField).at(3), '35');
    await tester.enterText(find.byType(TextFormField).at(4), '44');
    await tester.tap(find.text('儲存並連接 BLE'));
    await tester.pumpAndSettle();

    expect(find.text('裝置連線'), findsWidgets);
    expect(find.text('BLE protocol'), findsOneWidget);
    expect(find.text('Kai'), findsOneWidget);

    final UserProfile selected = await UserProfile.loadSelectedProfile();
    expect(selected.displayName, 'Kai');
    expect(selected.vo2Max, 44);
  });

  testWidgets('BLE connection sends profile and enters calibration', (
    WidgetTester tester,
  ) async {
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
          profile: const UserProfile(
            id: 'kai',
            displayName: 'Kai',
            heightCm: 180,
            weightKg: 75,
            age: 35,
            sex: UserSex.male,
            vo2Max: 44,
          ),
        ),
        routes: <String, WidgetBuilder>{
          CalibrationScreen.routeName: (_) => CalibrationScreen(
            protocolSession: session,
            profile: const UserProfile(
              id: 'kai',
              displayName: 'Kai',
              heightCm: 180,
              weightKg: 75,
              age: 35,
              sex: UserSex.male,
              vo2Max: 44,
            ),
          ),
        },
      ),
    );

    await tester.tap(find.text('開始接收資料'));
    await tester.pumpAndSettle();

    expect(find.text('30 秒靜止校正'), findsOneWidget);
    expect(transport.writtenFrames, isNotEmpty);
    expect(transport.writtenFrames.first.messageType, DeviceMessageType.profile);
    expect(transport.writtenFrames.first.payload.last, 44);
  });

  testWidgets('calibration skip sends fitness command and opens monitoring', (
    WidgetTester tester,
  ) async {
    final _FakeDeviceProtocolFrameWriter writer =
        _FakeDeviceProtocolFrameWriter();
    final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
    addTearDown(session.dispose);

    await _pumpTall(
      tester,
      _wrap(
        CalibrationScreen(
          protocolSession: session,
          profile: const UserProfile(
            id: 'kai',
            displayName: 'Kai',
            heightCm: 180,
            weightKg: 75,
            age: 35,
            sex: UserSex.male,
          ),
        ),
        routes: <String, WidgetBuilder>{
          DashboardPage.routeName: (_) => DashboardPage(
            protocolSession: session,
            profile: const UserProfile(
              id: 'kai',
              displayName: 'Kai',
              heightCm: 180,
              weightKg: 75,
              age: 35,
              sex: UserSex.male,
            ),
          ),
        },
      ),
    );

    await tester.tap(find.text('跳過校正'));
    await tester.pumpAndSettle();

    expect(writer.writtenFrames, hasLength(1));
    expect(writer.writtenFrames.single.messageType, DeviceMessageType.fitnessCommand);
    expect(writer.writtenFrames.single.payload.first, FitnessCommand.skipCalibration.value);
    expect(find.text('BLE protocol monitoring'), findsOneWidget);
  });

  testWidgets('calibration start sends selected profile and calibration command', (
    WidgetTester tester,
  ) async {
    final _FakeDeviceProtocolFrameWriter writer =
        _FakeDeviceProtocolFrameWriter();
    final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
    addTearDown(session.dispose);

    await _pumpTall(
      tester,
      _wrap(
        CalibrationScreen(
          protocolSession: session,
          profile: const UserProfile(
            id: 'kai',
            displayName: 'Kai',
            heightCm: 180,
            weightKg: 75,
            age: 35,
            sex: UserSex.female,
            vo2Max: 45,
          ),
        ),
      ),
    );

    await tester.tap(find.text('開始校正'));
    await tester.pump();

    expect(writer.writtenFrames, hasLength(2));
    expect(writer.writtenFrames[0].messageType, DeviceMessageType.profile);
    expect(writer.writtenFrames[0].payload[5], 1);
    expect(writer.writtenFrames[0].payload[6], 45);
    expect(writer.writtenFrames[1].messageType, DeviceMessageType.calibrationStart);
  });

  testWidgets('dashboard renders protocol-only empty state before data', (
    WidgetTester tester,
  ) async {
    final DeviceProtocolSession session = DeviceProtocolSession();
    addTearDown(session.dispose);

    await _pumpTall(tester, _wrap(DashboardPage(protocolSession: session)));

    expect(find.text('BLE protocol monitoring'), findsOneWidget);
    expect(find.text('等待 BLE protocol data'), findsWidgets);
    expect(find.textContaining('已接收樣本'), findsNothing);
    expect(find.textContaining('動作品質'), findsNothing);
    expect(find.textContaining('疲勞指標'), findsNothing);
    expect(find.textContaining('PPG 波形'), findsNothing);
  });

  testWidgets('dashboard renders exact BLE protocol values', (
    WidgetTester tester,
  ) async {
    final DeviceProtocolSession session = DeviceProtocolSession();
    addTearDown(session.dispose);

    await _pumpTall(tester, _wrap(DashboardPage(protocolSession: session)));

    final Uint8List predictionPayload = Uint8List(12);
    ByteData.sublistView(predictionPayload)
      ..setUint64(0, 123456789, Endian.little)
      ..setFloat32(8, 42.5, Endian.little);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.vo2Prediction, 1, predictionPayload),
    );

    final Uint8List appStatusPayload = Uint8List(9);
    ByteData.sublistView(appStatusPayload)
      ..setUint8(0, 1)
      ..setUint8(1, 2)
      ..setUint8(2, 3)
      ..setUint8(3, 1)
      ..setUint8(4, 4)
      ..setUint8(5, 100)
      ..setUint16(6, 0, Endian.little)
      ..setUint8(8, 1);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.appStatus, 2, appStatusPayload),
    );

    await session.handleDataEvent(
      _bleDataEvent(
        DeviceMessageType.healthResponse,
        3,
        Uint8List.fromList(<int>[0x03]),
      ),
    );

    final List<int> alertMessage = utf8.encode('slow down');
    final Uint8List rpeAlertPayload = Uint8List(16 + alertMessage.length);
    ByteData.sublistView(rpeAlertPayload)
      ..setUint64(0, 22334455, Endian.little)
      ..setUint8(8, 2)
      ..setUint8(9, 9)
      ..setUint32(10, 45000, Endian.little)
      ..setUint16(14, alertMessage.length, Endian.little);
    rpeAlertPayload.setRange(16, rpeAlertPayload.length, alertMessage);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.rpe, 4, rpeAlertPayload),
    );

    final Uint8List workoutSummaryPayload = Uint8List(77);
    ByteData.sublistView(workoutSummaryPayload)
      ..setUint64(16, 8000, Endian.little)
      ..setUint8(24, 5)
      ..setFloat32(57, 30.0, Endian.little)
      ..setFloat32(61, 44.0, Endian.little)
      ..setFloat32(65, 37.5, Endian.little)
      ..setUint16(69, 12, Endian.little)
      ..setUint8(73, 7)
      ..setUint16(74, 3, Endian.little);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.workoutSummary, 5, workoutSummaryPayload),
    );

    final Uint8List recommendationPayload = Uint8List(13);
    ByteData.sublistView(recommendationPayload)
      ..setUint8(0, 1)
      ..setUint8(1, 1)
      ..setUint8(2, 0)
      ..setUint8(3, 2)
      ..setUint8(4, 0)
      ..setUint32(5, 12000, Endian.little)
      ..setUint32(9, 0, Endian.little);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.recommendationInput, 6, recommendationPayload),
    );

    await tester.pump();

    expect(find.text('42.5'), findsOneWidget);
    expect(find.text('cal 100%'), findsOneWidget);
    expect(find.text('VO2 on'), findsOneWidget);
    expect(find.text('slow down'), findsOneWidget);
    expect(find.text('VO2 avg 37.5'), findsOneWidget);
    expect(find.text('RPE avg 7'), findsOneWidget);
    expect(find.text('low RPE true'), findsOneWidget);
  });

  testWidgets('dashboard protocol controls write fitness commands', (
    WidgetTester tester,
  ) async {
    final _FakeDeviceProtocolFrameWriter writer =
        _FakeDeviceProtocolFrameWriter();
    final DeviceProtocolSession session = DeviceProtocolSession(writer: writer);
    addTearDown(session.dispose);

    await _pumpTall(tester, _wrap(DashboardPage(protocolSession: session)));

    await tester.tap(find.text('Request status'));
    await tester.pump();
    await tester.tap(find.text('Start workout'));
    await tester.pump();
    await tester.tap(find.text('End workout'));
    await tester.pump();

    expect(writer.writtenFrames, hasLength(3));
    expect(writer.writtenFrames[0].payload.first, FitnessCommand.requestStatus.value);
    expect(writer.writtenFrames[1].payload.first, FitnessCommand.startWorkout.value);
    expect(writer.writtenFrames[2].payload.first, FitnessCommand.endWorkout.value);
  });
}

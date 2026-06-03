import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/onboarding_screen.dart';
import 'package:vo2_flutter/user_profile.dart';

class _FakeReceiverTransport implements ReceiverTransport {
  final StreamController<ReceiverTransportEvent> eventController =
      StreamController<ReceiverTransportEvent>.broadcast();

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<ReceiverTransportEvent> events() => eventController.stream;

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() async {
    return const <ReceiverDeviceInfo>[
      ReceiverDeviceInfo(
        name: 'Test Sensor',
        id: 'AA:BB',
        transportKind: ReceiverTransportKind.classicBluetooth,
      ),
    ];
  }

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<bool> requestPermissions() async => true;
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

ReceiverConnectionController _connectionController() {
  return ReceiverConnectionController(transport: _FakeReceiverTransport());
}

void main() {
  Widget wrap(Widget child, {Map<String, WidgetBuilder>? routes}) {
    return MaterialApp(
      home: child,
      routes: routes ?? <String, WidgetBuilder>{},
    );
  }

  testWidgets('onboarding screen renders and navigates forward', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: <String, WidgetBuilder>{
          OnboardingScreen.routeName: (_) => const OnboardingScreen(),
          ConnectionScreen.routeName: (_) =>
              ConnectionScreen(connectionController: _connectionController()),
        },
        initialRoute: OnboardingScreen.routeName,
      ),
    );

    expect(find.text('個人資料設定'), findsNWidgets(2));
    await tester.tap(find.text('前往裝置連線'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('藍牙連線'), findsOneWidget);
  });

  testWidgets('connection screen renders and navigates forward', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: <String, WidgetBuilder>{
          ConnectionScreen.routeName: (_) =>
              ConnectionScreen(connectionController: _connectionController()),
          CalibrationScreen.routeName: (_) => const CalibrationScreen(),
        },
        initialRoute: ConnectionScreen.routeName,
      ),
    );

    expect(find.text('藍牙連線'), findsOneWidget);
    await tester.tap(find.text('稍後校正'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('30 秒靜止校正'), findsOneWidget);
  });

  group('CalibrationScreen', () {
    testWidgets('initial state renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const CalibrationScreen()));
      expect(find.text('30 秒靜止校正'), findsOneWidget);
      expect(find.text('開始校正'), findsOneWidget);
      expect(find.text('回到即時監測首頁'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('starts calibration and shows countdown', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(const CalibrationScreen()));

      await tester.tap(find.text('開始校正'));
      await tester.pump(); // trigger setState

      expect(find.text('開始校正'), findsNothing);
      expect(find.text('剩餘 30 秒'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('剩餘 29 秒'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15));
      expect(find.text('剩餘 14 秒'), findsOneWidget);

      // Cleanup the timer by advancing to completion
      await tester.pump(const Duration(seconds: 14));
    });

    testWidgets('completes calibration and navigates to dashboard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: <String, WidgetBuilder>{
            CalibrationScreen.routeName: (_) => const CalibrationScreen(),
            DashboardPage.routeName: (_) =>
                const Scaffold(body: Text('Dashboard')),
          },
          initialRoute: CalibrationScreen.routeName,
        ),
      );

      // Start
      await tester.tap(find.text('開始校正'));
      await tester.pump();

      // Fast forward 30 seconds
      await tester.pump(const Duration(seconds: 30));

      expect(find.text('校正完成！'), findsOneWidget);
      expect(find.text('回到即時監測首頁'), findsOneWidget);

      // Navigate
      await tester.tap(find.text('回到即時監測首頁'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('protocol mode sends profile and calibration command', (
      WidgetTester tester,
    ) async {
      final _FakeDeviceProtocolFrameWriter writer =
          _FakeDeviceProtocolFrameWriter();
      const UserProfile profile = UserProfile(
        heightCm: 180,
        weightKg: 75,
        age: 35,
        sex: UserSex.female,
      );
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
        initialProfile: profile,
      );

      await tester.pumpWidget(
        wrap(CalibrationScreen(protocolSession: session, profile: profile)),
      );

      await tester.tap(find.text('開始校正'));
      await tester.pump();

      expect(writer.writtenFrames, hasLength(2));
      expect(writer.writtenFrames[0].messageType, DeviceMessageType.profile);
      expect(writer.writtenFrames[0].payload[5], 1);
      expect(
        writer.writtenFrames[1].messageType,
        DeviceMessageType.calibrationStart,
      );
      expect(find.text('校正中，請保持靜止...'), findsOneWidget);
    });

    testWidgets('protocol mode displays calibration progress', (
      WidgetTester tester,
    ) async {
      final _FakeDeviceProtocolFrameWriter writer =
          _FakeDeviceProtocolFrameWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
      );
      final Uint8List progressPayload = Uint8List(5);
      ByteData.sublistView(progressPayload)
        ..setUint32(0, 15000, Endian.little)
        ..setUint8(4, 78);

      await tester.pumpWidget(
        wrap(CalibrationScreen(protocolSession: session)),
      );
      await tester.tap(find.text('開始校正'));
      await tester.pump();

      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.calibrationProgress,
          1,
          progressPayload,
        ),
      );
      await tester.pump();

      expect(find.text('已進行 15 秒'), findsOneWidget);
      expect(find.text('心率估計：78 bpm'), findsOneWidget);
    });

    testWidgets('protocol mode displays calibration result', (
      WidgetTester tester,
    ) async {
      final _FakeDeviceProtocolFrameWriter writer =
          _FakeDeviceProtocolFrameWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
      );
      final Uint8List donePayload = Uint8List(9);
      ByteData.sublistView(donePayload)
        ..setUint8(0, 64)
        ..setUint8(1, 88)
        ..setUint16(2, 240, Endian.little)
        ..setUint32(4, 30000, Endian.little)
        ..setUint8(8, 0);

      await tester.pumpWidget(
        wrap(CalibrationScreen(protocolSession: session)),
      );
      await tester.tap(find.text('開始校正'));
      await tester.pump();

      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.calibrationDone, 2, donePayload),
      );
      await tester.pump();

      expect(find.text('校正完成！'), findsOneWidget);
      expect(find.text('品質分數：88'), findsOneWidget);
      expect(find.text('樣本數：240'), findsOneWidget);
    });
  });

  group('DashboardPage', () {
    testWidgets('Classic CSV updates sample count', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      await tester.pumpWidget(
        wrap(DashboardPage(connectionController: controller)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      transport.eventController.add(
        const ReceiverDataEvent(
          payload: '1,2,3,4,100,200,300,400,500,0.1,0.2,0.3,1.1,1.2,1.3',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('已接收樣本：1'), findsOneWidget);
    });

    testWidgets('BLE JSON does not trigger CSV parse error', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      await tester.pumpWidget(
        wrap(DashboardPage(connectionController: controller)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final String jsonPayload = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.sensorPpgImu,
        'flags': 0,
        'seq': 1,
        'payloadBase64': base64Encode(Uint8List(0)),
      });

      transport.eventController.add(ReceiverDataEvent(payload: jsonPayload));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('已收到原始資料，但格式尚未解析成功。'), findsNothing);
      expect(find.text('已接收樣本：0'), findsOneWidget);
    });

    testWidgets('displays injected protocol VO2 prediction when available', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);
      final DeviceProtocolSession session = DeviceProtocolSession();
      final Uint8List predictionPayload = Uint8List(12);
      ByteData.sublistView(predictionPayload)
        ..setUint64(0, 123456789, Endian.little)
        ..setFloat32(8, 42.5, Endian.little);

      await tester.pumpWidget(
        wrap(
          DashboardPage(
            connectionController: controller,
            protocolSession: session,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      transport.eventController.add(
        const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('開始訓練'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 10));

      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.vo2Prediction, 1, predictionPayload),
      );
      await tester.pump();

      expect(find.text('VO2 42.5'), findsOneWidget);
      expect(find.text('已接收樣本：0'), findsOneWidget);
    });
  });
}

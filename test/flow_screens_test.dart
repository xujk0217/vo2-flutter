import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/onboarding_screen.dart';

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
  });
}

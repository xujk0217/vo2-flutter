import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _FakeReceiverTransport({
    this.transportKind = ReceiverTransportKind.classicBluetooth,
    this.deviceName = 'Test Sensor',
    this.deviceId = 'AA:BB',
  });

  final StreamController<ReceiverTransportEvent> eventController =
      StreamController<ReceiverTransportEvent>.broadcast();
  final ReceiverTransportKind transportKind;
  final String deviceName;
  final String deviceId;
  final Completer<void> disconnectedCompleter = Completer<void>();
  bool disconnected = false;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {
    disconnected = true;
    if (!disconnectedCompleter.isCompleted) {
      disconnectedCompleter.complete();
    }
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
  _FakeWritableReceiverTransport()
    : super(
        transportKind: ReceiverTransportKind.ble,
        deviceName: DeviceBleUuids.advertisedName,
        deviceId: 'ble-1',
      );

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

  group('Vo2MotionApp transport selection', () {
    testWidgets('uses Classic Bluetooth by default', (
      WidgetTester tester,
    ) async {
      final List<ReceiverTransportKind> requestedKinds =
          <ReceiverTransportKind>[];

      await tester.pumpWidget(
        Vo2MotionApp(
          initialRoute: ConnectionScreen.routeName,
          transportFactory: (ReceiverTransportKind kind) {
            requestedKinds.add(kind);
            return _FakeReceiverTransport(transportKind: kind);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedKinds, <ReceiverTransportKind>[
        ReceiverTransportKind.classicBluetooth,
      ]);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('BLE'), findsOneWidget);
      expect(find.text('Test Sensor (AA:BB)'), findsOneWidget);
      expect(find.text('BLE 驗證資訊'), findsNothing);
      expect(find.textContaining('協定：'), findsNothing);
    });

    testWidgets('BLE selection rebuilds writable protocol session', (
      WidgetTester tester,
    ) async {
      final _FakeReceiverTransport classicTransport = _FakeReceiverTransport();
      final _FakeWritableReceiverTransport bleTransport =
          _FakeWritableReceiverTransport();
      final List<ReceiverTransportKind> requestedKinds =
          <ReceiverTransportKind>[];

      await tester.pumpWidget(
        Vo2MotionApp(
          initialRoute: ConnectionScreen.routeName,
          transportFactory: (ReceiverTransportKind kind) {
            requestedKinds.add(kind);
            switch (kind) {
              case ReceiverTransportKind.classicBluetooth:
                return classicTransport;
              case ReceiverTransportKind.ble:
                return bleTransport;
            }
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BLE'));
      await tester.pump();
      await tester.runAsync(() {
        return classicTransport.disconnectedCompleter.future;
      });
      await tester.pumpAndSettle();

      expect(requestedKinds, <ReceiverTransportKind>[
        ReceiverTransportKind.classicBluetooth,
        ReceiverTransportKind.ble,
      ]);
      expect(classicTransport.disconnected, isTrue);
      expect(
        find.text('${DeviceBleUuids.advertisedName} (ble-1)'),
        findsOneWidget,
      );

      final Uint8List predictionPayload = Uint8List(12);
      ByteData.sublistView(predictionPayload)
        ..setUint64(0, 123456789, Endian.little)
        ..setFloat32(8, 42.5, Endian.little);
      bleTransport.eventController.add(
        _bleDataEvent(DeviceMessageType.vo2Prediction, 1, predictionPayload),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('協定：0x0030'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('稍後校正'), 200);
      await tester.tap(find.text('稍後校正'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開始校正'));
      await tester.pump();

      expect(bleTransport.writtenFrames, hasLength(2));
      expect(
        bleTransport.writtenFrames[0].messageType,
        DeviceMessageType.profile,
      );
      expect(
        bleTransport.writtenFrames[1].messageType,
        DeviceMessageType.calibrationStart,
      );
    });
  });

  testWidgets('default app renders split-entry home and navigates forward', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      Vo2MotionApp(
        transportFactory: (ReceiverTransportKind kind) {
          return _FakeReceiverTransport(transportKind: kind);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VO2 Motion Monitor'), findsNWidgets(2));
    expect(find.text('基本資料'), findsOneWidget);
    expect(find.text('裝置連線'), findsOneWidget);
    expect(find.text('校正與訓練'), findsOneWidget);
    expect(find.text(UserProfile.defaults.summary), findsOneWidget);
    expect(find.text('BLE 驗證資訊'), findsNothing);
    expect(find.text('之後會在這裡放第一次進入 App 的個人資料流程。'), findsNothing);
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

  testWidgets('connection screen shows BLE diagnostics when BLE is selected', (
    WidgetTester tester,
  ) async {
    final _FakeReceiverTransport transport = _FakeReceiverTransport(
      transportKind: ReceiverTransportKind.ble,
      deviceName: DeviceBleUuids.advertisedName,
      deviceId: 'ble-1',
    );
    final ReceiverConnectionController controller =
        ReceiverConnectionController(transport: transport);
    final DeviceProtocolSession session = DeviceProtocolSession();
    addTearDown(() async {
      await controller.disposeAsync();
      await transport.eventController.close();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionScreen(
          connectionController: controller,
          transportKind: ReceiverTransportKind.ble,
          protocolSession: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    transport.eventController.add(
      const ReceiverStatusEvent(
        state: 'write_complete',
        message: 'BLE write complete.',
      ),
    );
    await tester.pump();
    transport.eventController.add(
      const ReceiverErrorEvent(code: 'gatt_error', message: 'GATT failed.'),
    );
    await tester.pump();

    final Uint8List healthPayload = Uint8List.fromList(<int>[0x01]);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.healthResponse, 1, healthPayload),
    );
    final Uint8List appStatusPayload = Uint8List(9);
    ByteData.sublistView(appStatusPayload)
      ..setUint8(0, 1)
      ..setUint8(1, 2)
      ..setUint8(2, 3)
      ..setUint8(3, 1)
      ..setUint8(4, 4)
      ..setUint8(5, 55)
      ..setUint16(6, 0, Endian.little)
      ..setUint8(8, 1);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.appStatus, 2, appStatusPayload),
    );
    final Uint8List predictionPayload = Uint8List(12);
    ByteData.sublistView(predictionPayload)
      ..setUint64(0, 123456789, Endian.little)
      ..setFloat32(8, 42.5, Endian.little);
    await session.handleDataEvent(
      _bleDataEvent(DeviceMessageType.vo2Prediction, 3, predictionPayload),
    );
    await tester.pump();

    expect(find.text('BLE 驗證資訊'), findsOneWidget);
    expect(find.text('模式：BLE'), findsOneWidget);
    expect(find.text('權限：已允許'), findsOneWidget);
    expect(find.text('藍牙：已開啟'), findsOneWidget);
    expect(find.text('裝置數：1'), findsOneWidget);
    expect(find.text('選擇：ble-1'), findsOneWidget);
    expect(find.text('狀態：write_complete'), findsOneWidget);
    expect(find.text('錯誤：gatt_error'), findsOneWidget);
    expect(find.text('協定：0x0030'), findsOneWidget);
    expect(find.text('健康：VO2 on / Sensor off'), findsOneWidget);
    expect(find.text('App：cal 55% / ready'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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
    testWidgets('settings present warning timing as advanced reminders', (
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

      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();

      expect(find.text('進階提醒'), findsOneWidget);
      expect(find.text('提醒排程：開始後 10 秒'), findsOneWidget);
      expect(find.text('尚未安排提醒'), findsOneWidget);
      expect(find.text('加入提醒排程'), findsOneWidget);
      expect(find.textContaining('警告跳出時間'), findsNothing);
    });

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

    testWidgets('passive protocol messages do not alter dashboard metrics', (
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

      await tester.pumpWidget(
        wrap(
          DashboardPage(
            connectionController: controller,
            protocolSession: session,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final Uint8List workoutSummaryPayload = Uint8List(77);
      ByteData.sublistView(workoutSummaryPayload)
        ..setUint64(0, 1000, Endian.little)
        ..setUint64(8, 2000, Endian.little)
        ..setUint64(16, 1000, Endian.little)
        ..setFloat32(57, 30.0, Endian.little)
        ..setFloat32(61, 31.0, Endian.little)
        ..setFloat32(65, 30.5, Endian.little);
      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.workoutSummary,
          1,
          workoutSummaryPayload,
        ),
      );

      final Uint8List recommendationPayload = Uint8List(13);
      ByteData.sublistView(recommendationPayload)
        ..setUint8(0, 1)
        ..setUint8(1, 1)
        ..setUint8(2, 0)
        ..setUint32(5, 12000, Endian.little)
        ..setUint32(9, 0, Endian.little);
      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.recommendationInput,
          2,
          recommendationPayload,
        ),
      );

      final List<int> alertMessage = utf8.encode('slow down');
      final Uint8List rpeAlertPayload = Uint8List(16 + alertMessage.length);
      ByteData.sublistView(rpeAlertPayload)
        ..setUint64(0, 123456789, Endian.little)
        ..setUint8(8, 2)
        ..setUint8(9, 9)
        ..setUint32(10, 45000, Endian.little)
        ..setUint16(14, alertMessage.length, Endian.little);
      rpeAlertPayload.setRange(16, rpeAlertPayload.length, alertMessage);
      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.rpe, 3, rpeAlertPayload),
      );
      await tester.pump();

      expect(find.text('已接收樣本：0'), findsOneWidget);
      expect(find.text('VO2 42.5'), findsNothing);
      expect(find.text('slow down'), findsNothing);
    });
  });
}

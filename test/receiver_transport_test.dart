import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/bluetooth_bridge.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

class _FakeClassicBridgeClient implements ClassicBridgeClient {
  _FakeClassicBridgeClient({required this.eventStream, required this.devices});

  final Stream<Map<String, dynamic>> eventStream;
  final List<BluetoothDeviceInfo> devices;
  String? connectedAddress;
  bool disconnected = false;

  @override
  Future<void> connect(String address) async {
    connectedAddress = address;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Stream<Map<String, dynamic>> events() => eventStream;

  @override
  Future<List<BluetoothDeviceInfo>> getBondedDevices() async => devices;

  @override
  Future<bool> isBluetoothEnabled() async => true;

  @override
  Future<bool> requestPermissions() async => true;
}

class _FakeBleBridgeClient implements BleBridgeClient {
  final StreamController<Map<String, dynamic>> eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  List<BleDeviceInfo> devices = const <BleDeviceInfo>[];
  bool permissionsGranted = true;
  bool enabled = true;
  String? connectedDeviceId;
  bool disconnected = false;
  List<int>? writtenBytes;

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceId = deviceId;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Stream<Map<String, dynamic>> events() => eventController.stream;

  @override
  Future<bool> isBluetoothEnabled() async => enabled;

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<List<BleDeviceInfo>> scanDevices() async => devices;

  @override
  Future<void> write(List<int> bytes) async {
    writtenBytes = bytes;
  }
}

void main() {
  group('mapClassicBridgeEvent', () {
    test('maps status events', () {
      final ReceiverTransportEvent event = mapClassicBridgeEvent(
        <String, dynamic>{
          'type': 'status',
          'state': 'connected',
          'message': 'Connected.',
        },
      );

      expect(event, isA<ReceiverStatusEvent>());
      expect((event as ReceiverStatusEvent).state, 'connected');
      expect(event.message, 'Connected.');
    });

    test('maps error events', () {
      final ReceiverTransportEvent event = mapClassicBridgeEvent(
        <String, dynamic>{
          'type': 'error',
          'code': 'connect_error',
          'message': 'Failed.',
        },
      );

      expect(event, isA<ReceiverErrorEvent>());
      expect((event as ReceiverErrorEvent).code, 'connect_error');
      expect(event.message, 'Failed.');
    });

    test('maps data events', () {
      final ReceiverTransportEvent event = mapClassicBridgeEvent(
        <String, dynamic>{'type': 'data', 'line': '1,2,3'},
      );

      expect(event, isA<ReceiverDataEvent>());
      expect((event as ReceiverDataEvent).payload, '1,2,3');
    });
  });

  group('ClassicBluetoothTransport', () {
    test('maps bonded devices to receiver devices', () async {
      final _FakeClassicBridgeClient client = _FakeClassicBridgeClient(
        eventStream: const Stream<Map<String, dynamic>>.empty(),
        devices: const <BluetoothDeviceInfo>[
          BluetoothDeviceInfo(name: 'Sensor A', address: 'AA:BB'),
        ],
      );
      final ClassicBluetoothTransport transport = ClassicBluetoothTransport(
        bridgeClient: client,
      );

      final List<ReceiverDeviceInfo> devices = await transport.getDevices();

      expect(devices, hasLength(1));
      expect(devices.first.name, 'Sensor A');
      expect(devices.first.id, 'AA:BB');
      expect(
        devices.first.transportKind,
        ReceiverTransportKind.classicBluetooth,
      );
    });

    test('delegates connect and disconnect to classic client', () async {
      final _FakeClassicBridgeClient client = _FakeClassicBridgeClient(
        eventStream: const Stream<Map<String, dynamic>>.empty(),
        devices: const <BluetoothDeviceInfo>[],
      );
      final ClassicBluetoothTransport transport = ClassicBluetoothTransport(
        bridgeClient: client,
      );

      await transport.connect('AA:BB');
      await transport.disconnect();

      expect(client.connectedAddress, 'AA:BB');
      expect(client.disconnected, isTrue);
    });
  });

  group('BleReceiverTransport', () {
    test(
      'delegates permissions, adapter state, and scan results to BLE client',
      () async {
        final _FakeBleBridgeClient client = _FakeBleBridgeClient()
          ..devices = const <BleDeviceInfo>[
            BleDeviceInfo(name: 'bt_fucktrae_young', id: 'ble-1'),
          ];
        final BleReceiverTransport transport = BleReceiverTransport(
          bridgeClient: client,
        );

        expect(await transport.requestPermissions(), isTrue);
        expect(await transport.isEnabled(), isTrue);
        final List<ReceiverDeviceInfo> devices = await transport.getDevices();

        expect(devices, hasLength(1));
        expect(devices.single.name, DeviceBleUuids.advertisedName);
        expect(devices.single.id, 'ble-1');
        expect(devices.single.transportKind, ReceiverTransportKind.ble);
      },
    );

    test(
      'delegates connect, disconnect, and writeFrame to BLE client',
      () async {
        final _FakeBleBridgeClient client = _FakeBleBridgeClient();
        final BleReceiverTransport transport = BleReceiverTransport(
          bridgeClient: client,
        );

        await transport.connect('ble-1');
        await transport.writeFrame(
          const DeviceFrame(
            messageType: DeviceMessageType.calibrationStart,
            seq: 4,
          ),
        );
        await transport.disconnect();

        expect(client.connectedDeviceId, 'ble-1');
        expect(client.disconnected, isTrue);
        final DeviceFrame writtenFrame = const DeviceProtocolCodec().decode(
          Uint8List.fromList(client.writtenBytes!),
        );
        expect(writtenFrame.messageType, DeviceMessageType.calibrationStart);
        expect(writtenFrame.seq, 4);
      },
    );

    test('maps BLE status and error events', () async {
      final _FakeBleBridgeClient client = _FakeBleBridgeClient();
      final BleReceiverTransport transport = BleReceiverTransport(
        bridgeClient: client,
      );
      final Future<List<ReceiverTransportEvent>> emittedFuture = transport
          .events()
          .take(2)
          .toList();
      await pumpEventQueue();

      client.eventController.add(<String, dynamic>{
        'type': 'status',
        'state': 'connected',
        'message': 'BLE connected.',
      });
      client.eventController.add(<String, dynamic>{
        'type': 'error',
        'code': 'gatt_error',
        'message': 'GATT failed.',
      });

      final List<ReceiverTransportEvent> emitted = await emittedFuture;
      final ReceiverStatusEvent status = emitted[0] as ReceiverStatusEvent;
      final ReceiverErrorEvent error = emitted[1] as ReceiverErrorEvent;

      expect(status.state, 'connected');
      expect(status.message, 'BLE connected.');
      expect(error.code, 'gatt_error');
      expect(error.message, 'GATT failed.');
    });

    test('reassembles split BLE TLV chunks into data event JSON', () async {
      final _FakeBleBridgeClient client = _FakeBleBridgeClient();
      final BleReceiverTransport transport = BleReceiverTransport(
        bridgeClient: client,
      );
      // calibration_progress payload: elapsedMs=5000 (uint32 LE), hrEstimate=75 (uint8)
      const List<int> framePayload = <int>[0x88, 0x13, 0x00, 0x00, 0x4B];
      final Uint8List frame = const DeviceProtocolCodec().encode(
        const DeviceFrame(
          messageType: DeviceMessageType.calibrationProgress,
          seq: 9,
          payload: framePayload,
        ),
      );
      final Future<ReceiverTransportEvent> eventFuture = transport
          .events()
          .first;
      await pumpEventQueue();

      client.eventController.add(<String, dynamic>{
        'type': 'data',
        'chunk': frame.sublist(0, 6),
      });
      client.eventController.add(<String, dynamic>{
        'type': 'data',
        'chunk': frame.sublist(6),
      });

      final ReceiverDataEvent event = await eventFuture as ReceiverDataEvent;
      final Map<String, dynamic> payload =
          jsonDecode(event.payload) as Map<String, dynamic>;

      expect(payload['messageType'], DeviceMessageType.calibrationProgress);
      expect(payload['seq'], 9);
      expect(payload['payloadBase64'], base64Encode(framePayload));

      // Verify the BLE JSON seam is compatible with DeviceProtocolJsonParser.
      final DeviceProtocolJsonResult? parsed =
          DeviceProtocolJsonParser.tryParse(event.payload);
      expect(parsed, isNotNull);
      expect(parsed!.messageType, DeviceMessageType.calibrationProgress);
      expect(parsed.seq, 9);
      expect(parsed.typedPayload, isA<CalibrationProgressPayload>());
      final CalibrationProgressPayload typed =
          parsed.typedPayload as CalibrationProgressPayload;
      expect(typed.elapsedMs, 5000);
      expect(typed.hrEstimate, 75);
    });

    test('emits multiple data events from one BLE chunk', () async {
      final _FakeBleBridgeClient client = _FakeBleBridgeClient();
      final BleReceiverTransport transport = BleReceiverTransport(
        bridgeClient: client,
      );
      final DeviceProtocolCodec codec = const DeviceProtocolCodec();
      final Uint8List first = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.profile, seq: 1),
      );
      final Uint8List second = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.profileAck, seq: 2),
      );
      final Future<List<ReceiverTransportEvent>> emittedFuture = transport
          .events()
          .take(2)
          .toList();
      await pumpEventQueue();

      client.eventController.add(<String, dynamic>{
        'type': 'data',
        'chunk': <int>[...first, ...second],
      });

      final List<ReceiverTransportEvent> emitted = await emittedFuture;

      expect(
        jsonDecode((emitted[0] as ReceiverDataEvent).payload)['messageType'],
        DeviceMessageType.profile,
      );
      expect(
        jsonDecode((emitted[1] as ReceiverDataEvent).payload)['messageType'],
        DeviceMessageType.profileAck,
      );
    });

    test('emits error event for invalid BLE TLV chunk', () async {
      final _FakeBleBridgeClient client = _FakeBleBridgeClient();
      final BleReceiverTransport transport = BleReceiverTransport(
        bridgeClient: client,
      );
      final Future<ReceiverTransportEvent> eventFuture = transport
          .events()
          .first;
      await pumpEventQueue();

      client.eventController.add(<String, dynamic>{
        'type': 'data',
        'chunk': <int>[0, 1, 2, 3, 4, 5, 6, 7],
      });

      final ReceiverErrorEvent error = await eventFuture as ReceiverErrorEvent;
      expect(error.code, 'invalid_ble_frame');
    });
  });
}

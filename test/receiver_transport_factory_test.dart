import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/receiver/receiver_transport_factory.dart';

void main() {
  group('createBleBridgeClient', () {
    test('uses the MethodChannel BLE adapter on macOS', () {
      final BleBridgeClient client = createBleBridgeClient(
        platform: TargetPlatform.macOS,
      );

      expect(client, isA<BleBridgeClientAdapter>());
    });

    test('uses the existing MethodChannel BLE adapter off macOS', () {
      final BleBridgeClient client = createBleBridgeClient(
        platform: TargetPlatform.android,
      );

      expect(client, isA<BleBridgeClientAdapter>());
    });
  });

  group('createReceiverTransport', () {
    test('creates BLE transport through the macOS channel adapter', () {
      final ReceiverTransport transport = createReceiverTransport(
        ReceiverTransportKind.ble,
        platform: TargetPlatform.macOS,
      );

      expect(transport, isA<BleReceiverTransport>());
    });

    test('keeps Classic Bluetooth on the classic transport path', () {
      final ReceiverTransport transport = createReceiverTransport(
        ReceiverTransportKind.classicBluetooth,
        platform: TargetPlatform.macOS,
      );

      expect(transport, isA<ClassicBluetoothTransport>());
    });
  });
}

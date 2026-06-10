import 'package:flutter/foundation.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

ReceiverTransport createReceiverTransport(
  ReceiverTransportKind kind, {
  TargetPlatform? platform,
}) {
  switch (kind) {
    case ReceiverTransportKind.classicBluetooth:
      return ClassicBluetoothTransport();
    case ReceiverTransportKind.ble:
      return BleReceiverTransport(
        bridgeClient: createBleBridgeClient(platform: platform),
      );
  }
}

BleBridgeClient createBleBridgeClient({TargetPlatform? platform}) {
  return const BleBridgeClientAdapter();
}

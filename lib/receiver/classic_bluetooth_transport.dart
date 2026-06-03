import 'package:vo2_flutter/bluetooth_bridge.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

abstract interface class ClassicBridgeClient {
  Stream<Map<String, dynamic>> events();

  Future<bool> requestPermissions();

  Future<bool> isBluetoothEnabled();

  Future<List<BluetoothDeviceInfo>> getBondedDevices();

  Future<void> connect(String address);

  Future<void> disconnect();
}

class BluetoothBridgeClientAdapter implements ClassicBridgeClient {
  BluetoothBridgeClientAdapter([BluetoothBridge? bridge])
    : _bridge = bridge ?? BluetoothBridge();

  final BluetoothBridge _bridge;

  @override
  Stream<Map<String, dynamic>> events() => _bridge.events();

  @override
  Future<List<BluetoothDeviceInfo>> getBondedDevices() {
    return _bridge.getBondedDevices();
  }

  @override
  Future<bool> isBluetoothEnabled() => _bridge.isBluetoothEnabled();

  @override
  Future<void> connect(String address) => _bridge.connect(address);

  @override
  Future<void> disconnect() => _bridge.disconnect();

  @override
  Future<bool> requestPermissions() => _bridge.requestPermissions();
}

ReceiverTransportEvent mapClassicBridgeEvent(Map<String, dynamic> event) {
  final String type = event['type'] as String? ?? '';
  switch (type) {
    case 'status':
      return ReceiverStatusEvent(
        state: event['state'] as String? ?? '',
        message: event['message'] as String? ?? '藍牙狀態更新',
      );
    case 'error':
      return ReceiverErrorEvent(
        code: event['code'] as String? ?? 'unknown_error',
        message: event['message'] as String? ?? '藍牙錯誤',
      );
    case 'data':
      return ReceiverDataEvent(payload: event['line'] as String? ?? '');
    default:
      return ReceiverErrorEvent(
        code: 'unsupported_event',
        message: event['message'] as String? ?? '未支援的接收事件',
      );
  }
}

class ClassicBluetoothTransport implements ReceiverTransport {
  ClassicBluetoothTransport({ClassicBridgeClient? bridgeClient})
    : _client = bridgeClient ?? BluetoothBridgeClientAdapter();

  final ClassicBridgeClient _client;

  @override
  Stream<ReceiverTransportEvent> events() {
    return _client.events().map(mapClassicBridgeEvent);
  }

  @override
  Future<bool> requestPermissions() => _client.requestPermissions();

  @override
  Future<bool> isEnabled() => _client.isBluetoothEnabled();

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() async {
    final List<BluetoothDeviceInfo> devices = await _client.getBondedDevices();
    return devices
        .map(
          (BluetoothDeviceInfo device) => ReceiverDeviceInfo(
            name: device.name,
            id: device.address,
            transportKind: ReceiverTransportKind.classicBluetooth,
          ),
        )
        .toList();
  }

  @override
  Future<void> connect(String deviceId) => _client.connect(deviceId);

  @override
  Future<void> disconnect() => _client.disconnect();
}

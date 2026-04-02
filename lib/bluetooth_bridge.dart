import 'package:flutter/services.dart';

class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({required this.name, required this.address});

  final String name;
  final String address;

  factory BluetoothDeviceInfo.fromMap(Map<String, dynamic> map) {
    return BluetoothDeviceInfo(
      name: map['name'] as String? ?? 'Unknown device',
      address: map['address'] as String? ?? '',
    );
  }
}

class BluetoothBridge {
  static const MethodChannel _methods = MethodChannel(
    'vo2_flutter/bluetooth_methods',
  );
  static const EventChannel _events = EventChannel(
    'vo2_flutter/bluetooth_stream',
  );

  Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map((dynamic event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  Future<bool> requestPermissions() async {
    return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
  }

  Future<bool> isBluetoothEnabled() async {
    return await _methods.invokeMethod<bool>('isBluetoothEnabled') ?? false;
  }

  Future<List<BluetoothDeviceInfo>> getBondedDevices() async {
    final List<dynamic> devices =
        await _methods.invokeListMethod<dynamic>('getBondedDevices') ??
        <dynamic>[];

    return devices.map((dynamic item) {
      return BluetoothDeviceInfo.fromMap(
        Map<String, dynamic>.from(item as Map),
      );
    }).toList();
  }

  Future<void> connect(String address) {
    return _methods.invokeMethod<void>('connect', <String, dynamic>{
      'address': address,
    });
  }

  Future<void> disconnect() {
    return _methods.invokeMethod<void>('disconnect');
  }
}

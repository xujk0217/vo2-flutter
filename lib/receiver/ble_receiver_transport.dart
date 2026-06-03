import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

class BleDeviceInfo {
  const BleDeviceInfo({required this.name, required this.id});

  final String name;
  final String id;

  factory BleDeviceInfo.fromMap(Map<String, dynamic> map) {
    return BleDeviceInfo(
      name: map['name'] as String? ?? DeviceBleUuids.advertisedName,
      id: map['id'] as String? ?? '',
    );
  }
}

abstract interface class BleBridgeClient {
  Stream<Map<String, dynamic>> events();

  Future<bool> requestPermissions();

  Future<bool> isBluetoothEnabled();

  Future<List<BleDeviceInfo>> scanDevices();

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<void> write(List<int> bytes);
}

class BleBridgeClientAdapter implements BleBridgeClient {
  const BleBridgeClientAdapter();

  static const MethodChannel _methods = MethodChannel(
    'vo2_flutter/ble_methods',
  );
  static const EventChannel _events = EventChannel('vo2_flutter/ble_stream');

  @override
  Future<void> connect(String deviceId) {
    return _methods.invokeMethod<void>('connect', <String, dynamic>{
      'deviceId': deviceId,
      'serviceUuid': DeviceBleUuids.service,
      'writeCharacteristicUuid': DeviceBleUuids.writeCharacteristic,
      'notifyCharacteristicUuid': DeviceBleUuids.notifyCharacteristic,
    });
  }

  @override
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');

  @override
  Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map((dynamic event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  @override
  Future<bool> isBluetoothEnabled() async {
    return await _methods.invokeMethod<bool>('isBluetoothEnabled') ?? false;
  }

  @override
  Future<bool> requestPermissions() async {
    return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
  }

  @override
  Future<List<BleDeviceInfo>> scanDevices() async {
    final List<dynamic> devices =
        await _methods
            .invokeListMethod<dynamic>('scanDevices', <String, dynamic>{
              'serviceUuid': DeviceBleUuids.service,
              'advertisedName': DeviceBleUuids.advertisedName,
            }) ??
        <dynamic>[];
    return devices.map((dynamic item) {
      return BleDeviceInfo.fromMap(Map<String, dynamic>.from(item as Map));
    }).toList();
  }

  @override
  Future<void> write(List<int> bytes) {
    return _methods.invokeMethod<void>('write', <String, dynamic>{
      'bytes': Uint8List.fromList(bytes),
    });
  }
}

class BleReceiverTransport
    implements ReceiverTransport, DeviceProtocolFrameWriter {
  BleReceiverTransport({
    BleBridgeClient? bridgeClient,
    DeviceProtocolCodec codec = const DeviceProtocolCodec(),
  }) : _bridgeClient = bridgeClient ?? const BleBridgeClientAdapter(),
       _codec = codec,
       _frameDecoder = DeviceFrameDecoder(codec: codec);

  final BleBridgeClient _bridgeClient;
  final DeviceProtocolCodec _codec;
  final DeviceFrameDecoder _frameDecoder;

  @override
  Future<void> connect(String deviceId) => _bridgeClient.connect(deviceId);

  @override
  Future<void> disconnect() => _bridgeClient.disconnect();

  @override
  Stream<ReceiverTransportEvent> events() async* {
    await for (final Map<String, dynamic> event in _bridgeClient.events()) {
      final List<ReceiverTransportEvent> mappedEvents = _mapBleEvent(event);
      for (final ReceiverTransportEvent mappedEvent in mappedEvents) {
        yield mappedEvent;
      }
    }
  }

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() async {
    final List<BleDeviceInfo> devices = await _bridgeClient.scanDevices();
    return devices
        .map(
          (BleDeviceInfo device) => ReceiverDeviceInfo(
            name: device.name,
            id: device.id,
            transportKind: ReceiverTransportKind.ble,
          ),
        )
        .toList();
  }

  @override
  Future<bool> isEnabled() => _bridgeClient.isBluetoothEnabled();

  @override
  Future<bool> requestPermissions() => _bridgeClient.requestPermissions();

  @override
  Future<void> writeFrame(DeviceFrame frame) {
    return _bridgeClient.write(_codec.encode(frame));
  }

  List<ReceiverTransportEvent> _mapBleEvent(Map<String, dynamic> event) {
    final String type = event['type'] as String? ?? '';
    switch (type) {
      case 'status':
        return <ReceiverTransportEvent>[
          ReceiverStatusEvent(
            state: event['state'] as String? ?? '',
            message: event['message'] as String? ?? 'BLE 狀態更新',
          ),
        ];
      case 'error':
        return <ReceiverTransportEvent>[
          ReceiverErrorEvent(
            code: event['code'] as String? ?? 'ble_error',
            message: event['message'] as String? ?? 'BLE 錯誤',
          ),
        ];
      case 'data':
        return _mapDataChunk(event['chunk']);
      default:
        return <ReceiverTransportEvent>[
          ReceiverErrorEvent(
            code: 'unsupported_ble_event',
            message: event['message'] as String? ?? '未支援的 BLE 事件',
          ),
        ];
    }
  }

  List<ReceiverTransportEvent> _mapDataChunk(dynamic chunk) {
    final Uint8List? bytes = _coerceChunk(chunk);
    if (bytes == null) {
      return const <ReceiverTransportEvent>[
        ReceiverErrorEvent(
          code: 'invalid_ble_chunk',
          message: 'BLE chunk 格式錯誤',
        ),
      ];
    }

    try {
      final List<DeviceFrame> frames = _frameDecoder.addChunk(bytes);
      return frames.map(_mapFrame).toList();
    } on FormatException catch (error) {
      return <ReceiverTransportEvent>[
        ReceiverErrorEvent(code: 'invalid_ble_frame', message: error.message),
      ];
    }
  }

  ReceiverDataEvent _mapFrame(DeviceFrame frame) {
    return ReceiverDataEvent(
      payload: jsonEncode(<String, dynamic>{
        'messageType': frame.messageType,
        'flags': frame.flags,
        'seq': frame.seq,
        'payloadBase64': base64Encode(frame.payload),
      }),
    );
  }

  Uint8List? _coerceChunk(dynamic chunk) {
    if (chunk is Uint8List) {
      return chunk;
    }
    if (chunk is List<int>) {
      return Uint8List.fromList(chunk);
    }
    if (chunk is List<dynamic>) {
      final List<int> bytes = <int>[];
      for (final dynamic value in chunk) {
        if (value is! int || value < 0 || value > 255) {
          return null;
        }
        bytes.add(value);
      }
      return Uint8List.fromList(bytes);
    }
    return null;
  }
}

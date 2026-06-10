import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

class ReceiverConnectionController extends ChangeNotifier {
  ReceiverConnectionController({
    required ReceiverTransport transport,
    String? preferredDeviceId,
    String initialStatusMessage = '等待藍牙權限',
  }) : _transport = transport,
       _preferredDeviceId = preferredDeviceId?.toUpperCase(),
       _statusMessage = initialStatusMessage {
    _eventSubscription = _transport.events().listen(_handleTransportEvent);
  }

  final ReceiverTransport _transport;
  final String? _preferredDeviceId;
  StreamSubscription<ReceiverTransportEvent>? _eventSubscription;
  Future<void>? _bootstrapOperation;
  void Function(ReceiverDataEvent event)? _onData;
  final List<void Function(ReceiverDataEvent event)> _dataListeners =
      <void Function(ReceiverDataEvent event)>[];

  List<ReceiverDeviceInfo> _devices = <ReceiverDeviceInfo>[];
  String? _selectedDeviceId;
  String _statusMessage;
  bool _permissionsGranted = false;
  bool _bluetoothEnabled = false;
  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _lastTransportState;
  String? _lastErrorCode;

  List<ReceiverDeviceInfo> get devices =>
      List<ReceiverDeviceInfo>.unmodifiable(_devices);
  String? get selectedDeviceId => _selectedDeviceId;
  String get statusMessage => _statusMessage;
  bool get permissionsGranted => _permissionsGranted;
  bool get bluetoothEnabled => _bluetoothEnabled;
  bool get isLoadingDevices => _isLoadingDevices;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String? get lastTransportState => _lastTransportState;
  String? get lastErrorCode => _lastErrorCode;

  void setDataListener(void Function(ReceiverDataEvent event)? onData) {
    _onData = onData;
  }

  void addDataListener(void Function(ReceiverDataEvent event) listener) {
    _dataListeners.add(listener);
  }

  void removeDataListener(void Function(ReceiverDataEvent event) listener) {
    _dataListeners.remove(listener);
  }

  void reportStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void selectDevice(String? deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  Future<void> connectToDevice(String deviceId) async {
    if (_isConnecting) {
      return;
    }
    if (_isConnected) {
      return;
    }

    _selectedDeviceId = deviceId;
    await toggleConnection();
  }

  Future<void> bootstrap() {
    final Future<void>? existingOperation = _bootstrapOperation;
    if (existingOperation != null) {
      return existingOperation;
    }

    final Future<void> operation = _bootstrap();
    _bootstrapOperation = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearBootstrapOperation(),
        onError: (Object error, StackTrace stackTrace) =>
            _clearBootstrapOperation(),
      ),
    );
    return operation;
  }

  void _clearBootstrapOperation() {
    _bootstrapOperation = null;
  }

  Future<void> _bootstrap() async {
    final bool granted = await _transport.requestPermissions();
    final bool enabled = await _transport.isEnabled();

    _permissionsGranted = granted;
    _bluetoothEnabled = enabled;
    if (!_isConnected && !_isConnecting) {
      _statusMessage = granted
          ? (enabled ? '藍牙已就緒，正在自動搜尋裝置。' : '請先開啟手機藍牙。')
          : '請允許藍牙權限。';
    }
    notifyListeners();

    if (granted && enabled) {
      await refreshDevices();
    }
  }

  Future<void> refreshDevices() async {
    if (!_permissionsGranted) {
      return;
    }

    _isLoadingDevices = true;
    notifyListeners();

    try {
      final List<ReceiverDeviceInfo> devices = await _transport.getDevices();
      String? nextSelectedDeviceId = _selectedDeviceId;
      if (devices.isNotEmpty) {
        final ReceiverDeviceInfo preferred = devices.firstWhere(
          (ReceiverDeviceInfo device) =>
              device.id.toUpperCase() == _preferredDeviceId,
          orElse: () => devices.first,
        );
        nextSelectedDeviceId =
            devices.any(
              (ReceiverDeviceInfo device) => device.id == _selectedDeviceId,
            )
            ? _selectedDeviceId
            : preferred.id;
      } else {
        nextSelectedDeviceId = null;
      }

      _devices = _mergeDevicesPreservingOrder(devices);
      _selectedDeviceId = nextSelectedDeviceId;
      if (!_isConnected && !_isConnecting) {
        _statusMessage = devices.isEmpty
            ? '尚未找到 BLE 裝置，會持續自動搜尋。'
            : '已找到 ${devices.length} 台 BLE 裝置。';
      }
    } on PlatformException catch (error) {
      _statusMessage = error.message ?? '讀取已配對裝置失敗。';
    } finally {
      _isLoadingDevices = false;
      notifyListeners();
    }
  }

  List<ReceiverDeviceInfo> _mergeDevicesPreservingOrder(
    List<ReceiverDeviceInfo> scannedDevices,
  ) {
    final Map<String, ReceiverDeviceInfo> scannedById =
        <String, ReceiverDeviceInfo>{
          for (final ReceiverDeviceInfo device in scannedDevices)
            device.id: device,
        };
    final List<ReceiverDeviceInfo> merged = <ReceiverDeviceInfo>[];
    for (final ReceiverDeviceInfo existing in _devices) {
      final ReceiverDeviceInfo? scanned = scannedById.remove(existing.id);
      if (scanned != null) {
        merged.add(scanned);
      }
    }
    merged.addAll(scannedById.values);
    return merged;
  }

  Future<void> toggleConnection() async {
    if (_isConnected) {
      await _transport.disconnect();
      return;
    }

    final String? deviceId = _selectedDeviceId;
    if (deviceId == null) {
      _statusMessage = '請先選擇藍牙裝置。';
      notifyListeners();
      return;
    }

    _isConnecting = true;
    _statusMessage = '準備連接 $deviceId ...';
    notifyListeners();

    try {
      await _transport.connect(deviceId);
    } on PlatformException catch (error) {
      _statusMessage = error.message ?? '藍牙連線失敗。';
      _isConnecting = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  String selectedDeviceName() {
    for (final ReceiverDeviceInfo device in _devices) {
      if (device.id == _selectedDeviceId) {
        return device.name;
      }
    }
    return '未選擇裝置';
  }

  void _handleTransportEvent(ReceiverTransportEvent event) {
    switch (event) {
      case ReceiverStatusEvent():
        _lastTransportState = event.state;
        _lastErrorCode = null;
        _statusMessage = event.message;
        _isConnecting = event.state == 'connecting';
        _isConnected = event.state == 'connected';
        notifyListeners();
      case ReceiverErrorEvent():
        _lastErrorCode = event.code;
        _statusMessage = event.message;
        _isConnecting = false;
        _isConnected = false;
        notifyListeners();
      case ReceiverDataEvent():
        _onData?.call(event);
        for (final void Function(ReceiverDataEvent event) listener
            in _dataListeners) {
          listener(event);
        }
    }
  }

  Future<void> disposeAsync() async {
    await _transport.disconnect();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  @override
  void dispose() {
    unawaited(disposeAsync());
    super.dispose();
  }
}

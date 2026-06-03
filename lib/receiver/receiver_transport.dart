enum ReceiverTransportKind { classicBluetooth, ble }

class ReceiverDeviceInfo {
  const ReceiverDeviceInfo({
    required this.name,
    required this.id,
    required this.transportKind,
  });

  final String name;
  final String id;
  final ReceiverTransportKind transportKind;
}

sealed class ReceiverTransportEvent {
  const ReceiverTransportEvent();
}

class ReceiverStatusEvent extends ReceiverTransportEvent {
  const ReceiverStatusEvent({required this.state, required this.message});

  final String state;
  final String message;
}

class ReceiverErrorEvent extends ReceiverTransportEvent {
  const ReceiverErrorEvent({required this.code, required this.message});

  final String code;
  final String message;
}

class ReceiverDataEvent extends ReceiverTransportEvent {
  const ReceiverDataEvent({required this.payload});

  final String payload;
}

abstract interface class ReceiverTransport {
  const ReceiverTransport();

  Stream<ReceiverTransportEvent> events();

  Future<bool> requestPermissions();

  Future<bool> isEnabled();

  Future<List<ReceiverDeviceInfo>> getDevices();

  Future<void> connect(String deviceId);

  Future<void> disconnect();
}

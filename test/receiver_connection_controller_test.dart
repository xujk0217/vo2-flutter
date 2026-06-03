import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

class _FakeReceiverTransport implements ReceiverTransport {
  _FakeReceiverTransport({this.permissionsCompleter});

  final StreamController<ReceiverTransportEvent> eventController =
      StreamController<ReceiverTransportEvent>.broadcast();
  final Completer<bool>? permissionsCompleter;
  List<ReceiverDeviceInfo> devices = const <ReceiverDeviceInfo>[];
  String? connectedDeviceId;
  int requestPermissionsCalls = 0;
  int isEnabledCalls = 0;
  int getDevicesCalls = 0;
  bool disconnected = false;

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceId = deviceId;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Stream<ReceiverTransportEvent> events() => eventController.stream;

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() async {
    getDevicesCalls += 1;
    return devices;
  }

  @override
  Future<bool> isEnabled() async {
    isEnabledCalls += 1;
    return true;
  }

  @override
  Future<bool> requestPermissions() async {
    requestPermissionsCalls += 1;
    return permissionsCompleter == null ? true : permissionsCompleter!.future;
  }
}

void main() {
  group('ReceiverConnectionController', () {
    test(
      'bootstraps permissions, adapter state, devices, and preferred device',
      () async {
        final _FakeReceiverTransport transport = _FakeReceiverTransport()
          ..devices = const <ReceiverDeviceInfo>[
            ReceiverDeviceInfo(
              name: 'Other',
              id: '11:22',
              transportKind: ReceiverTransportKind.classicBluetooth,
            ),
            ReceiverDeviceInfo(
              name: 'Preferred',
              id: 'AA:BB',
              transportKind: ReceiverTransportKind.classicBluetooth,
            ),
          ];
        final ReceiverConnectionController controller =
            ReceiverConnectionController(
              transport: transport,
              preferredDeviceId: 'AA:BB',
            );

        await controller.bootstrap();

        expect(controller.permissionsGranted, isTrue);
        expect(controller.bluetoothEnabled, isTrue);
        expect(controller.devices, hasLength(2));
        expect(controller.selectedDeviceId, 'AA:BB');
        await controller.disposeAsync();
      },
    );

    test(
      'connects selected device and disconnects when already connected',
      () async {
        final _FakeReceiverTransport transport = _FakeReceiverTransport()
          ..devices = const <ReceiverDeviceInfo>[
            ReceiverDeviceInfo(
              name: 'Sensor',
              id: 'AA:BB',
              transportKind: ReceiverTransportKind.classicBluetooth,
            ),
          ];
        final ReceiverConnectionController controller =
            ReceiverConnectionController(transport: transport);
        await controller.bootstrap();

        await controller.toggleConnection();
        expect(transport.connectedDeviceId, 'AA:BB');

        transport.eventController.add(
          const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
        );
        await pumpEventQueue();
        expect(controller.isConnected, isTrue);

        await controller.toggleConnection();
        expect(transport.disconnected, isTrue);
        await controller.disposeAsync();
      },
    );

    test('forwards data events to listener', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      ReceiverDataEvent? received;
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport)
            ..setDataListener((ReceiverDataEvent event) {
              received = event;
            });

      transport.eventController.add(
        const ReceiverDataEvent(payload: 'payload'),
      );
      await pumpEventQueue();

      expect(received?.payload, 'payload');
      await controller.disposeAsync();
    });

    test('coalesces concurrent bootstrap calls', () async {
      final Completer<bool> permissionsCompleter = Completer<bool>();
      final _FakeReceiverTransport transport =
          _FakeReceiverTransport(permissionsCompleter: permissionsCompleter)
            ..devices = const <ReceiverDeviceInfo>[
              ReceiverDeviceInfo(
                name: 'Sensor',
                id: 'AA:BB',
                transportKind: ReceiverTransportKind.classicBluetooth,
              ),
            ];
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      final Future<void> firstBootstrap = controller.bootstrap();
      final Future<void> secondBootstrap = controller.bootstrap();
      expect(identical(firstBootstrap, secondBootstrap), isTrue);
      expect(transport.requestPermissionsCalls, 1);

      permissionsCompleter.complete(true);
      await Future.wait(<Future<void>>[firstBootstrap, secondBootstrap]);

      expect(transport.requestPermissionsCalls, 1);
      expect(transport.isEnabledCalls, 1);
      expect(transport.getDevicesCalls, 1);
      expect(controller.devices, hasLength(1));
      await controller.disposeAsync();
    });

    test('preserves connected state message when bootstrapped again', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport()
        ..devices = const <ReceiverDeviceInfo>[
          ReceiverDeviceInfo(
            name: 'Sensor',
            id: 'AA:BB',
            transportKind: ReceiverTransportKind.classicBluetooth,
          ),
        ];
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);
      await controller.bootstrap();
      await controller.toggleConnection();
      transport.eventController.add(
        const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
      );
      await pumpEventQueue();

      await controller.bootstrap();

      expect(controller.isConnected, isTrue);
      expect(controller.statusMessage, 'Connected.');
      expect(transport.getDevicesCalls, 2);
      await controller.disposeAsync();
    });
  });
}

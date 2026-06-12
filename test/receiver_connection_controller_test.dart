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

    test('uses only named devices for selection, merge, and status', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport()
        ..devices = const <ReceiverDeviceInfo>[
          ReceiverDeviceInfo(
            name: '',
            id: 'hidden-1',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: '   ',
            id: 'hidden-2',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: 'Alpha',
            id: 'AA:BB',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: 'Beta',
            id: 'CC:DD',
            transportKind: ReceiverTransportKind.ble,
          ),
        ];
      final ReceiverConnectionController controller =
          ReceiverConnectionController(
            transport: transport,
            preferredDeviceId: 'hidden-1',
          );

      await controller.bootstrap();

      expect(
        controller.devices.map((ReceiverDeviceInfo device) => device.id),
        <String>['AA:BB', 'CC:DD'],
      );
      expect(controller.selectedDeviceId, 'AA:BB');
      expect(controller.statusMessage, '已找到 2 台 BLE 裝置。');

      controller.selectDevice('hidden-1');
      transport.devices = const <ReceiverDeviceInfo>[
        ReceiverDeviceInfo(
          name: 'Beta updated',
          id: 'CC:DD',
          transportKind: ReceiverTransportKind.ble,
        ),
        ReceiverDeviceInfo(
          name: 'Alpha updated',
          id: 'AA:BB',
          transportKind: ReceiverTransportKind.ble,
        ),
        ReceiverDeviceInfo(
          name: 'Gamma',
          id: 'EE:FF',
          transportKind: ReceiverTransportKind.ble,
        ),
        ReceiverDeviceInfo(
          name: ' ',
          id: 'hidden-1',
          transportKind: ReceiverTransportKind.ble,
        ),
      ];

      await controller.refreshDevices();

      expect(
        controller.devices.map((ReceiverDeviceInfo device) => device.id),
        <String>['AA:BB', 'CC:DD', 'EE:FF'],
      );
      expect(controller.selectedDeviceId, 'CC:DD');
      expect(controller.statusMessage, '已找到 3 台 BLE 裝置。');
      await controller.disposeAsync();
    });

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

    test(
      'connectToDevice targets tapped id and keeps active ids through refresh',
      () async {
        final _FakeReceiverTransport transport = _FakeReceiverTransport()
          ..devices = const <ReceiverDeviceInfo>[
            ReceiverDeviceInfo(
              name: 'Alpha',
              id: 'AA:BB',
              transportKind: ReceiverTransportKind.ble,
            ),
            ReceiverDeviceInfo(
              name: 'Beta',
              id: 'CC:DD',
              transportKind: ReceiverTransportKind.ble,
            ),
          ];
        final ReceiverConnectionController controller =
            ReceiverConnectionController(
              transport: transport,
              preferredDeviceId: 'AA:BB',
            );
        await controller.bootstrap();
        expect(controller.selectedDeviceId, 'AA:BB');

        await controller.connectToDevice('CC:DD');

        expect(transport.connectedDeviceId, 'CC:DD');
        expect(controller.connectingDeviceId, 'CC:DD');

        transport.devices = const <ReceiverDeviceInfo>[
          ReceiverDeviceInfo(
            name: 'Alpha updated',
            id: 'AA:BB',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: 'Beta updated',
            id: 'CC:DD',
            transportKind: ReceiverTransportKind.ble,
          ),
        ];
        await controller.refreshDevices();

        expect(controller.connectingDeviceId, 'CC:DD');
        transport.eventController.add(
          const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
        );
        await pumpEventQueue();

        expect(controller.connectedDeviceId, 'CC:DD');
        expect(controller.connectingDeviceId, isNull);

        controller.selectDevice('AA:BB');
        expect(controller.selectedDeviceId, 'AA:BB');
        expect(controller.connectedDeviceId, 'CC:DD');
        await controller.disposeAsync();
      },
    );

    test(
      'keeps visible device names attached to ids through connect refresh',
      () async {
        final _FakeReceiverTransport transport = _FakeReceiverTransport()
          ..devices = const <ReceiverDeviceInfo>[
            ReceiverDeviceInfo(
              name: 'Alpha',
              id: 'AA:BB',
              transportKind: ReceiverTransportKind.ble,
            ),
            ReceiverDeviceInfo(
              name: 'Beta',
              id: 'CC:DD',
              transportKind: ReceiverTransportKind.ble,
            ),
          ];
        final ReceiverConnectionController controller =
            ReceiverConnectionController(transport: transport);
        await controller.bootstrap();

        await controller.connectToDevice('CC:DD');
        transport.eventController.add(
          const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
        );
        await pumpEventQueue();
        expect(controller.connectedDeviceId, 'CC:DD');

        transport.devices = const <ReceiverDeviceInfo>[
          ReceiverDeviceInfo(
            name: 'Alpha',
            id: 'CC:DD',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: 'Beta',
            id: 'AA:BB',
            transportKind: ReceiverTransportKind.ble,
          ),
        ];
        await controller.refreshDevices();

        expect(
          controller.devices.map(
            (ReceiverDeviceInfo device) => '${device.id} ${device.name}',
          ),
          <String>['AA:BB Alpha', 'CC:DD Beta'],
        );
        expect(controller.connectedDeviceId, 'CC:DD');
        await controller.disposeAsync();
      },
    );

    test('connectToDevice disconnects the connected tapped device', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport()
        ..devices = const <ReceiverDeviceInfo>[
          ReceiverDeviceInfo(
            name: 'Alpha',
            id: 'AA:BB',
            transportKind: ReceiverTransportKind.ble,
          ),
          ReceiverDeviceInfo(
            name: 'Beta',
            id: 'CC:DD',
            transportKind: ReceiverTransportKind.ble,
          ),
        ];
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);
      await controller.bootstrap();

      await controller.connectToDevice('CC:DD');
      transport.eventController.add(
        const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
      );
      await pumpEventQueue();

      expect(controller.connectedDeviceId, 'CC:DD');
      await controller.connectToDevice('CC:DD');

      expect(transport.disconnected, isTrue);
      expect(controller.isConnecting, isFalse);
      expect(controller.isConnected, isFalse);
      expect(controller.connectingDeviceId, isNull);
      expect(controller.connectedDeviceId, isNull);

      transport.eventController.add(
        const ReceiverStatusEvent(
          state: 'disconnected',
          message: 'Disconnected.',
        ),
      );
      await pumpEventQueue();

      expect(controller.isConnected, isFalse);
      expect(controller.connectedDeviceId, isNull);
      await controller.disposeAsync();
    });

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

    test('records latest raw transport status for diagnostics', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      transport.eventController.add(
        const ReceiverStatusEvent(
          state: 'write_started',
          message: 'BLE write started.',
        ),
      );
      await pumpEventQueue();

      expect(controller.lastTransportState, 'write_started');
      expect(controller.lastErrorCode, isNull);
      expect(controller.statusMessage, 'BLE write started.');
      await controller.disposeAsync();
    });

    test('keeps connected state across transient BLE write statuses', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      transport.eventController.add(
        const ReceiverStatusEvent(state: 'connected', message: 'Connected.'),
      );
      await pumpEventQueue();
      expect(controller.isConnected, isTrue);

      transport.eventController.add(
        const ReceiverStatusEvent(
          state: 'write_complete',
          message: 'BLE write complete.',
        ),
      );
      await pumpEventQueue();

      expect(controller.lastTransportState, 'write_complete');
      expect(controller.isConnected, isTrue);
      expect(controller.statusMessage, 'BLE write complete.');
      await controller.disposeAsync();
    });

    test('records latest transport error code for diagnostics', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      transport.eventController.add(
        const ReceiverErrorEvent(code: 'gatt_error', message: 'GATT failed.'),
      );
      await pumpEventQueue();

      expect(controller.lastTransportState, isNull);
      expect(controller.lastErrorCode, 'gatt_error');
      expect(controller.statusMessage, 'GATT failed.');
      await controller.disposeAsync();
    });

    test('forwards data events to multiple listeners', () async {
      final _FakeReceiverTransport transport = _FakeReceiverTransport();
      final List<String> received1 = <String>[];
      final List<String> received2 = <String>[];

      void cb1(ReceiverDataEvent event) {
        received1.add(event.payload);
      }

      void cb2(ReceiverDataEvent event) {
        received2.add(event.payload);
      }

      final ReceiverConnectionController controller =
          ReceiverConnectionController(transport: transport);

      controller.addDataListener(cb1);
      controller.addDataListener(cb2);

      transport.eventController.add(
        const ReceiverDataEvent(payload: 'payload'),
      );
      await pumpEventQueue();

      expect(received1, <String>['payload']);
      expect(received2, <String>['payload']);

      controller.removeDataListener(cb1);
      controller.removeDataListener(cb2);
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

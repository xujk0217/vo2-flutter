import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/widgets/connection_card.dart';

typedef TransportKindChanged =
    Future<ReceiverConnectionController> Function(ReceiverTransportKind kind);

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    ReceiverConnectionController? connectionController,
    ReceiverTransportKind transportKind = ReceiverTransportKind.classicBluetooth,
    TransportKindChanged? onTransportKindChanged,
  }) : _connectionController = connectionController,
       _transportKind = transportKind,
       _onTransportKindChanged = onTransportKindChanged;

  static const String routeName = '/connection';

  final ReceiverConnectionController? _connectionController;
  final ReceiverTransportKind _transportKind;
  final TransportKindChanged? _onTransportKindChanged;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late ReceiverConnectionController _connectionController;
  late final bool _ownsConnectionController;
  late ReceiverTransportKind _transportKind;
  bool _isSwitchingTransport = false;

  @override
  void initState() {
    super.initState();
    _ownsConnectionController = widget._connectionController == null;
    _connectionController =
        widget._connectionController ??
        ReceiverConnectionController(
          transport: ClassicBluetoothTransport(),
          preferredDeviceId: kReferenceDeviceAddress,
        );
    _connectionController.addListener(_handleConnectionChanged);
    _transportKind = widget._transportKind;
    unawaited(_connectionController.bootstrap());
  }

  @override
  void didUpdateWidget(ConnectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._connectionController != widget._connectionController &&
        widget._connectionController != null) {
      _connectionController.removeListener(_handleConnectionChanged);
      _connectionController = widget._connectionController!;
      _connectionController.addListener(_handleConnectionChanged);
      unawaited(_connectionController.bootstrap());
    }
    _transportKind = widget._transportKind;
  }

  void _handleConnectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _handleTransportKindChanged(ReceiverTransportKind kind) async {
    if (kind == _transportKind) {
      return;
    }

    final TransportKindChanged? onTransportKindChanged =
        widget._onTransportKindChanged;
    if (onTransportKindChanged == null) {
      return;
    }

    setState(() {
      _isSwitchingTransport = true;
    });

    final ReceiverConnectionController previousController =
        _connectionController;
    final ReceiverConnectionController nextController = await onTransportKindChanged(
      kind,
    );
    if (!mounted) return;

    if (!identical(previousController, nextController)) {
      previousController.removeListener(_handleConnectionChanged);
      _connectionController = nextController;
      _connectionController.addListener(_handleConnectionChanged);
    }
    setState(() {
      _transportKind = kind;
      _isSwitchingTransport = false;
    });
    unawaited(_connectionController.bootstrap());
  }

  @override
  void dispose() {
    _connectionController.removeListener(_handleConnectionChanged);
    if (_ownsConnectionController) {
      _connectionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('裝置連線')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Text(
              '裝置連線',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '預設使用 Android Classic Bluetooth；需要測試 device_comm 時可手動切換 BLE。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 20),
            SegmentedButton<ReceiverTransportKind>(
              segments: const <ButtonSegment<ReceiverTransportKind>>[
                ButtonSegment<ReceiverTransportKind>(
                  value: ReceiverTransportKind.classicBluetooth,
                  label: Text('Classic'),
                  icon: Icon(Icons.bluetooth_rounded),
                ),
                ButtonSegment<ReceiverTransportKind>(
                  value: ReceiverTransportKind.ble,
                  label: Text('BLE'),
                  icon: Icon(Icons.sensors_rounded),
                ),
              ],
              selected: <ReceiverTransportKind>{_transportKind},
              onSelectionChanged: _isSwitchingTransport
                  ? null
                  : (Set<ReceiverTransportKind> selected) {
                      unawaited(_handleTransportKindChanged(selected.single));
                    },
            ),
            const SizedBox(height: 20),
            ConnectionCard(
              devices: _connectionController.devices,
              selectedDeviceId: _connectionController.selectedDeviceId,
              permissionsGranted: _connectionController.permissionsGranted,
              bluetoothEnabled: _connectionController.bluetoothEnabled,
              statusMessage: _connectionController.statusMessage,
              isLoadingDevices: _connectionController.isLoadingDevices,
              isConnecting: _connectionController.isConnecting,
              isConnected: _connectionController.isConnected,
              onRequestPermissions: _connectionController.bootstrap,
              onRefreshDevices: _connectionController.refreshDevices,
              onConnectPressed: _connectionController.toggleConnection,
              onDeviceChanged: _connectionController.selectDevice,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(CalibrationScreen.routeName);
              },
              icon: const Icon(Icons.timer_rounded),
              label: Text(
                _connectionController.isConnected ? '前往校正流程' : '稍後校正',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

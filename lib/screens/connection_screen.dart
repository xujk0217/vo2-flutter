import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/widgets/connection_card.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    ReceiverConnectionController? connectionController,
  }) : _connectionController = connectionController;

  static const String routeName = '/connection';

  final ReceiverConnectionController? _connectionController;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final ReceiverConnectionController _connectionController;
  late final bool _ownsConnectionController;

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
    unawaited(_connectionController.bootstrap());
  }

  void _handleConnectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
              '目前先沿用 Android Classic Bluetooth 接收；之後 BLE 會接到同一個 receiver transport 介面。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
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

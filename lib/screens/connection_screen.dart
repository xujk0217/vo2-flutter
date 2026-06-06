import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/widgets/connection_card.dart';

typedef TransportKindChanged =
    Future<TransportSelectionResult> Function(ReceiverTransportKind kind);

class TransportSelectionResult {
  const TransportSelectionResult({
    required this.connectionController,
    required this.protocolSession,
  });

  final ReceiverConnectionController connectionController;
  final DeviceProtocolSession protocolSession;
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    ReceiverConnectionController? connectionController,
    ReceiverTransportKind transportKind = ReceiverTransportKind.ble,
    DeviceProtocolSession? protocolSession,
    UserProfile profile = UserProfile.defaults,
    TransportKindChanged? onTransportKindChanged,
  }) : _connectionController = connectionController,
        _transportKind = transportKind,
        _protocolSession = protocolSession,
        _profile = profile,
        _onTransportKindChanged = onTransportKindChanged;

  static const String routeName = '/connection';

  final ReceiverConnectionController? _connectionController;
  final ReceiverTransportKind _transportKind;
  final DeviceProtocolSession? _protocolSession;
  final UserProfile _profile;
  final TransportKindChanged? _onTransportKindChanged;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late ReceiverConnectionController _connectionController;
  late final bool _ownsConnectionController;
  DeviceProtocolSession? _protocolSession;
  late ReceiverTransportKind _transportKind;
  bool _isSwitchingTransport = false;
  bool _showAdvancedTransport = false;
  bool _hasAutoNavigatedToCalibration = false;

  @override
  void initState() {
    super.initState();
    _ownsConnectionController = widget._connectionController == null;
    _connectionController =
        widget._connectionController ??
        ReceiverConnectionController(
          transport: BleReceiverTransport(),
        );
    _connectionController.addListener(_handleConnectionChanged);
    _protocolSession = widget._protocolSession;
    _protocolSession?.updateProfile(widget._profile);
    _protocolSession?.addListener(_handleProtocolChanged);
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
    if (oldWidget._protocolSession != widget._protocolSession &&
        _protocolSession != widget._protocolSession) {
      _protocolSession?.removeListener(_handleProtocolChanged);
      _protocolSession = widget._protocolSession;
      _protocolSession?.updateProfile(widget._profile);
      _protocolSession?.addListener(_handleProtocolChanged);
    }
    if (oldWidget._profile != widget._profile) {
      _protocolSession?.updateProfile(widget._profile);
    }
    _transportKind = widget._transportKind;
  }

  void _handleConnectionChanged() {
    if (_connectionController.isConnected) {
      unawaited(_handleBleConnected());
    }
    _notifyIfMounted();
  }

  Future<void> _handleBleConnected() async {
    if (_hasAutoNavigatedToCalibration) {
      return;
    }
    _hasAutoNavigatedToCalibration = true;
    await _protocolSession?.sendProfile(widget._profile);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamed(CalibrationScreen.routeName);
  }

  void _handleProtocolChanged() {
    _notifyIfMounted();
  }

  void _notifyIfMounted() {
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
    final TransportSelectionResult selection = await onTransportKindChanged(kind);
    final ReceiverConnectionController nextController =
        selection.connectionController;
    if (!mounted) return;

    if (!identical(previousController, nextController)) {
      previousController.removeListener(_handleConnectionChanged);
      _connectionController = nextController;
      _connectionController.addListener(_handleConnectionChanged);
    }
    if (!identical(_protocolSession, selection.protocolSession)) {
      _protocolSession?.removeListener(_handleProtocolChanged);
      _protocolSession = selection.protocolSession;
      _protocolSession?.addListener(_handleProtocolChanged);
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
    _protocolSession?.removeListener(_handleProtocolChanged);
    if (_ownsConnectionController) {
      _connectionController.dispose();
    }
    super.dispose();
  }

  String? _healthStatusLabel() {
    final health = _protocolSession?.latestHealthResponse;
    if (health == null) return null;
    final String vo2 = health.vo2Running ? 'VO2 on' : 'VO2 off';
    final String sensor = health.sensorRunning ? 'Sensor on' : 'Sensor off';
    return '$vo2 / $sensor';
  }

  String? _appStatusLabel() {
    final status = _protocolSession?.latestAppStatus;
    if (status == null) return null;
    final String readiness = status.startWorkoutAvailable ? 'ready' : 'wait';
    return 'cal ${status.calibrationProgressPct}% / $readiness';
  }

  @override
  Widget build(BuildContext context) {
    final bool showingBleDiagnostics =
        _transportKind == ReceiverTransportKind.ble;
    final DeviceProtocolSession? protocolSession = showingBleDiagnostics
        ? _protocolSession
        : null;

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
              '預設使用 BLE 直接連接 bt_fucktrae_young，連線後會進入校正流程。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(
                  avatar: const Icon(Icons.sensors_rounded, size: 18),
                  label: const Text('BLE protocol'),
                  backgroundColor: const Color(0xFFE0F2FE),
                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                ),
                Chip(
                  avatar: const Icon(Icons.person_rounded, size: 18),
                  label: Text(widget._profile.displayName),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: widget._onTransportKindChanged == null
                  ? null
                  : () {
                      setState(() {
                        _showAdvancedTransport = !_showAdvancedTransport;
                      });
                    },
              icon: const Icon(Icons.tune_rounded),
              label: const Text('進階：測試傳輸模式'),
            ),
            if (_showAdvancedTransport) ...<Widget>[
              const SizedBox(height: 8),
              SegmentedButton<ReceiverTransportKind>(
                segments: const <ButtonSegment<ReceiverTransportKind>>[
                  ButtonSegment<ReceiverTransportKind>(
                    value: ReceiverTransportKind.ble,
                    label: Text('BLE'),
                    icon: Icon(Icons.sensors_rounded),
                  ),
                  ButtonSegment<ReceiverTransportKind>(
                    value: ReceiverTransportKind.classicBluetooth,
                    label: Text('Classic'),
                    icon: Icon(Icons.bluetooth_rounded),
                  ),
                ],
                selected: <ReceiverTransportKind>{_transportKind},
                onSelectionChanged: _isSwitchingTransport
                    ? null
                    : (Set<ReceiverTransportKind> selected) {
                        unawaited(_handleTransportKindChanged(selected.single));
                      },
              ),
            ],
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
              showBleDiagnostics: showingBleDiagnostics,
              lastTransportState: _connectionController.lastTransportState,
              lastErrorCode: _connectionController.lastErrorCode,
              lastProtocolMessageType: protocolSession?.lastProtocolMessageType,
              lastUnsupportedMessageType:
                  protocolSession?.lastUnsupportedMessageType,
              healthStatusLabel: showingBleDiagnostics
                  ? _healthStatusLabel()
                  : null,
              appStatusLabel: showingBleDiagnostics ? _appStatusLabel() : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(CalibrationScreen.routeName);
              },
              icon: const Icon(Icons.timer_rounded),
              label: Text(
                _connectionController.isConnected ? '前往校正流程' : '手動前往校正',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

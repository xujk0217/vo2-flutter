import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/onboarding_screen.dart';
import 'package:vo2_flutter/user_profile.dart';

typedef ReceiverTransportFactory =
    ReceiverTransport Function(ReceiverTransportKind kind);

class Vo2MotionApp extends StatefulWidget {
  const Vo2MotionApp({
    super.key,
    this.initialRoute = DashboardPage.routeName,
    this.transportFactory,
  });

  final String initialRoute;
  final ReceiverTransportFactory? transportFactory;

  @override
  State<Vo2MotionApp> createState() => _Vo2MotionAppState();
}

class _Vo2MotionAppState extends State<Vo2MotionApp> {
  ReceiverTransportKind _transportKind = ReceiverTransportKind.classicBluetooth;
  late ReceiverConnectionController _connectionController;
  late DeviceProtocolSession _protocolSession;
  late final void Function(ReceiverDataEvent event) _protocolDataListener;
  bool _protocolSessionDisposed = false;

  @override
  void initState() {
    super.initState();
    _protocolDataListener = (ReceiverDataEvent event) {
      unawaited(_protocolSession.handleDataEvent(event));
    };
    final ReceiverTransport transport = _createTransport(_transportKind);
    _protocolSession = _createProtocolSession(transport);
    _connectionController = _createConnectionController(
      kind: _transportKind,
      transport: transport,
    );
    _connectionController.addDataListener(_protocolDataListener);
  }

  ReceiverTransport _createTransport(ReceiverTransportKind kind) {
    final ReceiverTransportFactory? transportFactory = widget.transportFactory;
    if (transportFactory != null) {
      return transportFactory(kind);
    }

    switch (kind) {
      case ReceiverTransportKind.classicBluetooth:
        return ClassicBluetoothTransport();
      case ReceiverTransportKind.ble:
        return BleReceiverTransport();
    }
  }

  ReceiverConnectionController _createConnectionController({
    required ReceiverTransportKind kind,
    required ReceiverTransport transport,
  }) {
    return ReceiverConnectionController(
      transport: transport,
      preferredDeviceId: kind == ReceiverTransportKind.classicBluetooth
          ? kReferenceDeviceAddress
          : null,
    );
  }

  DeviceProtocolSession _createProtocolSession(ReceiverTransport transport) {
    if (transport case final DeviceProtocolFrameWriter writer) {
      return DeviceProtocolSession(writer: writer);
    }
    return DeviceProtocolSession();
  }

  Future<ReceiverConnectionController> _selectTransportKind(
    ReceiverTransportKind kind,
  ) async {
    if (kind == _transportKind) {
      return _connectionController;
    }

    final ReceiverConnectionController previousController =
        _connectionController;
    final DeviceProtocolSession previousProtocolSession = _protocolSession;
    previousController.removeDataListener(_protocolDataListener);

    final ReceiverTransport nextTransport = _createTransport(kind);
    final DeviceProtocolSession nextProtocolSession = _createProtocolSession(
      nextTransport,
    );
    final ReceiverConnectionController nextController =
        _createConnectionController(kind: kind, transport: nextTransport);
    nextController.addDataListener(_protocolDataListener);

    previousProtocolSession.dispose();
    _protocolSessionDisposed = true;
    await previousController.disposeAsync();

    if (!mounted) {
      nextProtocolSession.dispose();
      nextController.dispose();
      return nextController;
    }

    setState(() {
      _transportKind = kind;
      _protocolSession = nextProtocolSession;
      _connectionController = nextController;
      _protocolSessionDisposed = false;
    });
    return nextController;
  }

  @override
  void dispose() {
    _connectionController.removeDataListener(_protocolDataListener);
    _connectionController.dispose();
    if (!_protocolSessionDisposed) {
      _protocolSession.dispose();
      _protocolSessionDisposed = true;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E7490),
    );

    return MaterialApp(
      title: 'VO2 Motion Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F7FA),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF0F172A),
          displayColor: const Color(0xFF0F172A),
        ),
      ),
      initialRoute: widget.initialRoute,
      routes: <String, WidgetBuilder>{
        DashboardPage.routeName: (_) => DashboardPage(
          connectionController: _connectionController,
          protocolSession: _protocolSession,
        ),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        ConnectionScreen.routeName: (_) => ConnectionScreen(
          connectionController: _connectionController,
          transportKind: _transportKind,
          protocolSession: _protocolSession,
          onTransportKindChanged: _selectTransportKind,
        ),
        CalibrationScreen.routeName: (_) => CalibrationScreen(
          protocolSession: _protocolSession,
          profile: UserProfile.defaults,
        ),
      },
    );
  }
}

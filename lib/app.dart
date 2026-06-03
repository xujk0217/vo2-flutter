import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/onboarding_screen.dart';

class Vo2MotionApp extends StatefulWidget {
  const Vo2MotionApp({super.key});

  @override
  State<Vo2MotionApp> createState() => _Vo2MotionAppState();
}

class _Vo2MotionAppState extends State<Vo2MotionApp> {
  late final ReceiverConnectionController _connectionController;

  @override
  void initState() {
    super.initState();
    _connectionController = ReceiverConnectionController(
      transport: ClassicBluetoothTransport(),
      preferredDeviceId: kReferenceDeviceAddress,
    );
  }

  @override
  void dispose() {
    _connectionController.dispose();
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
      initialRoute: DashboardPage.routeName,
      routes: <String, WidgetBuilder>{
        DashboardPage.routeName: (_) =>
            DashboardPage(connectionController: _connectionController),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        ConnectionScreen.routeName: (_) =>
            ConnectionScreen(connectionController: _connectionController),
        CalibrationScreen.routeName: (_) => const CalibrationScreen(),
      },
    );
  }
}

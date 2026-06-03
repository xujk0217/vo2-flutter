import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';

enum CalibrationStatus { initial, running, completed }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  static const String routeName = '/calibration';

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CalibrationStatus _status = CalibrationStatus.initial;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCalibration() {
    setState(() {
      _status = CalibrationStatus.running;
      _secondsLeft = 30;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
        } else {
          _secondsLeft = 0;
          _status = CalibrationStatus.completed;
          timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('靜止校正')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '30 秒靜止校正',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_status == CalibrationStatus.initial)
                    Text(
                      '請保持靜止，然後點擊下方按鈕開始校正。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  if (_status == CalibrationStatus.running) ...<Widget>[
                    Text(
                      '校正中，請保持靜止...',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '剩餘 $_secondsLeft 秒',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: (30 - _secondsLeft) / 30),
                  ],
                  if (_status == CalibrationStatus.completed)
                    Text(
                      '校正完成！',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 32),
                  if (_status == CalibrationStatus.initial)
                    FilledButton(
                      onPressed: _startCalibration,
                      child: const Text('開始校正'),
                    ),
                  if (_status == CalibrationStatus.completed)
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          DashboardPage.routeName,
                          (Route<dynamic> route) => route.isFirst,
                        );
                      },
                      child: const Text('回到即時監測首頁'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

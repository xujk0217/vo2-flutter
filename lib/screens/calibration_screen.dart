import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/user_profile.dart';

enum CalibrationStatus { initial, running, completed }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({
    super.key,
    DeviceProtocolSession? protocolSession,
    UserProfile? profile,
  }) : _protocolSession = protocolSession,
       _profile = profile;

  static const String routeName = '/calibration';

  final DeviceProtocolSession? _protocolSession;
  final UserProfile? _profile;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CalibrationStatus _status = CalibrationStatus.initial;
  int _secondsLeft = 30;
  Timer? _timer;

  DeviceProtocolSession? get _protocolSession => widget._protocolSession;
  bool get _usesProtocol => _protocolSession?.canWriteCommands ?? false;

  @override
  void initState() {
    super.initState();
    _protocolSession?.addListener(_handleProtocolSessionChanged);
  }

  @override
  void didUpdateWidget(CalibrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._protocolSession != widget._protocolSession) {
      oldWidget._protocolSession?.removeListener(_handleProtocolSessionChanged);
      _protocolSession?.addListener(_handleProtocolSessionChanged);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _protocolSession?.removeListener(_handleProtocolSessionChanged);
    super.dispose();
  }

  void _handleProtocolSessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _startCalibration() async {
    if (_usesProtocol) {
      _timer?.cancel();
      await _protocolSession!.startCalibration(profile: widget._profile);
      return;
    }

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
    final DeviceProtocolSession? protocolSession = _protocolSession;
    final DeviceProtocolCalibrationState? protocolState =
        protocolSession?.calibrationState;
    final bool isInitial = _usesProtocol
        ? protocolState == DeviceProtocolCalibrationState.idle ||
              protocolState == DeviceProtocolCalibrationState.error
        : _status == CalibrationStatus.initial;
    final bool isRunning = _usesProtocol
        ? protocolState == DeviceProtocolCalibrationState.running
        : _status == CalibrationStatus.running;
    final bool isCompleted = _usesProtocol
        ? protocolState == DeviceProtocolCalibrationState.completed
        : _status == CalibrationStatus.completed;

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
                  if (isInitial)
                    Text(
                      '請保持靜止，然後點擊下方按鈕開始校正。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  if (_usesProtocol &&
                      protocolState == DeviceProtocolCalibrationState.error)
                    Text(
                      '校正失敗：${protocolSession?.protocolError?.message ?? '裝置回報錯誤'}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (isRunning) ...<Widget>[
                    Text(
                      '校正中，請保持靜止...',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_usesProtocol) ...<Widget>[
                      Text(
                        protocolSession?.calibrationElapsedMs == null
                            ? '等待裝置回報進度'
                            : '已進行 ${protocolSession!.calibrationElapsedMs! ~/ 1000} 秒',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (protocolSession?.calibrationHrEstimate != null)
                        Text(
                          '心率估計：${protocolSession!.calibrationHrEstimate} bpm',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF475569)),
                        ),
                    ] else
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
                    LinearProgressIndicator(
                      value: _usesProtocol
                          ? protocolSession?.calibrationProgress ?? 0
                          : (30 - _secondsLeft) / 30,
                    ),
                  ],
                  if (isCompleted) ...<Widget>[
                    Text(
                      '校正完成！',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_usesProtocol &&
                        protocolSession?.calibrationDone != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        '品質分數：${protocolSession!.calibrationDone!.qualityScore}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '樣本數：${protocolSession.calibrationDone!.sampleCount}',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                  const SizedBox(height: 32),
                  if (isInitial)
                    FilledButton(
                      onPressed: () {
                        unawaited(_startCalibration());
                      },
                      child: const Text('開始校正'),
                    ),
                  if (isCompleted)
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

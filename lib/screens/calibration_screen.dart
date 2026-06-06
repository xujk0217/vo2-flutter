import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/user_profile.dart';

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
  bool _isSendingCommand = false;

  DeviceProtocolSession? get _protocolSession => widget._protocolSession;
  bool get _usesProtocol => _protocolSession?.canWriteCommands ?? false;
  UserProfile get _selectedProfile => widget._profile ?? UserProfile.defaults;

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
    final DeviceProtocolSession? session = _protocolSession;
    if (session == null || !session.canWriteCommands) {
      return;
    }

    setState(() {
      _isSendingCommand = true;
    });
    await session.startCalibration(profile: _selectedProfile);
    if (mounted) {
      setState(() {
        _isSendingCommand = false;
      });
    }
  }

  Future<void> _skipCalibration() async {
    final DeviceProtocolSession? session = _protocolSession;
    if (session == null || !session.canWriteCommands) {
      return;
    }

    setState(() {
      _isSendingCommand = true;
    });
    final bool sent = await session.sendSkipCalibration();
    if (!mounted) {
      return;
    }
    setState(() {
      _isSendingCommand = false;
    });
    if (sent) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        DashboardPage.routeName,
        (Route<dynamic> route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeviceProtocolSession? protocolSession = _protocolSession;
    final DeviceProtocolCalibrationState? protocolState =
        protocolSession?.calibrationState;
    final bool isInitial = protocolState == null ||
        protocolState == DeviceProtocolCalibrationState.idle ||
        protocolState == DeviceProtocolCalibrationState.error;
    final bool isRunning = protocolState == DeviceProtocolCalibrationState.running;
    final bool isCompleted =
        protocolState == DeviceProtocolCalibrationState.completed;

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
                  const SizedBox(height: 8),
                  Text(
                    '使用者：${_selectedProfile.displayName}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_usesProtocol)
                    Text(
                      '此 BLE-first 流程需要可寫入的 DeviceProtocolSession；未連上支援協定的 BLE 裝置前，不會模擬校正狀態。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFB45309),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (isInitial)
                    Text(
                      '請保持靜止，然後點擊下方按鈕由 BLE 協定開始校正。',
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                        ),
                      ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: protocolSession?.calibrationProgress ?? 0,
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
                    FilledButton.icon(
                      onPressed: !_usesProtocol || _isSendingCommand
                          ? null
                          : () {
                              unawaited(_startCalibration());
                            },
                      icon: _isSendingCommand
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: const Text('開始校正'),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: !_usesProtocol || _isSendingCommand
                        ? null
                        : () {
                            unawaited(_skipCalibration());
                          },
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('跳過校正'),
                  ),
                  if (!_usesProtocol) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '跳過校正也必須透過 BLE fitness command 傳送，現在無法使用。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/user_profile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    ReceiverConnectionController? connectionController,
    DeviceProtocolSession? protocolSession,
    UserProfile profile = UserProfile.defaults,
  }) : _connectionController = connectionController,
       _protocolSession = protocolSession,
       _profile = profile;

  static const String routeName = '/dashboard';

  final ReceiverConnectionController? _connectionController;
  final DeviceProtocolSession? _protocolSession;
  final UserProfile _profile;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final ReceiverConnectionController _connectionController;
  late final bool _ownsConnectionController;
  DeviceProtocolSession? _protocolSession;
  String? _commandStatus;

  @override
  void initState() {
    super.initState();
    _ownsConnectionController = widget._connectionController == null;
    _connectionController =
        widget._connectionController ??
        ReceiverConnectionController(transport: BleReceiverTransport());
    _connectionController.addListener(_handleConnectionChanged);
    _protocolSession = widget._protocolSession;
    _protocolSession?.updateProfile(widget._profile);
    _protocolSession?.addListener(_handleProtocolSessionChanged);
    unawaited(_connectionController.bootstrap());
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._protocolSession != widget._protocolSession &&
        _protocolSession != widget._protocolSession) {
      _protocolSession?.removeListener(_handleProtocolSessionChanged);
      _protocolSession = widget._protocolSession;
      _protocolSession?.updateProfile(widget._profile);
      _protocolSession?.addListener(_handleProtocolSessionChanged);
    }
    if (oldWidget._profile != widget._profile) {
      _protocolSession?.updateProfile(widget._profile);
    }
  }

  @override
  void dispose() {
    _connectionController.removeListener(_handleConnectionChanged);
    _protocolSession?.removeListener(_handleProtocolSessionChanged);
    if (_ownsConnectionController) {
      _connectionController.dispose();
    }
    super.dispose();
  }

  void _handleConnectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleProtocolSessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _sendCommand(
    String successLabel,
    Future<bool> Function() command,
  ) async {
    final bool sent = await command();
    if (!mounted) {
      return;
    }
    setState(() {
      _commandStatus = sent ? successLabel : '尚未連上可寫入的 BLE protocol session';
    });
  }

  bool get _canWriteProtocol => _protocolSession?.canWriteCommands ?? false;

  bool get _canStartWorkout {
    if (!_canWriteProtocol) {
      return false;
    }
    final AppStatusPayload? status = _protocolSession?.latestAppStatus;
    return status?.startWorkoutAvailable ?? true;
  }

  bool get _hasAnyProtocolData {
    final DeviceProtocolSession? session = _protocolSession;
    if (session == null) {
      return false;
    }
    return session.latestVo2Prediction != null ||
        session.latestAppStatus != null ||
        session.latestHealthResponse != null ||
        session.latestRpeAlert != null ||
        session.latestWorkoutSummary != null ||
        session.latestRecommendationInput != null ||
        session.protocolError != null ||
        session.lastProtocolMessageType != null;
  }

  static String _hexMessageType(int value) {
    return '0x${value.toRadixString(16).padLeft(4, '0')}';
  }

  String _protocolSummary() {
    final DeviceProtocolSession? session = _protocolSession;
    if (session == null) {
      return '等待 BLE protocol session';
    }
    final int? messageType = session.lastProtocolMessageType;
    if (messageType == null) {
      return '等待 BLE protocol data';
    }
    return '最後訊息 ${_hexMessageType(messageType)}';
  }

  @override
  Widget build(BuildContext context) {
    final DeviceProtocolSession? session = _protocolSession;
    return Scaffold(
      appBar: AppBar(title: const Text('即時監測')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            _DashboardHeader(
              profile: widget._profile,
              connectionStatus: _connectionController.statusMessage,
              protocolSummary: _protocolSummary(),
            ),
            const SizedBox(height: 16),
            _CommandCard(
              canWriteProtocol: _canWriteProtocol,
              canStartWorkout: _canStartWorkout,
              commandStatus: _commandStatus,
              onRequestStatus: () {
                final DeviceProtocolSession? session = _protocolSession;
                if (session == null) {
                  return;
                }
                unawaited(
                  _sendCommand('已送出狀態請求', session.sendStatusRequest),
                );
              },
              onStartWorkout: () {
                final DeviceProtocolSession? session = _protocolSession;
                if (session == null) {
                  return;
                }
                unawaited(
                  _sendCommand('已送出開始訓練', session.sendStartWorkout),
                );
              },
              onEndWorkout: () {
                final DeviceProtocolSession? session = _protocolSession;
                if (session == null) {
                  return;
                }
                unawaited(_sendCommand('已送出結束訓練', session.sendEndWorkout));
              },
            ),
            const SizedBox(height: 16),
            if (!_hasAnyProtocolData) const _WaitingCard(),
            if (!_hasAnyProtocolData) const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _Vo2Card(prediction: session?.latestVo2Prediction),
                _AppStatusCard(status: session?.latestAppStatus),
                _HealthCard(health: session?.latestHealthResponse),
                _ProtocolDiagnosticsCard(session: session),
              ],
            ),
            const SizedBox(height: 16),
            _RpeAlertCard(alert: session?.latestRpeAlert),
            const SizedBox(height: 16),
            _WorkoutSummaryCard(summary: session?.latestWorkoutSummary),
            const SizedBox(height: 16),
            _RecommendationCard(
              recommendation: session?.latestRecommendationInput,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.profile,
    required this.connectionStatus,
    required this.protocolSummary,
  });

  final UserProfile profile;
  final String connectionStatus;
  final String protocolSummary;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'BLE protocol monitoring',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用者：${profile.displayName}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StatusChip(label: '來源：BLE protocol'),
              _StatusChip(label: protocolSummary),
              _StatusChip(label: '連線：$connectionStatus'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.canWriteProtocol,
    required this.canStartWorkout,
    required this.commandStatus,
    required this.onRequestStatus,
    required this.onStartWorkout,
    required this.onEndWorkout,
  });

  final bool canWriteProtocol;
  final bool canStartWorkout;
  final String? commandStatus;
  final VoidCallback onRequestStatus;
  final VoidCallback onStartWorkout;
  final VoidCallback onEndWorkout;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '協定控制',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: canWriteProtocol ? onRequestStatus : null,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Request status'),
              ),
              FilledButton.icon(
                onPressed: canStartWorkout ? onStartWorkout : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(canStartWorkout ? 'Start workout' : 'Start unavailable'),
              ),
              FilledButton.tonalIcon(
                onPressed: canWriteProtocol ? onEndWorkout : null,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('End workout'),
              ),
            ],
          ),
          if (commandStatus != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              commandStatus!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475569),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        children: <Widget>[
          const Icon(Icons.sensors_rounded, color: Color(0xFF0284C7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '等待 BLE protocol data；尚未收到裝置回報前不顯示 0、隨機或 demo 生理指標。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Vo2Card extends StatelessWidget {
  const _Vo2Card({required this.prediction});

  final Vo2PredictionPayload? prediction;

  @override
  Widget build(BuildContext context) {
    final Vo2PredictionPayload? value = prediction;
    return _MetricTile(
      title: 'VO2 prediction',
      value: value == null ? '等待資料' : value.vo2MlKgMin.toStringAsFixed(1),
      detail: value == null
          ? '等待 BLE protocol data'
          : 'timestampNs ${value.timestampNs}',
      accentColor: const Color(0xFF0E7490),
    );
  }
}

class _AppStatusCard extends StatelessWidget {
  const _AppStatusCard({required this.status});

  final AppStatusPayload? status;

  @override
  Widget build(BuildContext context) {
    final AppStatusPayload? value = status;
    return _MetricTile(
      title: 'app_status',
      value: value == null ? '等待資料' : 'cal ${value.calibrationProgressPct}%',
      detail: value == null
          ? '等待 BLE protocol data'
          : 'transport ${value.transport} / conn ${value.connectionState} / ble ${value.bleTransferState}\nprofile ${value.profileReceived ? 'received' : 'pending'} / calibration ${value.calibrationState}\nlast error ${value.lastErrorCode} / start ${value.startWorkoutAvailable ? 'available' : 'unavailable'}',
      accentColor: const Color(0xFF2563EB),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final HealthResponsePayload? health;

  @override
  Widget build(BuildContext context) {
    final HealthResponsePayload? value = health;
    return _MetricTile(
      title: 'health_response',
      value: value == null ? '等待資料' : 'VO2 ${value.vo2Running ? 'on' : 'off'}',
      detail: value == null
          ? '等待 BLE protocol data'
          : 'sensor ${value.sensorRunning ? 'running' : 'stopped'}',
      accentColor: const Color(0xFF16A34A),
    );
  }
}

class _ProtocolDiagnosticsCard extends StatelessWidget {
  const _ProtocolDiagnosticsCard({required this.session});

  final DeviceProtocolSession? session;

  @override
  Widget build(BuildContext context) {
    final DeviceProtocolSession? value = session;
    final ErrorPayload? error = value?.protocolError;
    final int? lastMessageType = value?.lastProtocolMessageType;
    final int? unsupportedMessageType = value?.lastUnsupportedMessageType;
    return _MetricTile(
      title: 'protocol diagnostics',
      value: error == null ? '無錯誤' : 'error ${error.code}',
      detail: <String>[
        if (lastMessageType == null)
          '等待 BLE protocol data'
        else
          'last ${_DashboardPageState._hexMessageType(lastMessageType)}',
        if (unsupportedMessageType != null)
          'unsupported ${_DashboardPageState._hexMessageType(unsupportedMessageType)}',
        if (error != null) error.message,
      ].join('\n'),
      accentColor: const Color(0xFFEA580C),
    );
  }
}

class _RpeAlertCard extends StatelessWidget {
  const _RpeAlertCard({required this.alert});

  final RpeAlertPayload? alert;

  @override
  Widget build(BuildContext context) {
    final RpeAlertPayload? value = alert;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionTitle(title: 'RPE alert'),
          const SizedBox(height: 8),
          if (value == null)
            const _EmptyProtocolText()
          else ...<Widget>[
            Text(
              value.message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'type ${value.alertType} / RPE ${value.rpe} / duration ${value.durationMs} ms / ts ${value.hostTsMs}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkoutSummaryCard extends StatelessWidget {
  const _WorkoutSummaryCard({required this.summary});

  final WorkoutSummaryPayload? summary;

  @override
  Widget build(BuildContext context) {
    final WorkoutSummaryPayload? value = summary;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionTitle(title: 'workout_summary'),
          const SizedBox(height: 8),
          if (value == null)
            const _EmptyProtocolText()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusChip(label: 'duration ${value.durationMs} ms'),
                _StatusChip(label: 'movements ${value.totalMovementCount}'),
                _StatusChip(label: 'VO2 avg ${value.vo2Avg.toStringAsFixed(1)}'),
                _StatusChip(label: 'VO2 min ${value.vo2Min.toStringAsFixed(1)}'),
                _StatusChip(label: 'VO2 max ${value.vo2Max.toStringAsFixed(1)}'),
                _StatusChip(label: 'VO2 samples ${value.vo2SampleCount}'),
                _StatusChip(label: 'RPE avg ${value.rpeAvg}'),
                _StatusChip(label: 'RPE samples ${value.rpeSampleCount}'),
                _StatusChip(label: 'load ${value.loadStatus}'),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final RecommendationInputPayload? recommendation;

  @override
  Widget build(BuildContext context) {
    final RecommendationInputPayload? value = recommendation;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionTitle(title: 'recommendation_input'),
          const SizedBox(height: 8),
          if (value == null)
            const _EmptyProtocolText()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusChip(label: 'status ${value.recommendationStatus}'),
                _StatusChip(label: 'low RPE ${value.hasLowRpeInterval}'),
                _StatusChip(label: 'high RPE ${value.hasHighRpeInterval}'),
                _StatusChip(label: 'load ${value.loadStatus}'),
                _StatusChip(label: 'VO2 trend ${value.vo2Trend}'),
                _StatusChip(label: 'low ${value.lowRpeTotalMs} ms'),
                _StatusChip(label: 'high ${value.highRpeTotalMs} ms'),
              ],
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.detail,
    required this.accentColor,
  });

  final String title;
  final String value;
  final String detail;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final double width = (MediaQuery.sizeOf(context).width - 52) / 2;
    return Container(
      width: width < 180 ? double.infinity : width,
      constraints: const BoxConstraints(minHeight: 168),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _EmptyProtocolText extends StatelessWidget {
  const _EmptyProtocolText();

  @override
  Widget build(BuildContext context) {
    return Text(
      '等待 BLE protocol data',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xFFF8FAFC),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/history_page.dart';
import 'package:vo2_flutter/screens/live_fitness_page.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/workout_history_repository.dart';

class TrainingHomeScreen extends StatefulWidget {
  const TrainingHomeScreen({
    super.key,
    required this.connectionController,
    required this.protocolSession,
    required this.profile,
    this.historyRepository = const WorkoutHistoryRepository(),
  });

  static const String routeName = '/home';

  final ReceiverConnectionController connectionController;
  final DeviceProtocolSession protocolSession;
  final UserProfile profile;
  final WorkoutHistoryRepository historyRepository;

  @override
  State<TrainingHomeScreen> createState() => _TrainingHomeScreenState();
}

class _TrainingHomeScreenState extends State<TrainingHomeScreen> {
  WorkoutHistoryEntry? _latestEntry;

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_handleStateChanged);
    widget.protocolSession.addListener(_handleStateChanged);
    unawaited(_loadLatestEntry());
  }

  @override
  void didUpdateWidget(TrainingHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionController != widget.connectionController) {
      oldWidget.connectionController.removeListener(_handleStateChanged);
      widget.connectionController.addListener(_handleStateChanged);
    }
    if (oldWidget.protocolSession != widget.protocolSession) {
      oldWidget.protocolSession.removeListener(_handleStateChanged);
      widget.protocolSession.addListener(_handleStateChanged);
    }
    if (oldWidget.profile != widget.profile) {
      unawaited(_loadLatestEntry());
    }
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_handleStateChanged);
    widget.protocolSession.removeListener(_handleStateChanged);
    super.dispose();
  }

  void _handleStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLatestEntry() async {
    final WorkoutHistoryEntry? latest = await widget.historyRepository.latest();
    if (!mounted) return;
    setState(() {
      _latestEntry = latest;
    });
  }

  bool get _readyForWorkout {
    final AppStatusPayload? status = widget.protocolSession.latestAppStatus;
    return widget.protocolSession.calibrationState ==
            DeviceProtocolCalibrationState.completed ||
        status?.startWorkoutAvailable == true;
  }

  String get _primaryLabel {
    if (!widget.connectionController.isConnected) return '連接手環開始訓練';
    if (!_readyForWorkout) return '完成 30 秒校正';
    return '開始即時訓練';
  }

  void _handlePrimaryPressed() {
    if (!widget.connectionController.isConnected) {
      Navigator.of(context).pushNamed(ConnectionScreen.routeName);
      return;
    }
    if (!_readyForWorkout) {
      Navigator.of(context).pushNamed(CalibrationScreen.routeName);
      return;
    }
    Navigator.of(context).pushNamed(LiveFitnessPage.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VO2 訓練')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 860;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(child: _hero(context)),
                              const SizedBox(width: 18),
                              Expanded(child: _secondaryColumn(context)),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _hero(context),
                              const SizedBox(height: 16),
                              _secondaryColumn(context),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return _ProductCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '準備好把每一下變成可追蹤的體能進步。',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '系統會先確認連線與校正狀態，訓練中只顯示你需要的節奏、動作與疲勞提醒。',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _StatusPill(
                icon: Icons.person_rounded,
                label: widget.profile.displayName,
                positive: true,
              ),
              _StatusPill(
                icon: widget.connectionController.isConnected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_searching_rounded,
                label: widget.connectionController.isConnected
                    ? '手環已連線'
                    : '等待連線',
                positive: widget.connectionController.isConnected,
              ),
              _StatusPill(
                icon: Icons.speed_rounded,
                label: _readyForWorkout ? '已可開始訓練' : '建議先校正',
                positive: _readyForWorkout,
              ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _handlePrimaryPressed,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_primaryLabel),
          ),
        ],
      ),
    );
  }

  Widget _secondaryColumn(BuildContext context) {
    final WorkoutHistoryEntry? latest = _latestEntry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProductCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '上次訓練',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (latest == null)
                const Text('還沒有紀錄。完成第一堂訓練後，這裡會顯示 VO2、RPE 與主要動作。')
              else ...<Widget>[
                Text(
                  '${latest.durationLabel} · ${latest.totalReps} 下 · 平均 VO2 ${latest.vo2Avg.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  latest.activeMovements
                      .map(
                        (MovementSummary movement) =>
                            '${movement.exerciseLabel} ${movement.reps} 下',
                      )
                      .join('、'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ProductCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(HistoryPage.routeName),
                icon: const Icon(Icons.history_rounded),
                label: const Text('查看歷史'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(DashboardPage.routeName),
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('進階診斷'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.positive,
  });

  final IconData icon;
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final Color tone = positive
        ? const Color(0xFF0F766E)
        : const Color(0xFFB45309);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: tone),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: tone, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.child});

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

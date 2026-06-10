import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/exercise_illustration.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/ppg_waveform_card.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/screens/workout_review_page.dart';
import 'package:vo2_flutter/sensor_processing.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/widgets/metric_card.dart';
import 'package:vo2_flutter/widgets/muscle_map_card.dart';
import 'package:vo2_flutter/workout_history_repository.dart';

class LiveFitnessPage extends StatefulWidget {
  const LiveFitnessPage({
    super.key,
    required this.protocolSession,
    required this.profile,
    this.connectionController,
    this.historyRepository = const WorkoutHistoryRepository(),
  });

  static const String routeName = '/live';

  final DeviceProtocolSession protocolSession;
  final UserProfile profile;
  final ReceiverConnectionController? connectionController;
  final WorkoutHistoryRepository historyRepository;

  @override
  State<LiveFitnessPage> createState() => _LiveFitnessPageState();
}

class _LiveFitnessPageState extends State<LiveFitnessPage> {
  static const Duration _summaryWaitTimeout = Duration(seconds: 9);

  bool _workoutStarted = false;
  bool _isSending = false;
  bool _isEndingWorkout = false;
  bool _hasSavedEndingWorkout = false;
  bool _usedFallbackSummary = false;
  bool _showPpgDetail = false;
  int _selectedPpgChannel = 0;
  DateTime? _startedAt;
  Timer? _summaryWaitTimer;
  final List<PpgFrame> _ppgFrames = <PpgFrame>[];

  @override
  void initState() {
    super.initState();
    widget.protocolSession.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(LiveFitnessPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protocolSession != widget.protocolSession) {
      oldWidget.protocolSession.removeListener(_handleSessionChanged);
      widget.protocolSession.addListener(_handleSessionChanged);
    }
  }

  @override
  void dispose() {
    _summaryWaitTimer?.cancel();
    widget.protocolSession.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    final DeviceSensorPayload? sample =
        widget.protocolSession.latestSensorSample;
    if (sample != null && sample.ppgChannels.isNotEmpty) {
      _ppgFrames.add(
        PpgFrame(
          receivedAt: DateTime.now(),
          values: sample.ppgChannels.take(5).toList(),
        ),
      );
      if (_ppgFrames.length > 240) {
        _ppgFrames.removeRange(0, _ppgFrames.length - 240);
      }
    }
    if (_isEndingWorkout &&
        widget.protocolSession.latestWorkoutSummary != null) {
      unawaited(_saveEndedWorkout(useFallback: false));
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startWorkout() async {
    setState(() {
      _isSending = true;
    });
    final bool sent = await widget.protocolSession.sendStartWorkout();
    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (sent) {
        _workoutStarted = true;
        _isEndingWorkout = false;
        _hasSavedEndingWorkout = false;
        _usedFallbackSummary = false;
        _startedAt = DateTime.now();
      }
    });
  }

  Future<void> _endWorkout() async {
    setState(() {
      _isSending = true;
      _isEndingWorkout = true;
      _usedFallbackSummary = false;
    });
    await widget.protocolSession.sendEndWorkout();
    if (!mounted) return;
    setState(() {
      _isSending = false;
    });

    if (widget.protocolSession.latestWorkoutSummary != null) {
      await _saveEndedWorkout(useFallback: false);
      return;
    }

    _summaryWaitTimer?.cancel();
    _summaryWaitTimer = Timer(_summaryWaitTimeout, () {
      unawaited(_saveEndedWorkout(useFallback: true));
    });
  }

  Future<void> _saveEndedWorkout({required bool useFallback}) async {
    if (_hasSavedEndingWorkout) {
      return;
    }
    _hasSavedEndingWorkout = true;
    _summaryWaitTimer?.cancel();

    final WorkoutHistoryEntry entry = await widget.historyRepository.add(
      _buildEntry(forceFallback: useFallback),
    );
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _isEndingWorkout = false;
      _workoutStarted = false;
      _usedFallbackSummary = useFallback;
    });
    Navigator.of(
      context,
    ).pushNamed(WorkoutReviewPage.routeName, arguments: entry.id);
  }

  WorkoutHistoryEntry _buildEntry({required bool forceFallback}) {
    final WorkoutSummaryPayload? summary =
        widget.protocolSession.latestWorkoutSummary;
    final RecommendationInputPayload? recommendation =
        widget.protocolSession.latestRecommendationInput;
    if (!forceFallback && summary != null) {
      return WorkoutHistoryEntry.fromProtocol(
        summary: summary,
        profile: widget.profile,
        recommendationInput: recommendation,
      );
    }
    final ClassifierResultPayload? classifier =
        widget.protocolSession.latestClassifierResult;
    final int movementId =
        protocolMovementExercises.containsKey(classifier?.movementId)
        ? classifier!.movementId
        : 0;
    return WorkoutHistoryEntry.fallbackFromLive(
      profile: widget.profile,
      startedAt: _startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
      movementId: movementId,
      reps: classifier?.reps ?? 0,
      sets: classifier?.sets ?? 0,
      vo2: widget.protocolSession.latestVo2Prediction?.vo2MlKgMin,
      rpeAlert: widget.protocolSession.latestRpeAlert,
      recommendationInput: recommendation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeviceProtocolSession session = widget.protocolSession;
    final ClassifierResultPayload? classifier = session.latestClassifierResult;
    final int movementId =
        protocolMovementExercises.containsKey(classifier?.movementId)
        ? classifier!.movementId
        : 0;
    final ExerciseType exercise = exerciseForProtocolMovement(movementId);
    final double? vo2 = session.latestVo2Prediction?.vo2MlKgMin;
    final int reps = classifier?.reps ?? 0;
    final int sets = classifier?.sets ?? 0;
    final RpeAlertPayload? rpeAlert = session.latestRpeAlert;
    final ErrorPayload? error = session.protocolError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('即時訓練'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed(DashboardPage.routeName),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('診斷'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 960;
            final Widget primary = _primaryColumn(
              context,
              exercise,
              vo2,
              reps,
              sets,
              rpeAlert,
              error,
              _isEndingWorkout,
            );
            final Widget secondary = _secondaryColumn(context, exercise);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(flex: 5, child: primary),
                              const SizedBox(width: 18),
                              Expanded(flex: 4, child: secondary),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              primary,
                              const SizedBox(height: 16),
                              secondary,
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

  Widget _primaryColumn(
    BuildContext context,
    ExerciseType exercise,
    double? vo2,
    int reps,
    int sets,
    RpeAlertPayload? rpeAlert,
    ErrorPayload? error,
    bool isEndingWorkout,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (error != null) ...<Widget>[
          _AlertBanner(
            icon: Icons.warning_amber_rounded,
            title: '裝置回報需要注意',
            message: '請先暫停動作，確認手環配戴與連線狀態。',
            tone: const Color(0xFFB45309),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.connectionController != null &&
            !widget.connectionController!.isConnected) ...<Widget>[
          const _AlertBanner(
            icon: Icons.bluetooth_disabled_rounded,
            title: '手環連線中斷',
            message: '請靠近裝置並返回連線頁重新連接，已收到的訓練資料會保留。',
            tone: Color(0xFFB45309),
          ),
          const SizedBox(height: 12),
        ],
        if (rpeAlert != null) ...<Widget>[
          _AlertBanner(
            icon: Icons.monitor_heart_rounded,
            title: rpeAlert.rpe >= 8 ? '強度偏高，放慢節奏' : '強度偏低，可穩定加壓',
            message: _friendlyRpeMessage(rpeAlert),
            tone: rpeAlert.rpe >= 8
                ? const Color(0xFFBE123C)
                : const Color(0xFF0F766E),
          ),
          const SizedBox(height: 12),
        ],
        if (isEndingWorkout) ...<Widget>[
          const _AlertBanner(
            icon: Icons.hourglass_top_rounded,
            title: '正在整理本次訓練',
            message: '已送出結束訓練，正在等待手環回傳完整摘要。若等待過久，會先用目前資料建立回顧。',
            tone: Color(0xFF0E7490),
          ),
          const SizedBox(height: 12),
        ] else if (_usedFallbackSummary) ...<Widget>[
          const _AlertBanner(
            icon: Icons.info_outline_rounded,
            title: '已用目前資料建立回顧',
            message: '手環摘要回傳較慢，這次回顧先採用訓練中已收到的數據。',
            tone: Color(0xFFB45309),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 420,
          child: ExerciseIllustrationCard(
            exercise: exercise,
            isActive: _workoutStarted,
            repetitions: reps,
            statusText: _workoutStarted
                ? '保持呼吸節奏，讓每一下完整可控。'
                : '按下開始後，手環會同步追蹤動作與 VO2。',
            onRepCompleted: () {},
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              title: '即時 VO2',
              value: vo2 == null ? '--' : vo2.toStringAsFixed(1),
              unit: 'ml/kg/min',
              tone: const Color(0xFF0E7490),
            ),
            MetricCard(
              title: '目前動作',
              value: '$reps',
              unit: '${exercise.label} · $sets 組',
              tone: const Color(0xFFF97316),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ControlCard(
          canWrite: widget.protocolSession.canWriteCommands,
          workoutStarted: _workoutStarted,
          isEndingWorkout: _isEndingWorkout,
          isSending: _isSending,
          onStart: () => unawaited(_startWorkout()),
          onEnd: () => unawaited(_endWorkout()),
        ),
      ],
    );
  }

  Widget _secondaryColumn(BuildContext context, ExerciseType exercise) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MuscleMapCard(highlighted: exercise.muscleGroups.toSet()),
        const SizedBox(height: 14),
        _ProductPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '訓練提示',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '目前辨識為 ${exercise.label}。穩定速度比追求最快更重要，讓每次推、拉、蹲都回到完整起點。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showPpgDetail = !_showPpgDetail;
                  });
                },
                icon: const Icon(Icons.show_chart_rounded),
                label: Text(_showPpgDetail ? '收合心率訊號細節' : '查看心率訊號細節'),
              ),
            ],
          ),
        ),
        if (_showPpgDetail) ...<Widget>[
          const SizedBox(height: 14),
          PpgWaveformCard(
            frames: _ppgFrames,
            selectedChannel: _selectedPpgChannel,
            onChannelSelected: (int channel) {
              setState(() {
                _selectedPpgChannel = channel;
              });
            },
            window: const Duration(seconds: 10),
          ),
        ],
      ],
    );
  }

  String _friendlyRpeMessage(RpeAlertPayload alert) {
    if (alert.rpe >= 8) {
      return '主觀強度已到 ${alert.rpe}/10。先把速度放慢，下一組再恢復輸出。';
    }
    if (alert.rpe <= 4) {
      return '目前強度 ${alert.rpe}/10，若動作穩定，可以逐步提高節奏。';
    }
    return '目前強度 ${alert.rpe}/10，維持這個呼吸節奏。';
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.canWrite,
    required this.workoutStarted,
    required this.isEndingWorkout,
    required this.isSending,
    required this.onStart,
    required this.onEnd,
  });

  final bool canWrite;
  final bool workoutStarted;
  final bool isEndingWorkout;
  final bool isSending;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return _ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isEndingWorkout
                ? '等待手環摘要'
                : workoutStarted
                ? '訓練進行中'
                : '準備開始',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            isEndingWorkout
                ? '正在整理 VO2、RPE 與動作拆解，請稍候。'
                : canWrite
                ? '開始與結束會同步送到手環，保留完整訓練摘要。'
                : '請先完成手環連線，才能開始訓練。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: !canWrite || workoutStarted || isSending
                    ? null
                    : onStart,
                icon: isSending && !workoutStarted
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('開始訓練'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    !canWrite || !workoutStarted || isSending || isEndingWorkout
                    ? null
                    : onEnd,
                icon: (isSending && workoutStarted) || isEndingWorkout
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_rounded),
                label: const Text('結束並查看回顧'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: tone),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(color: tone, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPanel extends StatelessWidget {
  const _ProductPanel({required this.child});

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
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

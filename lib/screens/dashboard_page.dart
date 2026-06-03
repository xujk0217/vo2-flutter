import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/exercise_illustration.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/ppg_waveform_card.dart';
import 'package:vo2_flutter/receiver/classic_bluetooth_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_connection_controller.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/sensor_processing.dart';
import 'package:vo2_flutter/user_profile.dart';
import 'package:vo2_flutter/widgets/connection_card.dart';
import 'package:vo2_flutter/widgets/metric_card.dart';
import 'package:vo2_flutter/widgets/muscle_map_card.dart';
import 'package:vo2_flutter/widgets/profile_settings_dialog.dart';

const String kReferenceDeviceAddress = 'D8:74:EF:D3:55:5F';
const Duration kPpgWindow = Duration(seconds: 10);

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    ReceiverConnectionController? connectionController,
    DeviceProtocolSession? protocolSession,
  }) : _connectionController = connectionController,
       _protocolSession = protocolSession;

  static const String routeName = '/dashboard';

  final ReceiverConnectionController? _connectionController;
  final DeviceProtocolSession? _protocolSession;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final CsvSensorSampleParser _sampleParser = const CsvSensorSampleParser();
  final Random _random = Random();
  late final ReceiverConnectionController _connectionController;
  late final bool _ownsConnectionController;
  DeviceProtocolSession? _protocolSession;
  late ExerciseType _exercise;
  late MotionEstimator _estimator;

  Timer? _vo2Ticker;
  Timer? _countdownTimer;
  final List<Timer> _warningTimers = <Timer>[];

  bool get _isConnected => _connectionController.isConnected;

  UserProfile _userProfile = UserProfile.defaults;
  WorkoutPhase _workoutPhase = WorkoutPhase.idle;
  double _rawEstimatedVo2 = 0;
  double _estimatedVo2 = 0;
  double _signalScore = 0;
  double _motionScore = 0;
  int _animatedRepetitions = 0;
  int _sampleCount = 0;
  int _selectedPpgChannel = 0;
  int _totalWorkoutRepetitions = 0;
  int _currentExerciseRepetitions = 0;
  int _warningDelayInputSeconds = 10;
  int _movementQualityLevel = 4;
  DateTime? _lastSampleAt;
  DateTime? _lastAnimatedRepAt;
  DateTime? _sessionStartedAt;
  DateTime? _activeWorkoutStartedAt;
  DateTime? _currentExerciseSegmentStartedAt;
  DateTime? _currentInstabilityStartedAt;
  DateTime? _unstableUntilAt;
  double _sessionRepLift = 0.18;
  double _sessionWaveA = 0.5;
  double _sessionWaveB = 0.28;
  double _sessionPhase = 0;
  Duration _currentSegmentUnstableAccumulated = Duration.zero;
  final List<int> _scheduledWarningSeconds = <int>[];
  final Set<int> _triggeredWarningSeconds = <int>{};
  final List<WorkoutSegment> _completedSegments = <WorkoutSegment>[];
  final List<PpgFrame> _ppgFrames = <PpgFrame>[];

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
    _connectionController
      ..setDataListener(_handleReceiverData)
      ..addListener(_handleConnectionChanged);
    _protocolSession = widget._protocolSession;
    _protocolSession?.addListener(_handleProtocolSessionChanged);
    _exercise = randomExercise();
    _estimator = MotionEstimator(exercise: _exercise);
    _refreshEstimatedVo2();
    _vo2Ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshEstimatedVo2();
        _refreshMovementQuality();
      });
    });
    unawaited(_loadProfile());
    unawaited(_bootstrap());
  }

  bool get _isWorkoutRunning => _workoutPhase == WorkoutPhase.active;
  bool get _isWorkoutPreparing => _workoutPhase == WorkoutPhase.countdown;
  double get _displayVo2 =>
      _protocolSession?.latestVo2Prediction?.vo2MlKgMin ?? _estimatedVo2;
  bool get _hasProtocolVo2Prediction =>
      _protocolSession?.latestVo2Prediction != null;
  bool get _shouldShowVo2Metric =>
      _shouldShowMetrics || _hasProtocolVo2Prediction;
  bool get _hasWorkoutSession =>
      _workoutPhase != WorkoutPhase.idle || _sessionStartedAt != null;
  bool get _shouldShowMetrics {
    if (!_isWorkoutRunning || _activeWorkoutStartedAt == null) {
      return false;
    }
    return DateTime.now().difference(_activeWorkoutStartedAt!).inSeconds >= 10;
  }

  Future<void> _loadProfile() async {
    final UserProfile profile = await UserProfile.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _userProfile = profile;
      _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
    });
  }

  Future<void> _bootstrap() async {
    await _connectionController.bootstrap();
  }

  Future<void> _loadBondedDevices() async {
    await _connectionController.refreshDevices();
  }

  Future<void> _toggleConnection() async {
    await _connectionController.toggleConnection();
  }

  void _handleConnectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (!_connectionController.isConnected && _hasWorkoutSession) {
        _cancelWorkoutSession();
        _refreshEstimatedVo2();
      }
    });
  }

  void _handleProtocolSessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleReceiverData(ReceiverDataEvent event) {
    if (!mounted) {
      return;
    }

    if (DeviceProtocolJsonParser.tryParse(event.payload) != null) {
      return;
    }

    final SensorSample? sample = _sampleParser.tryParse(event.payload);
    if (sample == null) {
      _connectionController.reportStatus('已收到原始資料，但格式尚未解析成功。');
      return;
    }

    final DerivedMetrics metrics = _estimator.absorb(sample);
    setState(() {
      _signalScore = metrics.signalScore;
      _motionScore = metrics.motionScore;
      _sampleCount += 1;
      _lastSampleAt = DateTime.now();
      _appendPpgSample(sample.ppg);
      _refreshEstimatedVo2();
    });
  }

  void _appendPpgSample(List<double> values) {
    final DateTime now = DateTime.now();
    _ppgFrames.add(
      PpgFrame(receivedAt: now, values: List<double>.from(values)),
    );
    final DateTime cutoff = now.subtract(kPpgWindow);
    _ppgFrames.removeWhere(
      (PpgFrame frame) => frame.receivedAt.isBefore(cutoff),
    );
  }

  void _advanceExercise() {
    final int currentIndex = exerciseCatalog.indexOf(_exercise);
    final int nextIndex = (currentIndex + 1) % exerciseCatalog.length;
    setState(() {
      if (_hasWorkoutSession) {
        _closeCurrentExerciseSegment();
      }
      _exercise = exerciseCatalog[nextIndex];
      _estimator = MotionEstimator(exercise: _exercise);
      if (_hasWorkoutSession) {
        _currentExerciseSegmentStartedAt = DateTime.now();
        _currentExerciseRepetitions = 0;
        _animatedRepetitions = 0;
        _lastAnimatedRepAt = null;
      }
      _signalScore = 0;
      _motionScore = 0;
      _sampleCount = 0;
      _lastSampleAt = null;
      _ppgFrames.clear();
    });
  }

  void _handleAnimationRepCompleted() {
    if (!mounted || !_isWorkoutRunning) {
      return;
    }
    setState(() {
      _lastAnimatedRepAt = DateTime.now();
      _animatedRepetitions += 1;
      _currentExerciseRepetitions += 1;
      _totalWorkoutRepetitions += 1;
      _refreshEstimatedVo2();
    });
  }

  double _applyProfileAdjustment(double rawVo2) {
    final double effort = max(rawVo2 - 8.0, 0);
    double multiplier = 1.0;
    multiplier += (_userProfile.heightCm - 170) * 0.0015;
    multiplier -= (_userProfile.weightKg - 70) * 0.0022;
    multiplier -= max(_userProfile.age - 30, 0) * 0.0018;
    switch (_userProfile.sex) {
      case UserSex.male:
        multiplier += 0.025;
      case UserSex.female:
        multiplier -= 0.025;
      case UserSex.other:
        break;
    }
    final double adjustedEffort = effort * multiplier.clamp(0.82, 1.18);
    return (8.0 + adjustedEffort).clamp(8.0, 30.0);
  }

  void _refreshEstimatedVo2() {
    _rawEstimatedVo2 = _computeExerciseVo2();
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
  }

  int _fatigueLevel() {
    final double normalized = ((_displayVo2 - 8.0) / 22.0).clamp(0.0, 1.0);
    return (1 + (normalized * 9)).round().clamp(1, 10);
  }

  String _fatigueLabel() {
    return _fatigueLabelFor(_fatigueLevel());
  }

  String _fatigueLabelFor(int level) {
    if (level <= 2) {
      return '很低';
    }
    if (level <= 4) {
      return '偏低';
    }
    if (level <= 6) {
      return '中等';
    }
    if (level <= 8) {
      return '偏高';
    }
    return '很高';
  }

  String _movementQualityLabel() {
    switch (_movementQualityLevel) {
      case 1:
        return '失衡';
      case 2:
        return '偏晃';
      case 3:
        return '普通';
      case 4:
        return '穩定';
      case 5:
        return '很穩';
      default:
        return '--';
    }
  }

  Color _movementQualityBackground() {
    switch (_movementQualityLevel) {
      case 1:
        return const Color(0xFFFEE2E2);
      case 2:
        return const Color(0xFFFFEDD5);
      case 3:
        return const Color(0xFFFEF3C7);
      case 4:
        return const Color(0xFFDCFCE7);
      case 5:
        return const Color(0xFFCCFBF1);
      default:
        return Colors.white;
    }
  }

  Color _fatigueBackground() {
    final int level = _fatigueLevel();
    if (!_shouldShowVo2Metric) {
      return Colors.white;
    }
    if (level <= 3) {
      return const Color(0xFFE0F2FE);
    }
    if (level <= 6) {
      return const Color(0xFFFEF3C7);
    }
    if (level <= 8) {
      return const Color(0xFFFFEDD5);
    }
    return const Color(0xFFFEE2E2);
  }

  void _refreshMovementQuality() {
    if (!_isWorkoutRunning) {
      _movementQualityLevel = 4;
      return;
    }

    final DateTime now = DateTime.now();
    final int? nextWarningSeconds = _nextPendingWarningSeconds();
    if (_unstableUntilAt != null && now.isAfter(_unstableUntilAt!)) {
      if (_currentInstabilityStartedAt != null) {
        _currentSegmentUnstableAccumulated += _unstableUntilAt!.difference(
          _currentInstabilityStartedAt!,
        );
      }
      _currentInstabilityStartedAt = null;
      _unstableUntilAt = null;
    }

    int minLevel = 3;
    int maxLevel = 4;
    if (nextWarningSeconds != null) {
      final int remaining = nextWarningSeconds;
      if (remaining <= 5) {
        minLevel = 1;
        maxLevel = 2;
      } else if (remaining <= 10) {
        minLevel = 2;
        maxLevel = 3;
      } else {
        minLevel = 3;
        maxLevel = 4;
      }
    } else if (_currentInstabilityStartedAt != null ||
        _triggeredWarningSeconds.isNotEmpty) {
      final int randomRoll = _random.nextInt(100);
      if (randomRoll < 15) {
        minLevel = 1;
        maxLevel = 2;
      } else if (randomRoll < 55) {
        minLevel = 2;
        maxLevel = 3;
      } else {
        minLevel = 3;
        maxLevel = 4;
      }
    } else {
      final int randomRoll = _random.nextInt(100);
      if (randomRoll < 15) {
        minLevel = 4;
        maxLevel = 5;
      }
    }

    final int target = minLevel + _random.nextInt((maxLevel - minLevel) + 1);
    if (_movementQualityLevel < target) {
      _movementQualityLevel += 1;
    } else if (_movementQualityLevel > target) {
      _movementQualityLevel -= 1;
    }
    _movementQualityLevel = _movementQualityLevel.clamp(minLevel, maxLevel);
  }

  void _startWorkoutSession() {
    final DateTime now = DateTime.now();
    _sessionStartedAt = now;
    _currentExerciseSegmentStartedAt = now;
    _workoutPhase = WorkoutPhase.countdown;
    _lastAnimatedRepAt = null;
    _completedSegments.clear();
    _activeWorkoutStartedAt = null;
    _currentInstabilityStartedAt = null;
    _unstableUntilAt = null;
    _animatedRepetitions = 0;
    _currentExerciseRepetitions = 0;
    _totalWorkoutRepetitions = 0;
    _movementQualityLevel = 4;
    _currentSegmentUnstableAccumulated = Duration.zero;
    _triggeredWarningSeconds.clear();
    _sessionRepLift = 0.03 + (_random.nextDouble() * 0.03);
    _sessionWaveA = 0.16 + (_random.nextDouble() * 0.16);
    _sessionWaveB = 0.06 + (_random.nextDouble() * 0.12);
    _sessionPhase = _random.nextDouble() * pi * 2;
    _rawEstimatedVo2 = 8;
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
    _scheduleCountdown();
  }

  void _cancelWorkoutSession() {
    _countdownTimer?.cancel();
    _cancelWarningTimers();
    _workoutPhase = WorkoutPhase.idle;
    _sessionStartedAt = null;
    _activeWorkoutStartedAt = null;
    _currentExerciseSegmentStartedAt = null;
    _currentInstabilityStartedAt = null;
    _unstableUntilAt = null;
    _lastAnimatedRepAt = null;
    _animatedRepetitions = 0;
    _currentExerciseRepetitions = 0;
    _totalWorkoutRepetitions = 0;
    _completedSegments.clear();
    _currentSegmentUnstableAccumulated = Duration.zero;
    _triggeredWarningSeconds.clear();
    _movementQualityLevel = 4;
    _rawEstimatedVo2 = 8;
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
  }

  double _computeExerciseVo2() {
    if (!_isWorkoutRunning || _activeWorkoutStartedAt == null) {
      return 8;
    }
    final DateTime now = DateTime.now();
    final double elapsedSeconds =
        now.difference(_activeWorkoutStartedAt!).inMilliseconds / 1000;
    final double timeTrend = min(18.0, elapsedSeconds * 0.022);
    final double repetitionTrend = min(
      2.6,
      _totalWorkoutRepetitions * _sessionRepLift,
    );
    final double signalBoost = min(0.45, max(_signalScore - 4.8, 0) * 0.12);
    final double motionBoost = min(0.8, max(_motionScore - 0.9, 0) * 0.18);
    final double cadenceLift;
    if (_lastAnimatedRepAt == null) {
      cadenceLift = 0;
    } else {
      final double secondsSinceRep =
          now.difference(_lastAnimatedRepAt!).inMilliseconds / 1000;
      cadenceLift = max(0, 4 - secondsSinceRep) * 0.03;
    }
    final double waveA =
        sin((elapsedSeconds / 6.0) + _sessionPhase) * _sessionWaveA;
    final double waveB =
        sin(
          (elapsedSeconds / 3.1) +
              _sessionPhase +
              (_totalWorkoutRepetitions * 0.28),
        ) *
        _sessionWaveB;
    final double drift = min(0.9, elapsedSeconds / 600);

    return (8 +
            timeTrend +
            repetitionTrend +
            signalBoost +
            motionBoost +
            cadenceLift +
            waveA +
            waveB +
            drift)
        .clamp(8.0, 30.0);
  }

  void _scheduleCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _workoutPhase = WorkoutPhase.active;
        _activeWorkoutStartedAt = DateTime.now();
        _currentExerciseSegmentStartedAt ??= DateTime.now();
        _scheduleWarningTimers();
      });
    });
  }

  void _cancelWarningTimers() {
    for (final Timer timer in _warningTimers) {
      timer.cancel();
    }
    _warningTimers.clear();
  }

  int? _nextPendingWarningSeconds() {
    if (!_isWorkoutRunning || _activeWorkoutStartedAt == null) {
      return null;
    }
    final int elapsed = DateTime.now()
        .difference(_activeWorkoutStartedAt!)
        .inSeconds;
    final List<int> pending =
        _scheduledWarningSeconds
            .where(
              (int second) =>
                  !_triggeredWarningSeconds.contains(second) &&
                  second > elapsed,
            )
            .toList()
          ..sort();
    if (pending.isEmpty) {
      return null;
    }
    return pending.first - elapsed;
  }

  void _scheduleWarningTimers() {
    _cancelWarningTimers();
    if (_activeWorkoutStartedAt == null) {
      return;
    }
    final int elapsed = DateTime.now()
        .difference(_activeWorkoutStartedAt!)
        .inSeconds;
    final List<int> pending =
        _scheduledWarningSeconds
            .where(
              (int second) =>
                  !_triggeredWarningSeconds.contains(second) &&
                  second > elapsed,
            )
            .toList()
          ..sort();
    for (final int second in pending) {
      final int delay = max(1, second - elapsed);
      _warningTimers.add(
        Timer(Duration(seconds: delay), () {
          if (!mounted ||
              !_hasWorkoutSession ||
              _triggeredWarningSeconds.contains(second)) {
            return;
          }
          _triggeredWarningSeconds.add(second);
          _activateInstabilityWindow();
          unawaited(_showInstabilityAlert());
        }),
      );
    }
  }

  void _activateInstabilityWindow() {
    final DateTime now = DateTime.now();
    final Duration window = Duration(seconds: 8 + _random.nextInt(5));
    _currentInstabilityStartedAt ??= now;
    final DateTime candidateEnd = now.add(window);
    if (_unstableUntilAt == null || candidateEnd.isAfter(_unstableUntilAt!)) {
      _unstableUntilAt = candidateEnd;
    }
  }

  Future<void> _showInstabilityAlert() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('動作提醒'),
          content: Text('${_exercise.label} 目前看起來有些不穩定，可以先休息一下再繼續。'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _closeCurrentExerciseSegment() {
    final DateTime? startedAt = _currentExerciseSegmentStartedAt;
    if (startedAt == null) {
      return;
    }
    final DateTime now = DateTime.now();
    Duration unstableDuration = _currentSegmentUnstableAccumulated;
    if (_currentInstabilityStartedAt != null &&
        now.isAfter(_currentInstabilityStartedAt!)) {
      unstableDuration += now.difference(_currentInstabilityStartedAt!);
    }
    if (now.isAfter(startedAt)) {
      _completedSegments.add(
        WorkoutSegment(
          exercise: _exercise,
          startedAt: startedAt,
          endedAt: now,
          repetitions: _currentExerciseRepetitions,
          unstableDuration: unstableDuration,
        ),
      );
    }
    _currentInstabilityStartedAt = null;
    _unstableUntilAt = null;
    _currentSegmentUnstableAccumulated = Duration.zero;
  }

  Future<void> _handleStartWorkout() async {
    if (!_isConnected || _hasWorkoutSession) {
      return;
    }
    setState(() {
      _startWorkoutSession();
    });
  }

  Future<void> _handleEndWorkout() async {
    if (!_hasWorkoutSession) {
      return;
    }
    final DateTime startedAt = _sessionStartedAt ?? DateTime.now();
    final DateTime endedAt = DateTime.now();
    final double finalVo2 = _displayVo2;
    final int finalFatigue = _fatigueLevel();

    setState(() {
      _closeCurrentExerciseSegment();
      _countdownTimer?.cancel();
      _cancelWarningTimers();
      _workoutPhase = WorkoutPhase.idle;
      _sessionStartedAt = null;
      _activeWorkoutStartedAt = null;
      _currentExerciseSegmentStartedAt = null;
      _currentInstabilityStartedAt = null;
      _unstableUntilAt = null;
      _lastAnimatedRepAt = null;
      _animatedRepetitions = 0;
      _currentExerciseRepetitions = 0;
      _rawEstimatedVo2 = 8;
      _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
      _movementQualityLevel = 4;
      _currentSegmentUnstableAccumulated = Duration.zero;
    });

    await _showWorkoutSummary(
      startedAt: startedAt,
      endedAt: endedAt,
      finalVo2: finalVo2,
      finalFatigue: finalFatigue,
      segments: List<WorkoutSegment>.from(_completedSegments),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _completedSegments.clear();
      _totalWorkoutRepetitions = 0;
      _triggeredWarningSeconds.clear();
    });
  }

  Future<void> _confirmEndWorkout() async {
    if (!_hasWorkoutSession || !mounted) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('結束訓練'),
          content: const Text('確定要結束這次訓練嗎？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('確定'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _handleEndWorkout();
    }
  }

  Future<void> _showWorkoutSummary({
    required DateTime startedAt,
    required DateTime endedAt,
    required double finalVo2,
    required int finalFatigue,
    required List<WorkoutSegment> segments,
  }) async {
    final Set<MuscleGroup> allMuscles = <MuscleGroup>{};
    for (final WorkoutSegment segment in segments) {
      allMuscles.addAll(segment.exercise.muscleGroups);
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        MuscleGroup? selectedMuscle;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setModalState) {
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.86,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: ListView(
                    children: <Widget>[
                      Text(
                        '本次訓練摘要',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatClock(startedAt)} - ${_formatClock(endedAt)} ． ${(endedAt.difference(startedAt).inMinutes)} 分鐘',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: MetricCard(
                              title: '結束 VO2',
                              value: finalVo2.toStringAsFixed(1),
                              unit: 'ml/kg/min',
                              tone: const Color(0xFF0284C7),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              title: '疲勞指數',
                              value: finalFatigue.toString(),
                              unit: '/ 10 ${_fatigueLabelFor(finalFatigue)}',
                              tone: const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '完成動作',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      ...segments.map((WorkoutSegment segment) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x140F172A),
                                blurRadius: 18,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            children: <Widget>[
                              CircleAvatar(
                                backgroundColor: segment.exercise.endColor
                                    .withValues(alpha: 0.16),
                                foregroundColor: segment.exercise.endColor,
                                child: Icon(segment.exercise.icon),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      segment.exercise.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      segment.wasUnstable
                                          ? '${segment.repetitions} 次 ． ${segment.duration.inSeconds} 秒 ． 不穩定 ${segment.unstableDuration.inSeconds} 秒 (${(segment.unstableRatio * 100).round()}%)'
                                          : '${segment.repetitions} 次 ． ${segment.duration.inSeconds} 秒',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF64748B),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (segment.wasUnstable)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text('不穩定'),
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      Text(
                        '訓練肌群',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      MuscleMapCard(
                        highlighted: allMuscles,
                        selected: selectedMuscle,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allMuscles.map((MuscleGroup group) {
                          return FilterChip(
                            label: Text(group.label),
                            selected: selectedMuscle == group,
                            onSelected: (bool selected) {
                              setModalState(() {
                                selectedMuscle = selected ? group : null;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '建議與回饋',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      ..._buildWorkoutAdvice(segments, finalFatigue).map(
                        (String advice) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $advice'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> _buildWorkoutAdvice(
    List<WorkoutSegment> segments,
    int fatigueLevel,
  ) {
    final List<String> advice = <String>[];
    final List<String> tempoAdvice = <String>[
      '下次可以把離心階段放慢到 2 到 3 秒，讓肌肉張力更完整。',
      '向心發力可以再乾淨一點，想像用穩定而不是爆衝的方式把重量推起來。',
      '如果想讓刺激更扎實，可以維持離心慢、向心穩的節奏，不用急著搶速度。',
      '今天的節奏下次可以試著做成「向心 1 秒、離心 3 秒」，更容易感受到目標肌群。',
      '建議下次在離心時多控制底部位置，向心時再順暢發力，整體動作品質會更好。',
    ];
    if (segments.isEmpty) {
      advice.add('今天主要完成了連線與啟動流程，下次可以把單一動作做完整一組。');
      return advice;
    }
    final WorkoutSegment longestSegment = segments.reduce(
      (WorkoutSegment a, WorkoutSegment b) => a.duration >= b.duration ? a : b,
    );
    advice.add('${longestSegment.exercise.label} 是今天投入最久的動作，可以優先作為下次進步追蹤基準。');
    WorkoutSegment? unstableSegment;
    for (final WorkoutSegment segment in segments) {
      if (segment.unstableDuration > Duration.zero) {
        unstableSegment = segment;
        break;
      }
    }
    if (unstableSegment != null) {
      advice.add(
        '${unstableSegment.exercise.label} 有一段動作較不穩，下次可先降低重量 10% 左右，專注在軌跡與節奏。',
      );
    } else {
      advice.add('今天整體動作節奏穩定，可以下次小幅增加次數或延長每組時間。');
    }
    if (fatigueLevel >= 8) {
      advice.add('疲勞指數偏高，建議今天補充水分並安排較完整的恢復。');
    } else if (fatigueLevel >= 5) {
      advice.add('疲勞累積在可接受區間，下次可以維持強度並縮短組間休息。');
    } else {
      advice.add('今天負荷偏輕，若動作穩定，下次可以增加重量或每組次數。');
    }
    advice.add(tempoAdvice[_random.nextInt(tempoAdvice.length)]);
    return advice;
  }

  String _formatClock(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatWarningDelay(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    if (minutes == 0) {
      return '$seconds 秒';
    }
    return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
  }

  Future<void> _openProfileSettings() async {
    final UserProfile? updatedProfile = await showDialog<UserProfile>(
      context: context,
      builder: (BuildContext context) {
        return ProfileSettingsDialog(initialProfile: _userProfile);
      },
    );

    if (updatedProfile == null || !mounted) {
      return;
    }

    await updatedProfile.save();
    setState(() {
      _userProfile = updatedProfile;
      if (_rawEstimatedVo2 > 0) {
        _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
      }
    });
  }

  Future<void> _openSettingsSheet() async {
    int warningDelay = _warningDelayInputSeconds;
    List<int> scheduledWarnings = List<int>.from(_scheduledWarningSeconds)
      ..sort();

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return SafeArea(
                  child: FractionallySizedBox(
                    heightFactor: 0.9,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: ListView(
                        children: <Widget>[
                          Text(
                            '設定',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await _openProfileSettings();
                              if (mounted) {
                                setModalState(() {});
                              }
                            },
                            icon: const Icon(Icons.person_rounded),
                            label: const Text('編輯個人資料'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _advanceExercise();
                            },
                            icon: const Icon(Icons.skip_next_rounded),
                            label: const Text('切換到下一個動作'),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '警告跳出時間：${_formatWarningDelay(warningDelay)}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Slider(
                            value: warningDelay.toDouble(),
                            min: 10,
                            max: 600,
                            divisions: 59,
                            label: _formatWarningDelay(warningDelay),
                            onChanged: (double value) {
                              setModalState(() {
                                warningDelay = ((value / 10).round() * 10)
                                    .clamp(10, 600);
                              });
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(
                            scheduledWarnings.isEmpty
                                ? '尚未安排警告'
                                : '已設定於開始訓練後 ${scheduledWarnings.map(_formatWarningDelay).join('、')} 跳出警告',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              final List<int> next = <int>[
                                ...scheduledWarnings,
                                warningDelay,
                              ]..sort();
                              setState(() {
                                _warningDelayInputSeconds = warningDelay;
                                _scheduledWarningSeconds
                                  ..clear()
                                  ..addAll(next);
                              });
                              if (_isWorkoutRunning &&
                                  _activeWorkoutStartedAt != null) {
                                _scheduleWarningTimers();
                              }
                              setModalState(() {
                                scheduledWarnings = next;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已加入開始訓練後 ${_formatWarningDelay(warningDelay)} 的警告。',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.notification_important_rounded,
                            ),
                            label: const Text('安排不穩定警告'),
                          ),
                          if (scheduledWarnings.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: scheduledWarnings.map((int second) {
                                return InputChip(
                                  label: Text(_formatWarningDelay(second)),
                                  onDeleted: () {
                                    final List<int> next = List<int>.from(
                                      scheduledWarnings,
                                    )..remove(second);
                                    setState(() {
                                      _scheduledWarningSeconds
                                        ..clear()
                                        ..addAll(next);
                                      _triggeredWarningSeconds.remove(second);
                                    });
                                    if (_isWorkoutRunning &&
                                        _activeWorkoutStartedAt != null) {
                                      _scheduleWarningTimers();
                                    }
                                    setModalState(() {
                                      scheduledWarnings = next;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(
                            'PPG 波形',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          PpgWaveformCard(
                            frames: List<PpgFrame>.from(_ppgFrames),
                            selectedChannel: _selectedPpgChannel,
                            window: kPpgWindow,
                            onChannelSelected: (int index) {
                              setState(() {
                                _selectedPpgChannel = index;
                              });
                              setModalState(() {});
                            },
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _warningDelayInputSeconds = warningDelay;
                                _scheduledWarningSeconds
                                  ..clear()
                                  ..addAll(scheduledWarnings);
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('完成'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
        );
      },
    );
  }

  String _selectedDeviceName() {
    return _connectionController.selectedDeviceName();
  }

  @override
  void dispose() {
    _connectionController
      ..removeListener(_handleConnectionChanged)
      ..setDataListener(null);
    _protocolSession?.removeListener(_handleProtocolSessionChanged);
    _vo2Ticker?.cancel();
    _countdownTimer?.cancel();
    _cancelWarningTimers();
    if (_ownsConnectionController) {
      unawaited(_connectionController.disposeAsync());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _bootstrap,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'VO2 Motion Monitor',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '即時運動與疲勞監測',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _openSettingsSheet,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: '設定',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 360,
                child: ExerciseIllustrationCard(
                  exercise: _exercise,
                  isActive: _isWorkoutRunning,
                  repetitions: _animatedRepetitions,
                  statusText: _isWorkoutPreparing
                      ? '訓練進行中'
                      : _isWorkoutRunning
                      ? '訓練進行中'
                      : _isConnected
                      ? '按開始後進入訓練'
                      : '先連接裝置',
                  onRepCompleted: _handleAnimationRepCompleted,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: MetricCard(
                      title: '動作品質',
                      value: _isWorkoutRunning ? _movementQualityLabel() : '--',
                      unit: _isWorkoutRunning
                          ? '$_movementQualityLevel / 5'
                          : '--',
                      tone: const Color(0xFF0F766E),
                      backgroundColor: _isWorkoutRunning
                          ? _movementQualityBackground()
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      title: '疲勞指標 (VO2)',
                      value: _shouldShowVo2Metric
                          ? _fatigueLevel().toString()
                          : '--',
                      secondaryText: _shouldShowVo2Metric
                          ? 'VO2 ${_displayVo2.toStringAsFixed(1)}'
                          : null,
                      unit: _shouldShowVo2Metric
                          ? '/ 10 ${_fatigueLabel()}'
                          : '等待資料穩定',
                      tone: const Color(0xFFDC2626),
                      backgroundColor: _fatigueBackground(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: _hasWorkoutSession
                    ? FilledButton.tonalIcon(
                        onPressed: () {
                          unawaited(_confirmEndWorkout());
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(60),
                        ),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('結束訓練'),
                      )
                    : FilledButton.icon(
                        onPressed: !_isConnected
                            ? null
                            : () {
                                unawaited(_handleStartWorkout());
                              },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(60),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('開始訓練'),
                      ),
              ),
              const SizedBox(height: 24),
              ConnectionCard(
                devices: _connectionController.devices,
                selectedDeviceId: _connectionController.selectedDeviceId,
                bluetoothEnabled: _connectionController.bluetoothEnabled,
                permissionsGranted: _connectionController.permissionsGranted,
                statusMessage: _connectionController.statusMessage,
                isLoadingDevices: _connectionController.isLoadingDevices,
                isConnecting: _connectionController.isConnecting,
                isConnected: _connectionController.isConnected,
                onRefreshDevices: _loadBondedDevices,
                onRequestPermissions: _bootstrap,
                onConnectPressed: _toggleConnection,
                onDeviceChanged: (String? value) {
                  _connectionController.selectDevice(value);
                },
              ),
              const SizedBox(height: 22),
              Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.memory_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '裝置資訊',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('裝置：${_selectedDeviceName()}'),
                    const SizedBox(height: 4),
                    Text('已接收樣本：$_sampleCount'),
                    const SizedBox(height: 4),
                    Text('目前動作：${_exercise.label}'),
                    const SizedBox(height: 4),
                    Text('個人資料：${_userProfile.summary}'),
                    const SizedBox(height: 4),
                    Text(
                      '最後同步：${_lastSampleAt == null ? '--' : _lastSampleAt!.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

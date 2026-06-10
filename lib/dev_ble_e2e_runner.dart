import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/user_profile.dart';

class DevBleE2eRunnerApp extends StatefulWidget {
  const DevBleE2eRunnerApp({super.key});

  @override
  State<DevBleE2eRunnerApp> createState() => _DevBleE2eRunnerAppState();
}

class _DevBleE2eRunnerAppState extends State<DevBleE2eRunnerApp> {
  String _status = 'BLE_E2E starting';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    var exitCode = 0;
    try {
      await _runSkipWorkoutMatrix();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _runCalibrationMatrix();
      _log('PASS all functions');
    } catch (error, stackTrace) {
      exitCode = 1;
      _log('FAIL $error');
      stderr.writeln(stackTrace);
    } finally {
      await _finish(exitCode);
    }
  }

  Future<void> _runSkipWorkoutMatrix() async {
    final _BleE2ePhase phase = _BleE2ePhase(
      log: _log,
      phaseName: 'skip-workout',
    );
    await phase.start();
    try {
      await phase.ensureProfile();
      await phase.expectHealth();
      await phase.sendFitnessCommand(FitnessCommand.requestStatus, 500);
      await phase.expectStatus(
        label: 'status before skip',
        predicate: (AppStatusPayload status) {
          return status.profileReceived && !status.startWorkoutAvailable;
        },
      );
      await phase.sendFitnessCommand(FitnessCommand.skipCalibration, 1000);
      await phase.expectStatus(
        label: 'skip calibration',
        predicate: (AppStatusPayload status) {
          return status.profileReceived &&
              status.calibrationState == 4 &&
              status.calibrationProgressPct == 100 &&
              status.startWorkoutAvailable;
        },
      );
      await phase.sendFitnessCommand(FitnessCommand.requestStatus, 2000);
      await phase.expectStatus(
        label: 'request status',
        predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
      );
      await phase.sendFitnessCommand(FitnessCommand.startWorkout, 10000);
      await phase.expectStatus(
        label: 'start workout',
        predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
      );
      await phase.sendSensorSample(12000);
      await phase.expectNoErrorSinceLastCommand('sensor sample accepted');
      await phase.sendClassifierResult(
        hostTsMs: 15000,
        mode: 1,
        movementId: 2,
        reps: 12,
        sets: 3,
      );
      await phase.expectStatus(
        label: 'classifier result',
        predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
      );
      await phase.sendRpe(hostTsMs: 20000, rpe: 9);
      await phase.sendRpe(hostTsMs: 25000, rpe: 9);
      final RpeAlertPayload alert = await phase.expectRpeAlert();
      if (alert.alertType != 2 || alert.rpe != 9 || alert.durationMs < 5000) {
        throw StateError('unexpected RPE alert payload');
      }
      _log('PASS high RPE alert');
      await phase.sendFitnessCommand(FitnessCommand.endWorkout, 50000);
      final WorkoutSummaryPayload summary = await phase.expectWorkoutSummary();
      if (summary.durationMs != 40000 ||
          summary.totalMovementCount != 1 ||
          summary.repsByMovement[2] != 12 ||
          summary.setsByMovement[2] != 3 ||
          summary.rpeMax != 9 ||
          summary.rpeSampleCount < 2) {
        throw StateError('unexpected workout summary');
      }
      _log('PASS workout summary');
      final RecommendationInputPayload recommendation = await phase
          .expectRecommendationInput();
      if (!recommendation.hasHighRpeInterval ||
          recommendation.highRpeTotalMs < 5000 ||
          recommendation.hasLowRpeInterval) {
        throw StateError('unexpected recommendation input');
      }
      _log('PASS recommendation input');
      await phase.expectStatus(
        label: 'end workout status',
        predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
      );
      await phase.sendRpe(hostTsMs: 60000, rpe: 11);
      final ErrorPayload expectedError = await phase.expectError();
      if (expectedError.code != 15) {
        throw StateError(
          'unexpected invalid RPE error code ${expectedError.code}',
        );
      }
      _log('PASS invalid RPE error');
      await phase.sendProtocolDisconnect();
      _log('PASS protocol disconnect');
    } finally {
      await phase.stop();
    }
  }

  Future<void> _runCalibrationMatrix() async {
    final _BleE2ePhase phase = _BleE2ePhase(
      log: _log,
      phaseName: 'calibration',
    );
    await phase.start();
    try {
      await phase.ensureProfile();
      await phase.sendFrame(
        const DeviceFrame(
          messageType: DeviceMessageType.calibrationStart,
          seq: 0,
        ),
      );
      await phase.expectStatus(
        label: 'calibration start',
        timeout: const Duration(seconds: 8),
        predicate: (AppStatusPayload status) => status.calibrationState == 1,
      );
      await phase.expectCalibrationProgress();
      final CalibrationDonePayload done = await phase.expectCalibrationDone();
      if (done.durationMs == 0) {
        throw StateError('calibration_done duration was zero');
      }
      _log('PASS calibration done');
      await phase.expectStatus(
        label: 'calibration final status',
        timeout: const Duration(seconds: 8),
        predicate: (AppStatusPayload status) {
          return status.calibrationProgressPct == 100 &&
              status.startWorkoutAvailable;
        },
      );
      await phase.sendProtocolDisconnect();
      _log('PASS calibration protocol disconnect');
    } finally {
      await phase.stop();
    }
  }

  void _log(String message) {
    final String line = 'BLE_E2E $message';
    stdout.writeln(line);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = line;
    });
  }

  Future<void> _finish(int code) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(code);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_status),
          ),
        ),
      ),
    );
  }
}

class _BleE2ePhase {
  _BleE2ePhase({required this.log, required this.phaseName});

  final void Function(String message) log;
  final String phaseName;
  final BleReceiverTransport transport = BleReceiverTransport();
  late final DeviceProtocolSession session = DeviceProtocolSession(
    writer: transport,
  );
  final List<DeviceProtocolJsonResult> frames = <DeviceProtocolJsonResult>[];
  StreamSubscription<ReceiverTransportEvent>? _subscription;
  int _seq = 1;
  int _lastCommandIndex = 0;

  Future<void> start() async {
    _subscription = transport.events().listen((ReceiverTransportEvent event) {
      switch (event) {
        case ReceiverStatusEvent():
          log('$phaseName ${event.state}: ${event.message}');
        case ReceiverErrorEvent():
          log('$phaseName error ${event.code}: ${event.message}');
        case ReceiverDataEvent():
          final DeviceProtocolJsonResult? parsed =
              DeviceProtocolJsonParser.tryParse(event.payload);
          if (parsed != null) {
            frames.add(parsed);
          }
          unawaited(session.handleDataEvent(event));
      }
    });

    log('$phaseName requesting permissions');
    if (!await transport.requestPermissions().timeout(
      const Duration(seconds: 8),
    )) {
      throw StateError('BLE permission denied');
    }
    log('$phaseName checking adapter');
    if (!await transport.isEnabled().timeout(const Duration(seconds: 8))) {
      throw StateError('BLE adapter disabled');
    }

    log('$phaseName scanning');
    final List<ReceiverDeviceInfo> devices = await transport
        .getDevices()
        .timeout(const Duration(seconds: 45));
    log(
      '$phaseName saw ${devices.length}: ${devices.map((ReceiverDeviceInfo device) => '${device.name}/${device.id}').join(', ')}',
    );
    final ReceiverDeviceInfo board = devices.firstWhere(
      (ReceiverDeviceInfo device) =>
          DeviceBleUuids.isAcceptedAdvertisedName(device.name),
      orElse: () => throw StateError('BLE board not found'),
    );

    log('$phaseName connecting ${board.name}/${board.id}');
    await transport.connect(board.id).timeout(const Duration(seconds: 35));
    log('PASS $phaseName connect');
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await transport.disconnect();
    session.dispose();
  }

  Future<void> ensureProfile() async {
    final int start = frames.length;
    try {
      await expectMessage<ProfileAckPayload>(
        DeviceMessageType.profileAck,
        startIndex: start,
        timeout: const Duration(seconds: 3),
      );
    } on TimeoutException {
      log('$phaseName sending profile');
      final bool sent = await session.sendProfile(UserProfile.defaults);
      if (!sent) {
        throw StateError('profile was not written');
      }
      await expectMessage<ProfileAckPayload>(
        DeviceMessageType.profileAck,
        startIndex: start,
        timeout: const Duration(seconds: 10),
      );
    }
    log('PASS $phaseName profile/profile_ack');
  }

  Future<void> expectHealth() async {
    final int start = markCommand();
    log('$phaseName sending health request');
    if (!await session.sendHealthRequest()) {
      throw StateError('health request was not written');
    }
    await expectMessage<HealthResponsePayload>(
      DeviceMessageType.healthResponse,
      startIndex: start,
      timeout: const Duration(seconds: 25),
    );
    expectNoErrorSince(start, 'health request');
    log('PASS $phaseName health');
  }

  Future<void> sendProtocolDisconnect() {
    return session.sendProtocolDisconnect();
  }

  Future<void> sendFitnessCommand(FitnessCommand command, int hostTsMs) async {
    markCommand();
    await session.sendFitnessCommand(command, hostTimestampMs: hostTsMs);
  }

  Future<void> sendSensorSample(int hostTsMs) async {
    markCommand();
    await sendFrame(
      DeviceFrame(
        messageType: DeviceMessageType.sensorPpgImu,
        seq: _nextSeq(),
        payload: DeviceSensorPayload(
          hostTimestampUs: hostTsMs * 1000,
          ppgChannels: const <double>[
            1000,
            1002,
            1004,
            1006,
            1008,
            980,
            982,
            984,
            986,
            988,
          ],
          imuChannels: const <double>[0, 0, 1, 0.01, 0.02, 0.03, 0.1, 0.2, 0.3],
        ).encode(),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> sendClassifierResult({
    required int hostTsMs,
    required int mode,
    required int movementId,
    required int reps,
    required int sets,
  }) async {
    markCommand();
    await sendFrame(
      DeviceFrame(
        messageType: DeviceMessageType.classifierResult,
        seq: _nextSeq(),
        payload: _classifierPayload(
          hostTsMs: hostTsMs,
          mode: mode,
          movementId: movementId,
          reps: reps,
          sets: sets,
        ),
      ),
    );
  }

  Future<void> sendRpe({required int hostTsMs, required int rpe}) async {
    markCommand();
    await sendFrame(
      DeviceFrame(
        messageType: DeviceMessageType.rpe,
        seq: _nextSeq(),
        payload: _rpePayload(hostTsMs: hostTsMs, rpe: rpe),
      ),
    );
  }

  Future<void> sendFrame(DeviceFrame frame) {
    final DeviceFrame outbound = frame.seq == 0
        ? DeviceFrame(
            messageType: frame.messageType,
            seq: _nextSeq(),
            flags: frame.flags,
            payload: frame.payload,
          )
        : frame;
    return transport.writeFrame(outbound);
  }

  Future<AppStatusPayload> expectStatus({
    required String label,
    required bool Function(AppStatusPayload status) predicate,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final AppStatusPayload status = await expectMessage<AppStatusPayload>(
      DeviceMessageType.appStatus,
      startIndex: _lastCommandIndex,
      timeout: timeout,
      predicate: predicate,
    );
    expectNoErrorSince(_lastCommandIndex, label);
    log('PASS $phaseName $label');
    return status;
  }

  Future<RpeAlertPayload> expectRpeAlert() {
    return expectMessage<RpeAlertPayload>(
      DeviceMessageType.rpe,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<WorkoutSummaryPayload> expectWorkoutSummary() {
    return expectMessage<WorkoutSummaryPayload>(
      DeviceMessageType.workoutSummary,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<RecommendationInputPayload> expectRecommendationInput() {
    return expectMessage<RecommendationInputPayload>(
      DeviceMessageType.recommendationInput,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<ErrorPayload> expectError() {
    return expectMessage<ErrorPayload>(
      DeviceMessageType.error,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> expectCalibrationProgress() async {
    await expectMessage<CalibrationProgressPayload>(
      DeviceMessageType.calibrationProgress,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 12),
    );
    log('PASS $phaseName calibration progress');
  }

  Future<CalibrationDonePayload> expectCalibrationDone() {
    return expectMessage<CalibrationDonePayload>(
      DeviceMessageType.calibrationDone,
      startIndex: _lastCommandIndex,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<void> expectNoErrorSinceLastCommand(String label) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expectNoErrorSince(_lastCommandIndex, label);
    log('PASS $phaseName $label');
  }

  Future<T> expectMessage<T>(
    int messageType, {
    required int startIndex,
    required Duration timeout,
    bool Function(T payload)? predicate,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final DeviceProtocolJsonResult frame in frames.skip(startIndex)) {
        if (frame.messageType != messageType) {
          continue;
        }
        final Object? payload = frame.typedPayload;
        if (payload is! T) {
          continue;
        }
        if (predicate != null && !predicate(payload)) {
          continue;
        }
        return payload;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException(
      'timed out waiting for 0x${messageType.toRadixString(16)}',
      timeout,
    );
  }

  int markCommand() {
    _lastCommandIndex = frames.length;
    return _lastCommandIndex;
  }

  void expectNoErrorSince(int startIndex, String label) {
    for (final DeviceProtocolJsonResult frame in frames.skip(startIndex)) {
      if (frame.messageType == DeviceMessageType.error) {
        final Object? payload = frame.typedPayload;
        if (payload is ErrorPayload) {
          throw StateError(
            '$label returned error ${payload.code}: ${payload.message}',
          );
        }
        throw StateError('$label returned protocol error');
      }
    }
  }

  int _nextSeq() {
    final int seq = _seq;
    _seq = (_seq + 1) & 0xffff;
    return seq;
  }

  static Uint8List _classifierPayload({
    required int hostTsMs,
    required int mode,
    required int movementId,
    required int reps,
    required int sets,
  }) {
    final Uint8List bytes = Uint8List(14);
    ByteData.sublistView(bytes)
      ..setUint64(0, hostTsMs, Endian.little)
      ..setUint8(8, mode)
      ..setUint8(9, movementId)
      ..setUint16(10, reps, Endian.little)
      ..setUint16(12, sets, Endian.little);
    return bytes;
  }

  static Uint8List _rpePayload({required int hostTsMs, required int rpe}) {
    final Uint8List bytes = Uint8List(9);
    ByteData.sublistView(bytes)
      ..setUint64(0, hostTsMs, Endian.little)
      ..setUint8(8, rpe);
    return bytes;
  }
}

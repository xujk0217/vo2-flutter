import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/app.dart';
import 'package:vo2_flutter/receiver/ble_receiver_transport.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/live_fitness_page.dart';
import 'package:vo2_flutter/screens/workout_review_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'formal semantic UI hardware e2e covers skip-workout protocol matrix',
    (WidgetTester tester) async {
      final SemanticsHandle semanticsHandle = tester.ensureSemantics();
      final _RecordingBleTransport transport = _RecordingBleTransport();
      try {
        await _startAppAndCreateProfile(tester, transport, 'BLE Formal Skip');
        final int profileStart = transport.markInbound();
        await _tapBoardBySemantics(tester);
        await _pumpUntilFound(
          tester,
          find.byType(CalibrationScreen),
          const Duration(seconds: 35),
        );
        expect(find.text('30 秒靜止校正'), findsOneWidget);
        await transport.expectOutboundProfile();
        await transport.expectMessage<ProfileAckPayload>(
          DeviceMessageType.profileAck,
          startIndex: profileStart,
          timeout: const Duration(seconds: 12),
        );
        _pass('profile/profile_ack');

        final int healthStart = transport.markInbound();
        await transport.writeFrame(
          DeviceFrame(
            messageType: DeviceMessageType.healthRequest,
            seq: transport.nextSeq(),
          ),
        );
        await transport.expectMessage<HealthResponsePayload>(
          DeviceMessageType.healthResponse,
          startIndex: healthStart,
          timeout: const Duration(seconds: 25),
        );
        transport.expectNoErrorSince(healthStart, 'health');
        _pass('health');

        await transport.sendFitnessCommand(FitnessCommand.requestStatus, 500);
        await transport.expectStatus(
          label: 'status before skip',
          predicate: (AppStatusPayload status) {
            return status.profileReceived && !status.startWorkoutAvailable;
          },
        );

        final int skipStart = transport.markOutbound();
        await _tapSemantics(tester, '跳過校正');
        await _pumpUntilFound(
          tester,
          find.byType(LiveFitnessPage),
          const Duration(seconds: 20),
        );
        await transport.expectOutboundFitnessCommand(
          FitnessCommand.skipCalibration,
          startIndex: skipStart,
        );
        await transport.expectStatus(
          label: 'skip calibration',
          predicate: (AppStatusPayload status) {
            return status.profileReceived &&
                status.calibrationState == 4 &&
                status.calibrationProgressPct == 100 &&
                status.startWorkoutAvailable;
          },
        );

        await transport.sendFitnessCommand(FitnessCommand.requestStatus, 2000);
        await transport.expectStatus(
          label: 'request status',
          predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
        );

        final int startWorkoutStart = transport.markOutbound();
        await _tapSemantics(tester, '開始訓練');
        await transport.expectOutboundFitnessCommand(
          FitnessCommand.startWorkout,
          startIndex: startWorkoutStart,
        );
        await transport.expectStatus(
          label: 'start workout',
          predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
        );

        await transport.sendSensorSample(12000);
        await transport.expectNoErrorSinceLastCommand('sensor sample accepted');

        await transport.sendClassifierResult(
          hostTsMs: 15000,
          mode: 1,
          movementId: 2,
          reps: 12,
          sets: 3,
        );
        await transport.expectStatus(
          label: 'classifier result',
          predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
        );

        final int rpeStart = transport.markInbound();
        await transport.sendRpe(hostTsMs: 20000, rpe: 9, mark: false);
        await transport.sendRpe(hostTsMs: 25000, rpe: 9, mark: false);
        final RpeAlertPayload alert = await transport.expectRpeAlert(
          startIndex: rpeStart,
        );
        expect(alert.alertType, 2);
        expect(alert.rpe, 9);
        expect(alert.durationMs, greaterThanOrEqualTo(5000));
        _pass('high RPE alert');
        await _pumpUntilFound(
          tester,
          find.textContaining('強度偏高'),
          const Duration(seconds: 8),
        );

        final int endWorkoutStart = transport.markOutbound();
        await _tapSemantics(tester, '結束並查看回顧');
        await transport.expectOutboundFitnessCommand(
          FitnessCommand.endWorkout,
          startIndex: endWorkoutStart,
        );
        final WorkoutSummaryPayload summary = await transport
            .expectWorkoutSummary();
        expect(summary.durationMs, greaterThan(0));
        expect(summary.totalMovementCount, 1);
        expect(summary.repsByMovement[2], 12);
        expect(summary.setsByMovement[2], 3);
        expect(summary.rpeMax, 9);
        expect(summary.rpeSampleCount, greaterThanOrEqualTo(2));
        _pass('workout summary');

        final RecommendationInputPayload recommendation = await transport
            .expectRecommendationInput();
        expect(recommendation.hasHighRpeInterval, isTrue);
        expect(recommendation.highRpeTotalMs, greaterThanOrEqualTo(5000));
        expect(recommendation.hasLowRpeInterval, isFalse);
        _pass('recommendation input');

        await _pumpUntilFound(
          tester,
          find.byType(WorkoutReviewPage),
          const Duration(seconds: 12),
        );
        expect(find.text('訓練回顧'), findsOneWidget);
        await transport.expectStatus(
          label: 'end workout status',
          predicate: (AppStatusPayload status) => status.startWorkoutAvailable,
        );

        await transport.sendRpe(hostTsMs: 60000, rpe: 11);
        final ErrorPayload expectedError = await transport.expectError();
        expect(expectedError.code, 15);
        _pass('invalid RPE error');

        await transport.sendProtocolDisconnect();
        _pass('protocol disconnect');
      } finally {
        semanticsHandle.dispose();
        await transport.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'formal semantic UI hardware e2e covers calibration lifecycle',
    (WidgetTester tester) async {
      final SemanticsHandle semanticsHandle = tester.ensureSemantics();
      final _RecordingBleTransport transport = _RecordingBleTransport();
      try {
        await _startAppAndCreateProfile(
          tester,
          transport,
          'BLE Formal Calibration',
        );
        final int profileStart = transport.markInbound();
        await _tapBoardBySemantics(tester);
        await _pumpUntilFound(
          tester,
          find.byType(CalibrationScreen),
          const Duration(seconds: 35),
        );
        await transport.expectOutboundProfile();
        await transport.expectMessage<ProfileAckPayload>(
          DeviceMessageType.profileAck,
          startIndex: profileStart,
          timeout: const Duration(seconds: 12),
        );
        _pass('calibration profile/profile_ack');

        final int calibrationStart = transport.markOutbound();
        await _tapSemantics(tester, '開始校正');
        await transport.expectOutboundMessageType(
          DeviceMessageType.calibrationStart,
          startIndex: calibrationStart,
        );
        await transport.expectStatus(
          label: 'calibration start',
          timeout: const Duration(seconds: 8),
          predicate: (AppStatusPayload status) => status.calibrationState == 1,
        );

        await transport.expectCalibrationProgress();
        await _pumpUntilFound(
          tester,
          find.textContaining('校正中'),
          const Duration(seconds: 12),
        );

        final CalibrationDonePayload done = await transport
            .expectCalibrationDone();
        expect(done.durationMs, greaterThan(0));
        _pass('calibration done');
        await _pumpUntilFound(
          tester,
          find.text('校正完成！'),
          const Duration(seconds: 45),
        );
        await transport.expectStatus(
          label: 'calibration final status',
          timeout: const Duration(seconds: 8),
          predicate: (AppStatusPayload status) {
            return status.calibrationProgressPct == 100 &&
                status.startWorkoutAvailable;
          },
        );

        await _tapSemantics(tester, '開始即時訓練');
        await _pumpUntilFound(
          tester,
          find.byType(LiveFitnessPage),
          const Duration(seconds: 12),
        );

        await transport.sendProtocolDisconnect();
        _pass('calibration protocol disconnect');
      } finally {
        semanticsHandle.dispose();
        await transport.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _startAppAndCreateProfile(
  WidgetTester tester,
  _RecordingBleTransport transport,
  String profileName,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(Vo2MotionApp(transportFactory: (_) => transport));
  await tester.pump(const Duration(milliseconds: 300));

  expect(find.text('先選擇使用者'), findsOneWidget);
  await tester.enterText(find.byType(TextFormField).at(0), profileName);
  await tester.enterText(find.byType(TextFormField).at(1), '180');
  await tester.enterText(find.byType(TextFormField).at(2), '75');
  await tester.enterText(find.byType(TextFormField).at(3), '35');
  await tester.enterText(find.byType(TextFormField).at(4), '44');
  await _tapSemantics(tester, '儲存並連接 BLE');
  await _pumpUntilFound(tester, find.text('裝置連線'), const Duration(seconds: 12));
  await _pumpUntilFound(
    tester,
    _boardSemanticsFinder(),
    const Duration(seconds: 35),
  );
}

Future<void> _tapBoardBySemantics(WidgetTester tester) {
  return _tapSemantics(
    tester,
    RegExp('(${DeviceBleUuids.advertisedNames.join('|')})'),
  );
}

Future<void> _tapSemantics(WidgetTester tester, Pattern label) async {
  final Finder finder = find.bySemanticsLabel(label);
  expect(finder, findsAtLeastNWidgets(1));
  Finder? tappableFinder;
  for (int index = 0; index < finder.evaluate().length; index += 1) {
    final Finder candidate = finder.at(index);
    final SemanticsData data = tester
        .getSemantics(candidate)
        .getSemanticsData();
    if (data.hasAction(SemanticsAction.tap)) {
      tappableFinder = candidate;
      break;
    }
  }
  if (tappableFinder == null) {
    fail('Expected semantics node `$label` to expose tap action.');
  }
  debugPrint('SEMANTIC_TAP $label');
  await tester.tap(tappableFinder);
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _boardSemanticsFinder() {
  return find.bySemanticsLabel(
    RegExp('(${DeviceBleUuids.advertisedNames.join('|')})'),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder.');
}

void _pass(String label) {
  debugPrint('FORMAL_BLE_UI PASS $label');
}

class _RecordingBleTransport
    implements ReceiverTransport, DeviceProtocolFrameWriter {
  _RecordingBleTransport() {
    _subscription = _delegate.events().listen((ReceiverTransportEvent event) {
      switch (event) {
        case ReceiverStatusEvent():
          statuses.add('${event.state}: ${event.message}');
        case ReceiverErrorEvent():
          errors.add('${event.code}: ${event.message}');
        case ReceiverDataEvent():
          final DeviceProtocolJsonResult? parsed =
              DeviceProtocolJsonParser.tryParse(event.payload);
          if (parsed != null) {
            inboundFrames.add(parsed);
          }
      }
      _events.add(event);
    });
  }

  final BleReceiverTransport _delegate = BleReceiverTransport();
  final StreamController<ReceiverTransportEvent> _events =
      StreamController<ReceiverTransportEvent>.broadcast();
  final List<DeviceProtocolJsonResult> inboundFrames =
      <DeviceProtocolJsonResult>[];
  final List<DeviceFrame> outboundFrames = <DeviceFrame>[];
  final List<String> statuses = <String>[];
  final List<String> errors = <String>[];
  StreamSubscription<ReceiverTransportEvent>? _subscription;
  int _seq = 4000;
  int _lastInboundCommandIndex = 0;

  @override
  Future<void> connect(String deviceId) => _delegate.connect(deviceId);

  @override
  Future<void> disconnect() => _delegate.disconnect();

  @override
  Stream<ReceiverTransportEvent> events() => _events.stream;

  @override
  Future<List<ReceiverDeviceInfo>> getDevices() => _delegate.getDevices();

  @override
  Future<bool> isEnabled() => _delegate.isEnabled();

  @override
  Future<bool> requestPermissions() => _delegate.requestPermissions();

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    outboundFrames.add(frame);
    await _delegate.writeFrame(frame);
  }

  int nextSeq() {
    final int seq = _seq;
    _seq = (_seq + 1) & 0xffff;
    return seq;
  }

  int markInbound() => inboundFrames.length;

  int markOutbound() => outboundFrames.length;

  Future<void> dispose() async {
    try {
      await _delegate.writeFrame(
        DeviceFrame(messageType: DeviceMessageType.disconnect, seq: nextSeq()),
      );
    } catch (_) {
      // The formal test may fail before a BLE connection exists.
    }
    await _subscription?.cancel();
    await _delegate.disconnect();
    await _events.close();
  }

  Future<void> expectOutboundProfile() async {
    await expectOutboundMessageType(
      DeviceMessageType.profile,
      startIndex: 0,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<void> expectOutboundMessageType(
    int messageType, {
    required int startIndex,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _waitForOutbound(
      startIndex: startIndex,
      timeout: timeout,
      predicate: (DeviceFrame frame) => frame.messageType == messageType,
      label: '0x${messageType.toRadixString(16)}',
    );
  }

  Future<void> expectOutboundFitnessCommand(
    FitnessCommand command, {
    required int startIndex,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _waitForOutbound(
      startIndex: startIndex,
      timeout: timeout,
      predicate: (DeviceFrame frame) {
        return frame.messageType == DeviceMessageType.fitnessCommand &&
            frame.payload.isNotEmpty &&
            frame.payload.first == command.value;
      },
      label: command.name,
    );
  }

  Future<void> _waitForOutbound({
    required int startIndex,
    required Duration timeout,
    required bool Function(DeviceFrame frame) predicate,
    required String label,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final DeviceFrame frame in outboundFrames.skip(startIndex)) {
        if (predicate(frame)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('timed out waiting for outbound $label', timeout);
  }

  Future<void> sendProtocolDisconnect() {
    return writeFrame(
      DeviceFrame(messageType: DeviceMessageType.disconnect, seq: nextSeq()),
    );
  }

  Future<void> sendFitnessCommand(FitnessCommand command, int hostTsMs) async {
    _lastInboundCommandIndex = markInbound();
    await writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.fitnessCommand,
        seq: nextSeq(),
        payload: FitnessCommandPayload(
          command: command,
          hostTimestampMs: hostTsMs,
        ).encode(),
      ),
    );
  }

  Future<void> sendSensorSample(int hostTsMs) async {
    _lastInboundCommandIndex = markInbound();
    await writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.sensorPpgImu,
        seq: nextSeq(),
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
    _lastInboundCommandIndex = markInbound();
    await writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.classifierResult,
        seq: nextSeq(),
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

  Future<void> sendRpe({
    required int hostTsMs,
    required int rpe,
    bool mark = true,
  }) async {
    if (mark) {
      _lastInboundCommandIndex = markInbound();
    }
    await writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.rpe,
        seq: nextSeq(),
        payload: _rpePayload(hostTsMs: hostTsMs, rpe: rpe),
      ),
    );
  }

  Future<AppStatusPayload> expectStatus({
    required String label,
    required bool Function(AppStatusPayload status) predicate,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final AppStatusPayload status = await expectMessage<AppStatusPayload>(
      DeviceMessageType.appStatus,
      startIndex: _lastInboundCommandIndex,
      timeout: timeout,
      predicate: predicate,
    );
    expectNoErrorSince(_lastInboundCommandIndex, label);
    _pass(label);
    return status;
  }

  Future<RpeAlertPayload> expectRpeAlert({int? startIndex}) {
    return expectMessage<RpeAlertPayload>(
      DeviceMessageType.rpe,
      startIndex: startIndex ?? _lastInboundCommandIndex,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<WorkoutSummaryPayload> expectWorkoutSummary() {
    return expectMessage<WorkoutSummaryPayload>(
      DeviceMessageType.workoutSummary,
      startIndex: _lastInboundCommandIndex,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<RecommendationInputPayload> expectRecommendationInput() {
    return expectMessage<RecommendationInputPayload>(
      DeviceMessageType.recommendationInput,
      startIndex: _lastInboundCommandIndex,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<ErrorPayload> expectError() {
    return expectMessage<ErrorPayload>(
      DeviceMessageType.error,
      startIndex: _lastInboundCommandIndex,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> expectCalibrationProgress() async {
    await expectMessage<CalibrationProgressPayload>(
      DeviceMessageType.calibrationProgress,
      startIndex: _lastInboundCommandIndex,
      timeout: const Duration(seconds: 12),
    );
    _pass('calibration progress');
  }

  Future<CalibrationDonePayload> expectCalibrationDone() {
    return expectMessage<CalibrationDonePayload>(
      DeviceMessageType.calibrationDone,
      startIndex: _lastInboundCommandIndex,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<void> expectNoErrorSinceLastCommand(String label) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expectNoErrorSince(_lastInboundCommandIndex, label);
    _pass(label);
  }

  Future<T> expectMessage<T>(
    int messageType, {
    required int startIndex,
    required Duration timeout,
    bool Function(T payload)? predicate,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final DeviceProtocolJsonResult frame in inboundFrames.skip(
        startIndex,
      )) {
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
      'timed out waiting for 0x${messageType.toRadixString(16)}. '
      'Statuses: $statuses Errors: $errors',
      timeout,
    );
  }

  void expectNoErrorSince(int startIndex, String label) {
    for (final DeviceProtocolJsonResult frame in inboundFrames.skip(
      startIndex,
    )) {
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

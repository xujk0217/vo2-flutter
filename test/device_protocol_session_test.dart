import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/device_protocol_session.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/user_profile.dart';

/// Fake writer that records every [DeviceFrame] written.
class _FakeDeviceProtocolFrameWriter implements DeviceProtocolFrameWriter {
  final List<DeviceFrame> writtenFrames = <DeviceFrame>[];

  @override
  Future<void> writeFrame(DeviceFrame frame) async {
    writtenFrames.add(frame);
  }
}

/// Build a [ReceiverDataEvent] with a BLE JSON payload for the given
/// message type, sequence number, and raw payload bytes.
ReceiverDataEvent _bleDataEvent(int messageType, int seq, List<int> payload) {
  return ReceiverDataEvent(
    payload: jsonEncode(<String, dynamic>{
      'messageType': messageType,
      'flags': 0,
      'seq': seq,
      'payloadBase64': base64Encode(Uint8List.fromList(payload)),
    }),
  );
}

const UserProfile _defaultProfile = UserProfile(
  heightCm: 170,
  weightKg: 70,
  age: 30,
  sex: UserSex.male,
);

Uint8List _appStatusPayload() {
  final Uint8List payload = Uint8List(9);
  ByteData.sublistView(payload)
    ..setUint8(0, 1)
    ..setUint8(1, 2)
    ..setUint8(2, 3)
    ..setUint8(3, 1)
    ..setUint8(4, 4)
    ..setUint8(5, 55)
    ..setUint16(6, 99, Endian.little)
    ..setUint8(8, 1);
  return payload;
}

Uint8List _workoutSummaryPayload() {
  final Uint8List payload = Uint8List(77);
  final ByteData data = ByteData.sublistView(payload);
  data
    ..setUint64(0, 1000, Endian.little)
    ..setUint64(8, 4000, Endian.little)
    ..setUint64(16, 3000, Endian.little)
    ..setUint8(24, 2);
  for (int i = 0; i < 8; i += 1) {
    data
      ..setUint16(25 + i * 2, 10 + i, Endian.little)
      ..setUint16(41 + i * 2, 1 + i, Endian.little);
  }
  data
    ..setFloat32(57, 30.5, Endian.little)
    ..setFloat32(61, 44.5, Endian.little)
    ..setFloat32(65, 38.5, Endian.little)
    ..setUint16(69, 7, Endian.little)
    ..setUint8(71, 3)
    ..setUint8(72, 8)
    ..setUint8(73, 5)
    ..setUint16(74, 6, Endian.little)
    ..setUint8(76, 2);
  return payload;
}

Uint8List _recommendationInputPayload() {
  final Uint8List payload = Uint8List(13);
  ByteData.sublistView(payload)
    ..setUint8(0, 1)
    ..setUint8(1, 1)
    ..setUint8(2, 0)
    ..setUint8(3, 2)
    ..setUint8(4, 3)
    ..setUint32(5, 12000, Endian.little)
    ..setUint32(9, 34000, Endian.little);
  return payload;
}

Uint8List _rpeSamplePayload() {
  final Uint8List payload = Uint8List(9);
  ByteData.sublistView(payload)
    ..setUint64(0, 987654321, Endian.little)
    ..setUint8(8, 6);
  return payload;
}

Uint8List _rpeAlertPayload(String message) {
  final List<int> messageBytes = utf8.encode(message);
  final Uint8List payload = Uint8List(16 + messageBytes.length);
  ByteData.sublistView(payload)
    ..setUint64(0, 123456789, Endian.little)
    ..setUint8(8, 2)
    ..setUint8(9, 9)
    ..setUint32(10, 45000, Endian.little)
    ..setUint16(14, messageBytes.length, Endian.little);
  payload.setRange(16, payload.length, messageBytes);
  return payload;
}

void main() {
  group('DeviceProtocolSession', () {
    // ── canWriteCommands / writerless ──────────────────────────────────────

    test(
      'canWriteCommands false without writer; startCalibration fails',
      () async {
        final DeviceProtocolSession session = DeviceProtocolSession(
          initialProfile: _defaultProfile,
        );

        expect(session.canWriteCommands, isFalse);
        expect(session.calibrationState, DeviceProtocolCalibrationState.idle);

        final bool started = await session.startCalibration();
        expect(started, isFalse);
        expect(session.calibrationState, DeviceProtocolCalibrationState.idle);
      },
    );

    // ── sendProfile ───────────────────────────────────────────────────────

    test(
      'sendProfile writes profile frame with sex mapping; seq starts at 1',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        // male → 0, seq = 1
        final bool sent = await session.sendProfile(
          const UserProfile(
            heightCm: 175,
            weightKg: 68,
            age: 25,
            sex: UserSex.male,
          ),
        );
        expect(sent, isTrue);
        expect(writer.writtenFrames, hasLength(1));
        expect(
          writer.writtenFrames.single.messageType,
          DeviceMessageType.profile,
        );
        expect(writer.writtenFrames.single.seq, 1);
        expect(writer.writtenFrames.single.payload[5], 0);

        // female → 1, seq = 2
        await session.sendProfile(
          const UserProfile(
            heightCm: 165,
            weightKg: 55,
            age: 28,
            sex: UserSex.female,
          ),
        );
        expect(writer.writtenFrames, hasLength(2));
        expect(writer.writtenFrames[1].seq, 2);
        expect(writer.writtenFrames[1].payload[5], 1);

        // other → 2, seq = 3
        await session.sendProfile(
          const UserProfile(
            heightCm: 170,
            weightKg: 70,
            age: 30,
            sex: UserSex.other,
          ),
        );
        expect(writer.writtenFrames, hasLength(3));
        expect(writer.writtenFrames[2].seq, 3);
        expect(writer.writtenFrames[2].payload[5], 2);
      },
    );

    test('sendProfile payload matches DeviceProfilePayload encoding', () async {
      final writer = _FakeDeviceProtocolFrameWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
        initialProfile: _defaultProfile,
      );

      await session.sendProfile(
        const UserProfile(
          heightCm: 175,
          weightKg: 68,
          age: 25,
          sex: UserSex.male,
        ),
      );

      final Uint8List expectedPayload = DeviceProfilePayload(
        heightCm: 175,
        weightKg: 68,
        age: 25,
        sex: 0,
      ).encode();
      expect(
        writer.writtenFrames.single.payload,
        orderedEquals(expectedPayload),
      );
    });

    test(
      'sendHealthRequest and sendProtocolDisconnect write empty frames with next sequence',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        expect(await session.sendHealthRequest(), isTrue);
        expect(await session.sendProtocolDisconnect(), isTrue);

        expect(writer.writtenFrames, hasLength(2));
        expect(
          writer.writtenFrames[0].messageType,
          DeviceMessageType.healthRequest,
        );
        expect(writer.writtenFrames[0].seq, 1);
        expect(writer.writtenFrames[0].payload, isEmpty);
        expect(
          writer.writtenFrames[1].messageType,
          DeviceMessageType.disconnect,
        );
        expect(writer.writtenFrames[1].seq, 2);
        expect(writer.writtenFrames[1].payload, isEmpty);
      },
    );

    test(
      'writerless helper commands return false and write no frames',
      () async {
        final DeviceProtocolSession session = DeviceProtocolSession(
          initialProfile: _defaultProfile,
        );

        expect(await session.sendHealthRequest(), isFalse);
        expect(await session.sendProtocolDisconnect(), isFalse);
        expect(session.canWriteCommands, isFalse);
      },
    );

    // ── profile request response ──────────────────────────────────────────

    test('empty profile request triggers profile response', () async {
      final writer = _FakeDeviceProtocolFrameWriter();
      const UserProfile profile = UserProfile(
        heightCm: 180,
        weightKg: 75,
        age: 35,
        sex: UserSex.female,
      );
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
        initialProfile: profile,
      );

      // Device sends empty profile request.
      await session.handleDataEvent(
        _bleDataEvent(DeviceMessageType.profile, 0, <int>[]),
      );

      expect(writer.writtenFrames, hasLength(1));
      final DeviceFrame frame = writer.writtenFrames.single;
      expect(frame.messageType, DeviceMessageType.profile);
      expect(frame.seq, 1);

      final Uint8List expectedPayload = DeviceProfilePayload(
        heightCm: 180,
        weightKg: 75,
        age: 35,
        sex: 1, // female
      ).encode();
      expect(frame.payload, orderedEquals(expectedPayload));
      expect(session.lastProtocolMessageType, DeviceMessageType.profile);
    });

    // ── passive protocol state ─────────────────────────────────────────────

    test(
      'stores passive payloads and protocol message types without writes',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.profileAck, 1, <int>[]),
        );
        expect(session.latestProfileAck, isA<ProfileAckPayload>());
        expect(session.lastProtocolMessageType, DeviceMessageType.profileAck);

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.healthResponse, 2, <int>[0x03]),
        );
        expect(session.latestHealthResponse, isA<HealthResponsePayload>());
        expect(session.latestHealthResponse!.vo2Running, isTrue);
        expect(session.latestHealthResponse!.sensorRunning, isTrue);
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.healthResponse,
        );

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.appStatus, 3, _appStatusPayload()),
        );
        expect(session.latestAppStatus, isA<AppStatusPayload>());
        expect(session.latestAppStatus!.calibrationProgressPct, 55);
        expect(session.lastProtocolMessageType, DeviceMessageType.appStatus);

        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.workoutSummary,
            4,
            _workoutSummaryPayload(),
          ),
        );
        expect(session.latestWorkoutSummary, isA<WorkoutSummaryPayload>());
        expect(session.latestWorkoutSummary!.durationMs, 3000);
        expect(session.latestWorkoutSummary!.repsByMovement.first, 10);
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.workoutSummary,
        );

        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.recommendationInput,
            5,
            _recommendationInputPayload(),
          ),
        );
        expect(
          session.latestRecommendationInput,
          isA<RecommendationInputPayload>(),
        );
        expect(session.latestRecommendationInput!.lowRpeTotalMs, 12000);
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.recommendationInput,
        );

        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.rpe,
            6,
            _rpeAlertPayload('slow down'),
          ),
        );
        expect(session.latestRpeAlert, isA<RpeAlertPayload>());
        expect(session.latestRpeAlert!.message, 'slow down');
        expect(session.lastProtocolMessageType, DeviceMessageType.rpe);
        expect(session.lastUnsupportedMessageType, isNull);
        expect(writer.writtenFrames, isEmpty);
      },
    );

    // ── startCalibration ──────────────────────────────────────────────────

    test(
      'startCalibration writes calibrationStart, returns true, sets running',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        final bool started = await session.startCalibration();
        expect(started, isTrue);
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );

        expect(writer.writtenFrames, hasLength(1));
        final DeviceFrame frame = writer.writtenFrames.single;
        expect(frame.messageType, DeviceMessageType.calibrationStart);
        expect(frame.seq, 1);
        expect(frame.payload, isEmpty);
      },
    );

    test(
      'startCalibration with profile writes profile then calibrationStart',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        const UserProfile newProfile = UserProfile(
          heightCm: 190,
          weightKg: 85,
          age: 40,
          sex: UserSex.male,
        );

        final bool started = await session.startCalibration(
          profile: newProfile,
        );
        expect(started, isTrue);
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );

        expect(writer.writtenFrames, hasLength(2));
        expect(writer.writtenFrames[0].messageType, DeviceMessageType.profile);
        expect(writer.writtenFrames[0].seq, 1);
        expect(writer.writtenFrames[0].payload[5], 0); // male
        expect(
          writer.writtenFrames[1].messageType,
          DeviceMessageType.calibrationStart,
        );
        expect(writer.writtenFrames[1].seq, 2);
        expect(writer.writtenFrames[1].payload, isEmpty);
      },
    );

    // ── calibration_progress ──────────────────────────────────────────────

    test('calibration_progress updates elapsed, hr, and progress', () async {
      final writer = _FakeDeviceProtocolFrameWriter();
      final DeviceProtocolSession session = DeviceProtocolSession(
        writer: writer,
        initialProfile: _defaultProfile,
      );

      await session.startCalibration();
      writer.writtenFrames.clear();

      // elapsedMs = 15000, hrEstimate = 78
      final Uint8List progressPayload = Uint8List(5);
      ByteData.sublistView(progressPayload)
        ..setUint32(0, 15000, Endian.little)
        ..setUint8(4, 78);

      await session.handleDataEvent(
        _bleDataEvent(
          DeviceMessageType.calibrationProgress,
          1,
          progressPayload,
        ),
      );

      expect(session.calibrationState, DeviceProtocolCalibrationState.running);
      expect(session.calibrationElapsedMs, 15000);
      expect(session.calibrationHrEstimate, 78);
      expect(session.calibrationProgress, closeTo(0.5, 0.001)); // 15000/30000
      expect(writer.writtenFrames, isEmpty); // no frames written for progress
    });

    test(
      'calibration_progress clamps to 1.0 when elapsed exceeds 30000',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.startCalibration();

        final Uint8List progressPayload = Uint8List(5);
        ByteData.sublistView(progressPayload)
          ..setUint32(0, 50000, Endian.little) // exceeds 30000
          ..setUint8(4, 80);

        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.calibrationProgress,
            2,
            progressPayload,
          ),
        );

        expect(session.calibrationProgress, closeTo(1.0, 0.001));
        expect(session.calibrationElapsedMs, 50000);
        expect(session.calibrationHrEstimate, 80);
      },
    );

    // ── calibration_done ──────────────────────────────────────────────────

    test(
      'calibration_done sets state to completed and exposes payload',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.startCalibration();

        final Uint8List donePayload = Uint8List(9);
        ByteData.sublistView(donePayload)
          ..setUint8(0, 64) // avgHrBpm
          ..setUint8(1, 88) // qualityScore
          ..setUint16(2, 240, Endian.little) // sampleCount
          ..setUint32(4, 30000, Endian.little) // durationMs
          ..setUint8(8, 0); // status

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.calibrationDone, 3, donePayload),
        );

        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.completed,
        );
        expect(session.calibrationDone, isA<CalibrationDonePayload>());
        expect(session.calibrationDone!.avgHrBpm, 64);
        expect(session.calibrationDone!.qualityScore, 88);
        expect(session.calibrationDone!.sampleCount, 240);
        expect(session.calibrationDone!.durationMs, 30000);
        expect(session.calibrationDone!.status, 0);
      },
    );

    // ── non-calibration events are ignored/passive ────────────────────────

    test(
      'sensor_ppg_imu during running calibration does not change state or writes',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.startCalibration();
        writer.writtenFrames.clear();

        final Uint8List progressPayload = Uint8List(5);
        ByteData.sublistView(progressPayload)
          ..setUint32(0, 15000, Endian.little)
          ..setUint8(4, 78);
        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.calibrationProgress,
            1,
            progressPayload,
          ),
        );

        final Uint8List predictionPayload = Uint8List(12);
        ByteData.sublistView(predictionPayload)
          ..setUint64(0, 123456789, Endian.little)
          ..setFloat32(8, 42.5, Endian.little);
        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.vo2Prediction, 2, predictionPayload),
        );
        writer.writtenFrames.clear();

        await session.handleDataEvent(
          _bleDataEvent(
            DeviceMessageType.sensorPpgImu,
            0,
            List<int>.generate(93, (int i) => i),
          ),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(session.calibrationElapsedMs, 15000);
        expect(session.calibrationHrEstimate, 78);
        expect(session.calibrationProgress, closeTo(0.5, 0.001));
        expect(session.latestVo2Prediction!.vo2MlKgMin, closeTo(42.5, 0.001));
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.vo2Prediction,
        );
        expect(writer.writtenFrames, isEmpty);
      },
    );

    test(
      'rpe sample, classifierResult, and fitnessCommand stay passive',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.startCalibration();
        writer.writtenFrames.clear();

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.rpe, 0, _rpeSamplePayload()),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(session.latestRpeAlert, isNull);
        expect(session.lastProtocolMessageType, DeviceMessageType.rpe);
        expect(session.lastUnsupportedMessageType, isNull);
        expect(writer.writtenFrames, isEmpty);

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.classifierResult, 0, <int>[]),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.classifierResult,
        );
        expect(
          session.lastUnsupportedMessageType,
          DeviceMessageType.classifierResult,
        );
        expect(writer.writtenFrames, isEmpty);

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.fitnessCommand, 0, <int>[]),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(
          session.lastProtocolMessageType,
          DeviceMessageType.fitnessCommand,
        );
        expect(
          session.lastUnsupportedMessageType,
          DeviceMessageType.fitnessCommand,
        );
        expect(session.calibrationProgress, isNull);
        expect(session.latestVo2Prediction, isNull);
        expect(writer.writtenFrames, isEmpty);
      },
    );

    // ── protocol error ────────────────────────────────────────────────────

    test(
      'error event sets calibration state to error and exposes ErrorPayload',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        // code=8, message='not_streaming'
        final Uint8List errorPayload = Uint8List.fromList(<int>[
          0x08,
          0x00,
          ...'not_streaming'.codeUnits,
        ]);

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.error, 0, errorPayload),
        );

        expect(session.calibrationState, DeviceProtocolCalibrationState.error);
        expect(session.protocolError, isA<ErrorPayload>());
        expect(session.protocolError!.code, 8);
        expect(session.protocolError!.message, 'not_streaming');
      },
    );

    test(
      'vo2_prediction updates latest VO2 prediction and notifies listeners',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );
        int notifications = 0;
        session.addListener(() {
          notifications += 1;
        });
        final Uint8List predictionPayload = Uint8List(12);
        ByteData.sublistView(predictionPayload)
          ..setUint64(0, 123456789, Endian.little)
          ..setFloat32(8, 42.5, Endian.little);

        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.vo2Prediction, 4, predictionPayload),
        );

        expect(session.latestVo2Prediction, isA<Vo2PredictionPayload>());
        expect(session.latestVo2Prediction!.timestampNs, 123456789);
        expect(session.latestVo2Prediction!.vo2MlKgMin, closeTo(42.5, 0.001));
        expect(session.calibrationState, DeviceProtocolCalibrationState.idle);
        expect(writer.writtenFrames, isEmpty);
        expect(notifications, 1);
      },
    );
  });
}

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
    });

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

    // ── non-calibration events are ignored ────────────────────────────────

    test(
      'sensor_ppg_imu, rpe, classifierResult, fitnessCommand are no-ops',
      () async {
        final writer = _FakeDeviceProtocolFrameWriter();
        final DeviceProtocolSession session = DeviceProtocolSession(
          writer: writer,
          initialProfile: _defaultProfile,
        );

        await session.startCalibration();
        writer.writtenFrames.clear();

        // sensor_ppg_imu
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
        expect(writer.writtenFrames, isEmpty);

        // rpe
        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.rpe, 0, <int>[]),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(writer.writtenFrames, isEmpty);

        // classifierResult
        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.classifierResult, 0, <int>[]),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
        expect(writer.writtenFrames, isEmpty);

        // fitnessCommand
        await session.handleDataEvent(
          _bleDataEvent(DeviceMessageType.fitnessCommand, 0, <int>[]),
        );
        expect(
          session.calibrationState,
          DeviceProtocolCalibrationState.running,
        );
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
  });
}

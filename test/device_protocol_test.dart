import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';

void main() {
  const DeviceProtocolCodec codec = DeviceProtocolCodec();

  group('DeviceProtocolCodec', () {
    test('encodes and decodes empty calibration_start frame', () {
      final Uint8List bytes = codec.encode(
        const DeviceFrame(
          messageType: DeviceMessageType.calibrationStart,
          seq: 7,
        ),
      );

      expect(bytes[0], 0x54);
      expect(bytes[1], 0x42);
      expect(bytes[2], DeviceProtocolConstants.version);
      expect(bytes[3], 0x10);
      expect(bytes[4], 0x00);
      expect(bytes[8], 0x00);
      expect(bytes[9], 0x00);

      final DeviceFrame decoded = codec.decode(bytes);
      expect(decoded.messageType, DeviceMessageType.calibrationStart);
      expect(decoded.seq, 7);
      expect(decoded.flags, 0);
      expect(decoded.payload, isEmpty);
    });

    test('reassembles split TLV chunks', () {
      final Uint8List first = codec.encode(
        DeviceFrame(
          messageType: DeviceMessageType.healthRequest,
          seq: 1,
          payload: const <int>[],
        ),
      );
      final Uint8List second = codec.encode(
        DeviceFrame(
          messageType: DeviceMessageType.disconnect,
          seq: 2,
          payload: const <int>[],
        ),
      );
      final DeviceFrameDecoder decoder = DeviceFrameDecoder();

      expect(decoder.addChunk(first.sublist(0, 5)), isEmpty);
      expect(decoder.addChunk(first.sublist(5)), hasLength(1));
      final List<DeviceFrame> frames = decoder.addChunk(second);

      expect(frames, hasLength(1));
      expect(frames.single.messageType, DeviceMessageType.disconnect);
    });

    test('rejects CRC mismatch', () {
      final Uint8List bytes = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.healthRequest, seq: 3),
      );
      bytes[bytes.length - 1] ^= 0xFF;

      expect(() => codec.decode(bytes), throwsFormatException);
    });

    test('rejects truncated frame', () {
      final Uint8List bytes = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.healthRequest, seq: 3),
      );

      expect(
        () => codec.decode(
          Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        ),
        throwsFormatException,
      );
    });

    test('rejects invalid frame version', () {
      final Uint8List bytes = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.healthRequest, seq: 4),
      );
      bytes[2] = DeviceProtocolConstants.version + 1;

      expect(() => codec.decode(bytes), throwsFormatException);
    });

    test('rejects invalid frame prefix', () {
      final Uint8List bytes = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.healthRequest, seq: 5),
      );
      bytes[0] = 0x00;

      expect(() => codec.decode(bytes), throwsFormatException);

      final DeviceFrameDecoder decoder = DeviceFrameDecoder(codec: codec);
      expect(() => decoder.addChunk(bytes), throwsFormatException);
    });

    test('returns no frames for incomplete chunks', () {
      final Uint8List frame = codec.encode(
        const DeviceFrame(messageType: DeviceMessageType.healthRequest, seq: 6),
      );
      final DeviceFrameDecoder decoder = DeviceFrameDecoder(codec: codec);

      expect(decoder.addChunk(frame.sublist(0, 6)), isEmpty);
      expect(decoder.addChunk(frame.sublist(6, frame.length - 1)), isEmpty);
    });
  });

  group('payload helpers', () {
    test('encodes profile payload with optional VO2 max', () {
      final Uint8List payload = const DeviceProfilePayload(
        heightCm: 170,
        weightKg: 70,
        age: 30,
        sex: 2,
        vo2Max: 45,
      ).encode();

      expect(payload, <int>[0xAA, 0x00, 0x46, 0x00, 30, 2, 45]);
    });

    test('encodes sensor_ppg_imu payload shape', () {
      final Uint8List payload = DeviceSensorPayload(
        hostTimestampUs: 123456789,
        ppgChannels: List<double>.generate(10, (int index) => index + 0.5),
        imuChannels: List<double>.generate(9, (int index) => index + 20.5),
        actionType: 'squat'.codeUnits,
      ).encode();

      final ByteData data = ByteData.sublistView(payload);
      expect(payload.length, 89);
      expect(data.getUint64(0, Endian.little), 123456789);
      expect(data.getFloat32(8, Endian.little), closeTo(0.5, 0.0001));
      expect(data.getFloat32(48, Endian.little), closeTo(20.5, 0.0001));
      expect(String.fromCharCodes(payload.sublist(84)), 'squat');
    });

    test('decodes calibration_progress payload', () {
      final Uint8List payload = Uint8List(5);
      ByteData.sublistView(payload)
        ..setUint32(0, 12000, Endian.little)
        ..setUint8(4, 72);

      final CalibrationProgressPayload decoded =
          CalibrationProgressPayload.decode(payload);

      expect(decoded.elapsedMs, 12000);
      expect(decoded.hrEstimate, 72);
    });

    test('decodes calibration_done payload', () {
      final Uint8List payload = Uint8List(9);
      ByteData.sublistView(payload)
        ..setUint8(0, 64)
        ..setUint8(1, 88)
        ..setUint16(2, 240, Endian.little)
        ..setUint32(4, 30000, Endian.little)
        ..setUint8(8, 0);

      final CalibrationDonePayload decoded = CalibrationDonePayload.decode(
        payload,
      );

      expect(decoded.avgHrBpm, 64);
      expect(decoded.qualityScore, 88);
      expect(decoded.sampleCount, 240);
      expect(decoded.durationMs, 30000);
      expect(decoded.status, 0);
    });

    test('decodes health and error payloads', () {
      final HealthResponsePayload health = HealthResponsePayload.decode(<int>[
        0x03,
      ]);
      expect(health.vo2Running, isTrue);
      expect(health.sensorRunning, isTrue);

      final Uint8List errorPayload = Uint8List.fromList(<int>[
        0x08,
        0x00,
        ...'not_streaming'.codeUnits,
      ]);
      final ErrorPayload error = ErrorPayload.decode(errorPayload);
      expect(error.code, 8);
      expect(error.message, 'not_streaming');
    });
  });

  group('DeviceProtocolJsonParser', () {
    test('parses valid calibration_progress JSON', () {
      final Uint8List payload = Uint8List(5);
      ByteData.sublistView(payload)
        ..setUint32(0, 12000, Endian.little)
        ..setUint8(4, 72);

      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.calibrationProgress,
        'flags': 0,
        'seq': 1,
        'payloadBase64': base64Encode(payload),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.calibrationProgress);
      expect(result.flags, 0);
      expect(result.seq, 1);
      expect(result.typedPayload, isA<CalibrationProgressPayload>());

      final CalibrationProgressPayload progress =
          result.typedPayload as CalibrationProgressPayload;
      expect(progress.elapsedMs, 12000);
      expect(progress.hrEstimate, 72);
    });

    test('parses valid calibration_done JSON', () {
      final Uint8List payload = Uint8List(9);
      ByteData.sublistView(payload)
        ..setUint8(0, 64)
        ..setUint8(1, 88)
        ..setUint16(2, 240, Endian.little)
        ..setUint32(4, 30000, Endian.little)
        ..setUint8(8, 0);

      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.calibrationDone,
        'flags': 0,
        'seq': 2,
        'payloadBase64': base64Encode(payload),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.calibrationDone);
      expect(result.seq, 2);
      expect(result.typedPayload, isA<CalibrationDonePayload>());

      final CalibrationDonePayload done =
          result.typedPayload as CalibrationDonePayload;
      expect(done.avgHrBpm, 64);
      expect(done.qualityScore, 88);
      expect(done.sampleCount, 240);
      expect(done.durationMs, 30000);
      expect(done.status, 0);
    });

    test('parses valid vo2_prediction JSON', () {
      final Uint8List payload = Uint8List(12);
      ByteData.sublistView(payload)
        ..setUint64(0, 9876543210123, Endian.little)
        ..setFloat32(8, 42.5, Endian.little);

      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.vo2Prediction,
        'flags': 0,
        'seq': 3,
        'payloadBase64': base64Encode(payload),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.vo2Prediction);
      expect(result.typedPayload, isA<Vo2PredictionPayload>());

      final Vo2PredictionPayload prediction =
          result.typedPayload as Vo2PredictionPayload;
      expect(prediction.timestampNs, 9876543210123);
      expect(prediction.vo2MlKgMin, closeTo(42.5, 0.001));
    });

    test('parses valid health_response JSON', () {
      final Uint8List payload = Uint8List.fromList(<int>[0x01]);

      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.healthResponse,
        'flags': 0,
        'seq': 4,
        'payloadBase64': base64Encode(payload),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.healthResponse);
      expect(result.typedPayload, isA<HealthResponsePayload>());

      final HealthResponsePayload health =
          result.typedPayload as HealthResponsePayload;
      expect(health.vo2Running, isTrue);
      expect(health.sensorRunning, isFalse);
    });

    test('parses valid error JSON', () {
      final Uint8List errorPayload = Uint8List.fromList(<int>[
        0x08,
        0x00,
        ...'not_streaming'.codeUnits,
      ]);

      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.error,
        'flags': 0,
        'seq': 5,
        'payloadBase64': base64Encode(errorPayload),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.error);
      expect(result.typedPayload, isA<ErrorPayload>());

      final ErrorPayload error = result.typedPayload as ErrorPayload;
      expect(error.code, 8);
      expect(error.message, 'not_streaming');
    });

    test('parses valid profile_ack JSON', () {
      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.profileAck, Uint8List(0), seq: 6),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.profileAck);
      expect(result.seq, 6);
      expect(result.typedPayload, isA<ProfileAckPayload>());
    });

    test('parses valid app_status JSON', () {
      final Uint8List payload = Uint8List(9);
      ByteData.sublistView(payload)
        ..setUint8(0, 1)
        ..setUint8(1, 2)
        ..setUint8(2, 3)
        ..setUint8(3, 1)
        ..setUint8(4, 4)
        ..setUint8(5, 55)
        ..setUint16(6, 0x1234, Endian.little)
        ..setUint8(8, 0);

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.appStatus, payload, seq: 7),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.appStatus);
      expect(result.typedPayload, isA<AppStatusPayload>());

      final AppStatusPayload status = result.typedPayload as AppStatusPayload;
      expect(status.transport, 1);
      expect(status.connectionState, 2);
      expect(status.bleTransferState, 3);
      expect(status.profileReceived, isTrue);
      expect(status.calibrationState, 4);
      expect(status.calibrationProgressPct, 55);
      expect(status.lastErrorCode, 0x1234);
      expect(status.startWorkoutAvailable, isFalse);
    });

    test('parses valid workout_summary JSON', () {
      final Uint8List payload = Uint8List(77);
      final ByteData data = ByteData.sublistView(payload)
        ..setUint64(0, 1000, Endian.little)
        ..setUint64(8, 9000, Endian.little)
        ..setUint64(16, 8000, Endian.little)
        ..setUint8(24, 8)
        ..setFloat32(57, 21.5, Endian.little)
        ..setFloat32(61, 44.5, Endian.little)
        ..setFloat32(65, 32.25, Endian.little)
        ..setUint16(69, 12, Endian.little)
        ..setUint8(71, 2)
        ..setUint8(72, 9)
        ..setUint8(73, 6)
        ..setUint16(74, 4, Endian.little)
        ..setUint8(76, 3);
      for (int index = 0; index < 8; index += 1) {
        data
          ..setUint16(25 + index * 2, index + 10, Endian.little)
          ..setUint16(41 + index * 2, index + 20, Endian.little);
      }

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.workoutSummary, payload, seq: 8),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.workoutSummary);
      expect(result.typedPayload, isA<WorkoutSummaryPayload>());

      final WorkoutSummaryPayload summary =
          result.typedPayload as WorkoutSummaryPayload;
      expect(summary.workoutStartTsMs, 1000);
      expect(summary.workoutEndTsMs, 9000);
      expect(summary.durationMs, 8000);
      expect(summary.totalMovementCount, 8);
      expect(summary.repsByMovement, <int>[10, 11, 12, 13, 14, 15, 16, 17]);
      expect(summary.setsByMovement, <int>[20, 21, 22, 23, 24, 25, 26, 27]);
      expect(summary.vo2Min, closeTo(21.5, 0.001));
      expect(summary.vo2Max, closeTo(44.5, 0.001));
      expect(summary.vo2Avg, closeTo(32.25, 0.001));
      expect(summary.vo2SampleCount, 12);
      expect(summary.rpeMin, 2);
      expect(summary.rpeMax, 9);
      expect(summary.rpeAvg, 6);
      expect(summary.rpeSampleCount, 4);
      expect(summary.loadStatus, 3);
    });

    test('parses valid recommendation_input JSON', () {
      final Uint8List payload = Uint8List(13);
      ByteData.sublistView(payload)
        ..setUint8(0, 2)
        ..setUint8(1, 1)
        ..setUint8(2, 0)
        ..setUint8(3, 3)
        ..setUint8(4, 4)
        ..setUint32(5, 120000, Endian.little)
        ..setUint32(9, 30000, Endian.little);

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.recommendationInput, payload, seq: 9),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.recommendationInput);
      expect(result.typedPayload, isA<RecommendationInputPayload>());

      final RecommendationInputPayload recommendation =
          result.typedPayload as RecommendationInputPayload;
      expect(recommendation.recommendationStatus, 2);
      expect(recommendation.hasLowRpeInterval, isTrue);
      expect(recommendation.hasHighRpeInterval, isFalse);
      expect(recommendation.loadStatus, 3);
      expect(recommendation.vo2Trend, 4);
      expect(recommendation.lowRpeTotalMs, 120000);
      expect(recommendation.highRpeTotalMs, 30000);
    });

    test('parses valid rpe JSON', () {
      final Uint8List payload = Uint8List(9);
      ByteData.sublistView(payload)
        ..setUint64(0, 123456789, Endian.little)
        ..setUint8(8, 7);

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.rpe, payload, seq: 10),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.rpe);
      expect(result.typedPayload, isA<RpePayload>());

      final RpePayload rpe = result.typedPayload as RpePayload;
      expect(rpe.hostTsMs, 123456789);
      expect(rpe.rpe, 7);
    });

    test('parses valid rpe alert JSON', () {
      final List<int> message = utf8.encode('slow down');
      final Uint8List payload = Uint8List(16 + message.length);
      ByteData.sublistView(payload)
        ..setUint64(0, 22334455, Endian.little)
        ..setUint8(8, 2)
        ..setUint8(9, 9)
        ..setUint32(10, 45000, Endian.little)
        ..setUint16(14, message.length, Endian.little);
      payload.setRange(16, payload.length, message);

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(DeviceMessageType.rpe, payload, seq: 11),
          );

      expect(result, isNotNull);
      expect(result!.messageType, DeviceMessageType.rpe);
      expect(result.typedPayload, isA<RpeAlertPayload>());

      final RpeAlertPayload alert = result.typedPayload as RpeAlertPayload;
      expect(alert.hostTsMs, 22334455);
      expect(alert.alertType, 2);
      expect(alert.rpe, 9);
      expect(alert.durationMs, 45000);
      expect(alert.message, 'slow down');
    });

    test('returns null for malformed new typed payloads', () {
      final Map<int, Uint8List> malformedPayloads = <int, Uint8List>{
        DeviceMessageType.profileAck: Uint8List.fromList(<int>[1]),
        DeviceMessageType.appStatus: Uint8List(8),
        DeviceMessageType.workoutSummary: Uint8List(76),
        DeviceMessageType.recommendationInput: Uint8List(12),
        DeviceMessageType.rpe: Uint8List(8),
      };

      for (final MapEntry<int, Uint8List> fixture
          in malformedPayloads.entries) {
        expect(
          DeviceProtocolJsonParser.tryParse(
            _jsonFrame(fixture.key, fixture.value),
          ),
          isNull,
        );
      }
    });

    test('returns null for rpe alert with trailing bytes', () {
      final Uint8List payload = Uint8List(17);
      ByteData.sublistView(payload).setUint16(14, 0, Endian.little);

      expect(
        DeviceProtocolJsonParser.tryParse(
          _jsonFrame(DeviceMessageType.rpe, payload),
        ),
        isNull,
      );
    });

    test('represents unknown messageType as raw/unknown', () {
      final String json = jsonEncode(<String, dynamic>{
        'messageType': 0x9999,
        'flags': 0,
        'seq': 0,
        'payloadBase64': base64Encode(Uint8List(0)),
      });

      final DeviceProtocolJsonResult? result =
          DeviceProtocolJsonParser.tryParse(json);

      expect(result, isNotNull);
      expect(result!.messageType, 0x9999);
      expect(result.flags, 0);
      expect(result.seq, 0);
      expect(result.typedPayload, isNull);
    });

    test('returns null for malformed JSON', () {
      expect(DeviceProtocolJsonParser.tryParse('{invalid'), isNull);
    });

    test('returns null for invalid base64', () {
      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.calibrationProgress,
        'flags': 0,
        'seq': 0,
        'payloadBase64': 'not-valid-base64!!!',
      });

      expect(DeviceProtocolJsonParser.tryParse(json), isNull);
    });

    test('returns null for missing required fields', () {
      final String json = jsonEncode(<String, dynamic>{
        'messageType': DeviceMessageType.calibrationProgress,
        'flags': 0,
      });

      expect(DeviceProtocolJsonParser.tryParse(json), isNull);
    });

    test('returns null for a normal CSV string', () {
      expect(DeviceProtocolJsonParser.tryParse('hello,world'), isNull);
    });
  });
}

String _jsonFrame(int messageType, List<int> payload, {int seq = 0}) {
  return jsonEncode(<String, dynamic>{
    'messageType': messageType,
    'flags': 0,
    'seq': seq,
    'payloadBase64': base64Encode(payload),
  });
}

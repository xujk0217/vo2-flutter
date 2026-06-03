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

import 'dart:convert';
import 'dart:typed_data';

class DeviceBleUuids {
  const DeviceBleUuids._();

  static const String service = '0000ffee-0000-1000-8000-00805f9b34fb';
  static const String writeCharacteristic =
      '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String notifyCharacteristic =
      '0000ffe2-0000-1000-8000-00805f9b34fb';
  static const String advertisedName = 'bt_fucktrae_young';
}

class DeviceMessageType {
  const DeviceMessageType._();

  static const int profile = 0x0001;
  static const int profileAck = 0x0002;
  static const int calibrationStart = 0x0010;
  static const int calibrationProgress = 0x0011;
  static const int calibrationDone = 0x0012;
  static const int calibrationError = 0x0013;
  static const int sensorPpgImu = 0x0020;
  static const int vo2Prediction = 0x0030;
  static const int debugQuality = 0x0040;
  static const int error = 0x00F0;
  static const int healthRequest = 0x00F1;
  static const int healthResponse = 0x00F2;
  static const int disconnect = 0x00FF;
  static const int rpe = 0x0100;
  static const int classifierResult = 0x0101;
  static const int fitnessCommand = 0x0102;
}

class DeviceProtocolConstants {
  const DeviceProtocolConstants._();

  static const int magic = 0x4254;
  static const int version = 1;
  static const int headerSize = 8;
  static const int payloadLengthSize = 2;
  static const int crcSize = 4;
  static const int maxFrameSize = 4096;
  static const int maxPayloadSize = 4082;
}

class DeviceFrame {
  const DeviceFrame({
    required this.messageType,
    required this.seq,
    this.flags = 0,
    this.payload = const <int>[],
  });

  final int messageType;
  final int flags;
  final int seq;
  final List<int> payload;
}

class DeviceProtocolCodec {
  const DeviceProtocolCodec();

  Uint8List encode(DeviceFrame frame) {
    final Uint8List payload = Uint8List.fromList(frame.payload);
    if (payload.length > DeviceProtocolConstants.maxPayloadSize) {
      throw RangeError.range(
        payload.length,
        0,
        DeviceProtocolConstants.maxPayloadSize,
        'payload.length',
      );
    }

    final int totalLength =
        DeviceProtocolConstants.headerSize +
        DeviceProtocolConstants.payloadLengthSize +
        payload.length +
        DeviceProtocolConstants.crcSize;
    final Uint8List output = Uint8List(totalLength);
    final ByteData data = ByteData.sublistView(output);
    data
      ..setUint16(0, DeviceProtocolConstants.magic, Endian.little)
      ..setUint8(2, DeviceProtocolConstants.version)
      ..setUint16(3, frame.messageType, Endian.little)
      ..setUint8(5, frame.flags)
      ..setUint16(6, frame.seq, Endian.little)
      ..setUint16(8, payload.length, Endian.little);
    output.setRange(10, 10 + payload.length, payload);

    final Uint8List crcInput = Uint8List(8 + payload.length)
      ..setRange(0, 8, output.sublist(0, 8))
      ..setRange(8, 8 + payload.length, payload);
    data.setUint32(10 + payload.length, crc32(crcInput), Endian.little);
    return output;
  }

  DeviceFrame decode(Uint8List bytes) {
    if (bytes.length < 10) {
      throw const FormatException('Frame is shorter than header and length');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int magic = data.getUint16(0, Endian.little);
    if (magic != DeviceProtocolConstants.magic) {
      throw const FormatException('Invalid frame magic');
    }
    final int version = data.getUint8(2);
    if (version != DeviceProtocolConstants.version) {
      throw const FormatException('Unsupported frame version');
    }
    final int payloadLength = data.getUint16(8, Endian.little);
    if (payloadLength > DeviceProtocolConstants.maxPayloadSize) {
      throw const FormatException('Frame payload is too large');
    }
    final int totalLength = 10 + payloadLength + 4;
    if (totalLength > DeviceProtocolConstants.maxFrameSize) {
      throw const FormatException('Frame is too large');
    }
    if (bytes.length < totalLength) {
      throw const FormatException('Frame is truncated');
    }
    if (bytes.length > totalLength) {
      throw const FormatException('Frame has trailing bytes');
    }

    final Uint8List payload = Uint8List.fromList(
      bytes.sublist(10, 10 + payloadLength),
    );
    final Uint8List crcInput = Uint8List(8 + payloadLength)
      ..setRange(0, 8, bytes.sublist(0, 8))
      ..setRange(8, 8 + payloadLength, payload);
    final int expectedCrc = data.getUint32(10 + payloadLength, Endian.little);
    final int actualCrc = crc32(crcInput);
    if (actualCrc != expectedCrc) {
      throw const FormatException('Frame CRC mismatch');
    }

    return DeviceFrame(
      messageType: data.getUint16(3, Endian.little),
      flags: data.getUint8(5),
      seq: data.getUint16(6, Endian.little),
      payload: payload,
    );
  }

  static int crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final int byte in bytes) {
      crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class DeviceFrameDecoder {
  DeviceFrameDecoder({DeviceProtocolCodec codec = const DeviceProtocolCodec()})
    : _codec = codec;

  final DeviceProtocolCodec _codec;
  final List<int> _buffer = <int>[];

  List<DeviceFrame> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final List<DeviceFrame> frames = <DeviceFrame>[];

    while (true) {
      if (_buffer.length < 8) {
        return frames;
      }
      if (_readUint16(_buffer, 0) != DeviceProtocolConstants.magic ||
          _buffer[2] != DeviceProtocolConstants.version) {
        _buffer.clear();
        throw const FormatException('Invalid frame prefix');
      }
      if (_buffer.length < 10) {
        return frames;
      }
      final int payloadLength = _readUint16(_buffer, 8);
      if (payloadLength > DeviceProtocolConstants.maxPayloadSize) {
        _buffer.clear();
        throw const FormatException('Frame payload is too large');
      }
      final int totalLength = 10 + payloadLength + 4;
      if (totalLength > DeviceProtocolConstants.maxFrameSize) {
        _buffer.clear();
        throw const FormatException('Frame is too large');
      }
      if (_buffer.length < totalLength) {
        return frames;
      }
      final Uint8List frameBytes = Uint8List.fromList(
        _buffer.sublist(0, totalLength),
      );
      frames.add(_codec.decode(frameBytes));
      _buffer.removeRange(0, totalLength);
    }
  }

  static int _readUint16(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }
}

class DeviceProfilePayload {
  const DeviceProfilePayload({
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.sex,
    this.vo2Max,
  });

  final int heightCm;
  final int weightKg;
  final int age;
  final int sex;
  final int? vo2Max;

  Uint8List encode() {
    _validateRange('heightCm', heightCm, 80, 250);
    _validateRange('weightKg', weightKg, 20, 250);
    _validateRange('age', age, 5, 120);
    _validateRange('sex', sex, 0, 2);
    final int? vo2 = vo2Max;
    if (vo2 != null) {
      _validateRange('vo2Max', vo2, 5, 100);
    }

    final Uint8List bytes = Uint8List(vo2 == null ? 6 : 7);
    final ByteData data = ByteData.sublistView(bytes);
    data
      ..setUint16(0, heightCm, Endian.little)
      ..setUint16(2, weightKg, Endian.little)
      ..setUint8(4, age)
      ..setUint8(5, sex);
    if (vo2 != null) {
      data.setUint8(6, vo2);
    }
    return bytes;
  }

  static void _validateRange(String name, int value, int min, int max) {
    if (value < min || value > max) {
      throw RangeError.range(value, min, max, name);
    }
  }
}

class DeviceSensorPayload {
  const DeviceSensorPayload({
    required this.hostTimestampUs,
    required this.ppgChannels,
    required this.imuChannels,
    this.actionType = const <int>[],
  });

  final int hostTimestampUs;
  final List<double> ppgChannels;
  final List<double> imuChannels;
  final List<int> actionType;

  Uint8List encode() {
    if (ppgChannels.length != 10) {
      throw ArgumentError.value(ppgChannels.length, 'ppgChannels.length');
    }
    if (imuChannels.length != 9) {
      throw ArgumentError.value(imuChannels.length, 'imuChannels.length');
    }
    final Uint8List bytes = Uint8List(84 + actionType.length);
    final ByteData data = ByteData.sublistView(bytes)
      ..setUint64(0, hostTimestampUs, Endian.little);
    int offset = 8;
    for (final double value in ppgChannels) {
      data.setFloat32(offset, value, Endian.little);
      offset += 4;
    }
    for (final double value in imuChannels) {
      data.setFloat32(offset, value, Endian.little);
      offset += 4;
    }
    bytes.setRange(84, bytes.length, actionType);
    return bytes;
  }
}

class CalibrationProgressPayload {
  const CalibrationProgressPayload({
    required this.elapsedMs,
    required this.hrEstimate,
  });

  final int elapsedMs;
  final int hrEstimate;

  static CalibrationProgressPayload decode(List<int> payload) {
    if (payload.length != 5) {
      throw const FormatException('Invalid calibration_progress payload');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(payload));
    return CalibrationProgressPayload(
      elapsedMs: data.getUint32(0, Endian.little),
      hrEstimate: data.getUint8(4),
    );
  }
}

class CalibrationDonePayload {
  const CalibrationDonePayload({
    required this.avgHrBpm,
    required this.qualityScore,
    required this.sampleCount,
    required this.durationMs,
    required this.status,
  });

  final int avgHrBpm;
  final int qualityScore;
  final int sampleCount;
  final int durationMs;
  final int status;

  static CalibrationDonePayload decode(List<int> payload) {
    if (payload.length != 9) {
      throw const FormatException('Invalid calibration_done payload');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(payload));
    return CalibrationDonePayload(
      avgHrBpm: data.getUint8(0),
      qualityScore: data.getUint8(1),
      sampleCount: data.getUint16(2, Endian.little),
      durationMs: data.getUint32(4, Endian.little),
      status: data.getUint8(8),
    );
  }
}

class Vo2PredictionPayload {
  const Vo2PredictionPayload({
    required this.timestampNs,
    required this.vo2MlKgMin,
  });

  final int timestampNs;
  final double vo2MlKgMin;

  static Vo2PredictionPayload decode(List<int> payload) {
    if (payload.length != 12) {
      throw const FormatException('Invalid vo2_prediction payload');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(payload));
    return Vo2PredictionPayload(
      timestampNs: data.getUint64(0, Endian.little),
      vo2MlKgMin: data.getFloat32(8, Endian.little),
    );
  }
}

class HealthResponsePayload {
  const HealthResponsePayload({
    required this.vo2Running,
    required this.sensorRunning,
  });

  final bool vo2Running;
  final bool sensorRunning;

  static HealthResponsePayload decode(List<int> payload) {
    if (payload.length != 1) {
      throw const FormatException('Invalid health_response payload');
    }
    final int bitfield = payload.first;
    return HealthResponsePayload(
      vo2Running: (bitfield & 0x01) != 0,
      sensorRunning: (bitfield & 0x02) != 0,
    );
  }
}

class ErrorPayload {
  const ErrorPayload({required this.code, required this.message});

  final int code;
  final String message;

  static ErrorPayload decode(List<int> payload) {
    if (payload.length < 2) {
      throw const FormatException('Invalid error payload');
    }
    final ByteData data = ByteData.sublistView(Uint8List.fromList(payload));
    return ErrorPayload(
      code: data.getUint16(0, Endian.little),
      message: utf8.decode(payload.sublist(2), allowMalformed: true),
    );
  }
}

class DeviceProtocolJsonResult {
  const DeviceProtocolJsonResult({
    required this.messageType,
    required this.flags,
    required this.seq,
    this.typedPayload,
  });

  final int messageType;
  final int flags;
  final int seq;
  final Object? typedPayload;
}

class DeviceProtocolJsonParser {
  /// Parses a BLE JSON frame string.
  ///
  /// Expects a top-level JSON object with integer `messageType`, integer
  /// `flags`, integer `seq`, and string `payloadBase64`. Returns `null` for
  /// malformed input, missing/wrong-typed fields, invalid base64, or known
  /// message types whose typed payload decoder throws.
  static DeviceProtocolJsonResult? tryParse(String payload) {
    dynamic parsed;
    try {
      parsed = jsonDecode(payload);
    } catch (_) {
      return null;
    }

    if (parsed is! Map<String, dynamic>) {
      return null;
    }

    final dynamic messageType = parsed['messageType'];
    final dynamic flags = parsed['flags'];
    final dynamic seq = parsed['seq'];
    final dynamic payloadBase64 = parsed['payloadBase64'];

    if (messageType is! int ||
        flags is! int ||
        seq is! int ||
        payloadBase64 is! String) {
      return null;
    }

    Uint8List decodedPayload;
    try {
      decodedPayload = Uint8List.fromList(base64Decode(payloadBase64));
    } catch (_) {
      return null;
    }

    Object? typedPayload;
    switch (messageType) {
      case DeviceMessageType.calibrationProgress:
        try {
          typedPayload = CalibrationProgressPayload.decode(decodedPayload);
        } catch (_) {
          return null;
        }
      case DeviceMessageType.calibrationDone:
        try {
          typedPayload = CalibrationDonePayload.decode(decodedPayload);
        } catch (_) {
          return null;
        }
      case DeviceMessageType.vo2Prediction:
        try {
          typedPayload = Vo2PredictionPayload.decode(decodedPayload);
        } catch (_) {
          return null;
        }
      case DeviceMessageType.healthResponse:
        try {
          typedPayload = HealthResponsePayload.decode(decodedPayload);
        } catch (_) {
          return null;
        }
      case DeviceMessageType.error:
        try {
          typedPayload = ErrorPayload.decode(decodedPayload);
        } catch (_) {
          return null;
        }
      default:
        typedPayload = null;
    }

    return DeviceProtocolJsonResult(
      messageType: messageType,
      flags: flags,
      seq: seq,
      typedPayload: typedPayload,
    );
  }
}

final List<int> _crc32Table = List<int>.generate(256, (int index) {
  int crc = index;
  for (int bit = 0; bit < 8; bit += 1) {
    crc = (crc & 1) == 1 ? 0xEDB88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return crc;
});

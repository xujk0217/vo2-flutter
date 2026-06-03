import 'package:flutter/foundation.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';
import 'package:vo2_flutter/user_profile.dart';

/// Tracks the calibration lifecycle on the device.
enum DeviceProtocolCalibrationState { idle, running, completed, error }

/// Session-level controller for the device protocol.
///
/// Owns the conversation state (sequence numbers, current profile, calibration
/// progress) and translates [ReceiverDataEvent]s into typed payloads and state
/// transitions.
class DeviceProtocolSession extends ChangeNotifier {
  DeviceProtocolSession({
    DeviceProtocolFrameWriter? writer,
    UserProfile initialProfile = UserProfile.defaults,
  }) : _writer = writer,
       _currentProfile = initialProfile;

  final DeviceProtocolFrameWriter? _writer;
  UserProfile _currentProfile;
  int _seq = 1;

  DeviceProtocolCalibrationState _calibrationState =
      DeviceProtocolCalibrationState.idle;
  int? _calibrationElapsedMs;
  int? _calibrationHrEstimate;
  double? _calibrationProgress;
  CalibrationDonePayload? _calibrationDone;
  ErrorPayload? _protocolError;
  Vo2PredictionPayload? _latestVo2Prediction;

  // ── Public accessors ──────────────────────────────────────────────────────

  bool get canWriteCommands => _writer != null;

  DeviceProtocolCalibrationState get calibrationState => _calibrationState;

  int? get calibrationElapsedMs => _calibrationElapsedMs;

  int? get calibrationHrEstimate => _calibrationHrEstimate;

  double? get calibrationProgress => _calibrationProgress;

  CalibrationDonePayload? get calibrationDone => _calibrationDone;

  ErrorPayload? get protocolError => _protocolError;

  Vo2PredictionPayload? get latestVo2Prediction => _latestVo2Prediction;

  // ── Profile management ────────────────────────────────────────────────────

  /// Replace the locally-stored profile (e.g. when the user edits settings).
  void updateProfile(UserProfile profile) {
    _currentProfile = profile;
  }

  /// Map a [UserSex] to the wire format used by [DeviceProfilePayload].
  static int _sexToInt(UserSex sex) {
    switch (sex) {
      case UserSex.male:
        return 0;
      case UserSex.female:
        return 1;
      case UserSex.other:
        return 2;
    }
  }

  // ── Sequence numbers ──────────────────────────────────────────────────────

  int _nextSeq() {
    final int seq = _seq;
    _seq = (_seq + 1) & 0xFFFF; // wrap safely inside uint16
    return seq;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Send the device a [UserProfile] encoded as a [DeviceMessageType.profile]
  /// frame. Returns `false` when no writer is available.
  Future<bool> sendProfile(UserProfile profile) async {
    final DeviceProtocolFrameWriter? writer = _writer;
    if (writer == null) return false;

    final DeviceProfilePayload payload = DeviceProfilePayload(
      heightCm: profile.heightCm.round().clamp(80, 250),
      weightKg: profile.weightKg.round().clamp(20, 250),
      age: profile.age.clamp(5, 120),
      sex: _sexToInt(profile.sex),
    );

    await writer.writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.profile,
        seq: _nextSeq(),
        payload: payload.encode(),
      ),
    );

    return true;
  }

  /// Start a VO₂ calibration session.
  ///
  /// If [profile] is provided it is sent to the device first, then a
  /// [DeviceMessageType.calibrationStart] frame is written.  All calibration
  /// progress/result fields are reset and [calibrationState] becomes
  /// [DeviceProtocolCalibrationState.running].
  Future<bool> startCalibration({UserProfile? profile}) async {
    final DeviceProtocolFrameWriter? writer = _writer;
    if (writer == null) return false;

    if (profile != null) {
      await sendProfile(profile);
    }

    await writer.writeFrame(
      DeviceFrame(
        messageType: DeviceMessageType.calibrationStart,
        seq: _nextSeq(),
        payload: <int>[],
      ),
    );

    _calibrationState = DeviceProtocolCalibrationState.running;
    _calibrationElapsedMs = null;
    _calibrationHrEstimate = null;
    _calibrationProgress = null;
    _calibrationDone = null;
    _protocolError = null;
    notifyListeners();

    return true;
  }

  /// Process an incoming data event from the device transport.
  ///
  /// Parses the JSON payload, then dispatches based on [DeviceMessageType].
  /// Non-protocol events (parse failures) as well as sensor/RPE/classifier
  /// messages are silently ignored.
  Future<void> handleDataEvent(ReceiverDataEvent event) async {
    final DeviceProtocolJsonResult? result = DeviceProtocolJsonParser.tryParse(
      event.payload,
    );
    if (result == null) return;

    switch (result.messageType) {
      case DeviceMessageType.profile:
        // The device is asking for our profile – respond if we can write.
        if (_writer != null) {
          await sendProfile(_currentProfile);
        }

      case DeviceMessageType.calibrationProgress:
        final CalibrationProgressPayload? p =
            result.typedPayload as CalibrationProgressPayload?;
        if (p == null) return;
        _calibrationState = DeviceProtocolCalibrationState.running;
        _calibrationElapsedMs = p.elapsedMs;
        _calibrationHrEstimate = p.hrEstimate;
        _calibrationProgress = (p.elapsedMs / 30000.0).clamp(0.0, 1.0);
        notifyListeners();

      case DeviceMessageType.calibrationDone:
        final CalibrationDonePayload? p =
            result.typedPayload as CalibrationDonePayload?;
        if (p == null) return;
        _calibrationState = DeviceProtocolCalibrationState.completed;
        _calibrationDone = p;
        _calibrationProgress = 1.0;
        notifyListeners();

      case DeviceMessageType.error:
        final ErrorPayload? p = result.typedPayload as ErrorPayload?;
        if (p == null) return;
        _calibrationState = DeviceProtocolCalibrationState.error;
        _protocolError = p;
        notifyListeners();

      case DeviceMessageType.vo2Prediction:
        final Vo2PredictionPayload? p =
            result.typedPayload as Vo2PredictionPayload?;
        if (p == null) return;
        _latestVo2Prediction = p;
        notifyListeners();

      // Ignored message types – no writes, no state changes.
      case DeviceMessageType.sensorPpgImu:
      case DeviceMessageType.rpe:
      case DeviceMessageType.classifierResult:
      case DeviceMessageType.fitnessCommand:
        break;

      default:
        break;
    }
  }
}

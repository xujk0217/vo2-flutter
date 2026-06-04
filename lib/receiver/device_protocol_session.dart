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
  ProfileAckPayload? _latestProfileAck;
  HealthResponsePayload? _latestHealthResponse;
  AppStatusPayload? _latestAppStatus;
  WorkoutSummaryPayload? _latestWorkoutSummary;
  RecommendationInputPayload? _latestRecommendationInput;
  RpeAlertPayload? _latestRpeAlert;
  int? _lastProtocolMessageType;
  int? _lastUnsupportedMessageType;

  // ── Public accessors ──────────────────────────────────────────────────────

  bool get canWriteCommands => _writer != null;

  DeviceProtocolCalibrationState get calibrationState => _calibrationState;

  int? get calibrationElapsedMs => _calibrationElapsedMs;

  int? get calibrationHrEstimate => _calibrationHrEstimate;

  double? get calibrationProgress => _calibrationProgress;

  CalibrationDonePayload? get calibrationDone => _calibrationDone;

  ErrorPayload? get protocolError => _protocolError;

  Vo2PredictionPayload? get latestVo2Prediction => _latestVo2Prediction;

  ProfileAckPayload? get latestProfileAck => _latestProfileAck;

  HealthResponsePayload? get latestHealthResponse => _latestHealthResponse;

  AppStatusPayload? get latestAppStatus => _latestAppStatus;

  WorkoutSummaryPayload? get latestWorkoutSummary => _latestWorkoutSummary;

  RecommendationInputPayload? get latestRecommendationInput =>
      _latestRecommendationInput;

  RpeAlertPayload? get latestRpeAlert => _latestRpeAlert;

  int? get lastProtocolMessageType => _lastProtocolMessageType;

  int? get lastUnsupportedMessageType => _lastUnsupportedMessageType;

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

  Future<bool> _sendEmptyCommand(int messageType) async {
    final DeviceProtocolFrameWriter? writer = _writer;
    if (writer == null) return false;

    await writer.writeFrame(
      DeviceFrame(messageType: messageType, seq: _nextSeq(), payload: <int>[]),
    );

    return true;
  }

  /// Request the device's current health state.
  Future<bool> sendHealthRequest() {
    return _sendEmptyCommand(DeviceMessageType.healthRequest);
  }

  /// Send a protocol-level disconnect frame without closing the transport.
  Future<bool> sendProtocolDisconnect() {
    return _sendEmptyCommand(DeviceMessageType.disconnect);
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
  /// Non-protocol events (parse failures) are ignored. Passive protocol events
  /// update session diagnostics without starting product flows.
  Future<void> handleDataEvent(ReceiverDataEvent event) async {
    final DeviceProtocolJsonResult? result = DeviceProtocolJsonParser.tryParse(
      event.payload,
    );
    if (result == null) return;

    switch (result.messageType) {
      case DeviceMessageType.profile:
        _lastProtocolMessageType = result.messageType;
        // The device is asking for our profile – respond if we can write.
        if (_writer != null) {
          await sendProfile(_currentProfile);
        }
        notifyListeners();

      case DeviceMessageType.profileAck:
        final ProfileAckPayload? p = result.typedPayload as ProfileAckPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestProfileAck = p;
        notifyListeners();

      case DeviceMessageType.calibrationProgress:
        final CalibrationProgressPayload? p =
            result.typedPayload as CalibrationProgressPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _calibrationState = DeviceProtocolCalibrationState.running;
        _calibrationElapsedMs = p.elapsedMs;
        _calibrationHrEstimate = p.hrEstimate;
        _calibrationProgress = (p.elapsedMs / 30000.0).clamp(0.0, 1.0);
        notifyListeners();

      case DeviceMessageType.calibrationDone:
        final CalibrationDonePayload? p =
            result.typedPayload as CalibrationDonePayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _calibrationState = DeviceProtocolCalibrationState.completed;
        _calibrationDone = p;
        _calibrationProgress = 1.0;
        notifyListeners();

      case DeviceMessageType.error:
        final ErrorPayload? p = result.typedPayload as ErrorPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _calibrationState = DeviceProtocolCalibrationState.error;
        _protocolError = p;
        notifyListeners();

      case DeviceMessageType.vo2Prediction:
        final Vo2PredictionPayload? p =
            result.typedPayload as Vo2PredictionPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestVo2Prediction = p;
        notifyListeners();

      case DeviceMessageType.healthResponse:
        final HealthResponsePayload? p =
            result.typedPayload as HealthResponsePayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestHealthResponse = p;
        notifyListeners();

      case DeviceMessageType.appStatus:
        final AppStatusPayload? p = result.typedPayload as AppStatusPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestAppStatus = p;
        notifyListeners();

      case DeviceMessageType.workoutSummary:
        final WorkoutSummaryPayload? p =
            result.typedPayload as WorkoutSummaryPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestWorkoutSummary = p;
        notifyListeners();

      case DeviceMessageType.recommendationInput:
        final RecommendationInputPayload? p =
            result.typedPayload as RecommendationInputPayload?;
        if (p == null) return;
        _lastProtocolMessageType = result.messageType;
        _latestRecommendationInput = p;
        notifyListeners();

      case DeviceMessageType.rpe:
        _lastProtocolMessageType = result.messageType;
        final Object? p = result.typedPayload;
        if (p is RpeAlertPayload) {
          _latestRpeAlert = p;
        } else if (p is RpePayload) {
          // Phone-to-device RPE samples are not product behavior in Flutter.
        } else {
          return;
        }
        notifyListeners();

      // Ignored message types – no writes, no state changes.
      case DeviceMessageType.sensorPpgImu:
        break;

      case DeviceMessageType.classifierResult:
      case DeviceMessageType.fitnessCommand:
        _lastProtocolMessageType = result.messageType;
        _lastUnsupportedMessageType = result.messageType;
        notifyListeners();
        break;

      default:
        _lastProtocolMessageType = result.messageType;
        _lastUnsupportedMessageType = result.messageType;
        notifyListeners();
        break;
    }
  }
}

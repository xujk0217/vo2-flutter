# device_comm Protocol Pivot

This note records how the current device specification differs from the earlier Flutter receiver plan, and what this app should target for the current version.

## Major Differences

- The transport payload is now binary `device_comm` TLV frames, not CSV text lines.
- BLE is defined by fixed UUIDs:
  - Service: `0000ffee-0000-1000-8000-00805f9b34fb`
  - Phone-to-device write characteristic: `0000ffe1-0000-1000-8000-00805f9b34fb`
  - Device-to-phone notify characteristic: `0000ffe2-0000-1000-8000-00805f9b34fb`
  - Advertised local name: `bt_fucktrae_young`
- BLE chunks do not have an app-level chunk header. The phone app must reassemble by appending chunks until a full TLV frame can be decoded.
- Classic RFCOMM/SPP also carries the same TLV frames as a byte stream.
- Calibration is not a mobile-side CSV sample collection step. The phone sends `calibration_start` with an empty payload and receives `calibration_progress` / `calibration_done` from the device.
- `sensor_ppg_imu` is `Phone -> Device`, not `Device -> Phone`, and is accepted only after the device enters `streaming`.
- During calibration, the app must not stream PPG/IMU sensor frames. The current device may report `sample_count = 0` and `status = insufficient_signal` because the orchestrator does not feed HR samples into calibration yet.
- Profile exchange is explicit: device sends empty `profile` to request profile, phone replies with a 6 or 7 byte profile payload, then device sends `profile_ack`.

## Current Flutter Scope

- `lib/receiver/device_protocol.dart` provides a pure Dart TLV frame codec and payload helpers.
- `BleReceiverTransport` surfaces decoded TLV frames as JSON strings through `ReceiverDataEvent.payload`. These strings are parsed by `DeviceProtocolJsonParser` (or equivalent pure Dart helpers) for event handling.
- `DashboardPage` identifies and ignores these BLE protocol JSON strings. This prevents the generic CSV parser from attempting to process TLV frames, while the legacy Classic Bluetooth CSV path remains the default app transport.
- `DeviceProtocolSession` owns app-level protocol state for profile response, `calibration_start`, `calibration_progress`, `calibration_done`, and protocol error events. It observes receiver data through `ReceiverConnectionController.addDataListener` so Dashboard CSV handling can coexist with protocol event handling.
- `CalibrationScreen` can use a writable `DeviceProtocolSession` for device-backed calibration progress/done display. When no protocol writer is available, including the current Classic default app path, it keeps the local 30 second countdown fallback.
- This slice does not switch the default transport to BLE, does not auto-select BLE devices, and does not route `vo2_prediction` into Dashboard UI yet.
- A Dart-side BLE transport seam exists for scan/connect/write/notify events and TLV chunk reassembly; native Android BLE scanning, GATT write/notify handling, MTU chunking, and Classic TLV byte-stream platform code still require hardware verification before BLE becomes the default path.

## Current-Version Flow Target

```text
Phone                         Device
  | -- connect BLE/RFCOMM -----> |
  | <-- profile(empty) --------- |
  | -- profile(payload) -------> |
  | <-- profile_ack(empty) ----- |
  | -- calibration_start ------> |
  | <-- calibration_progress --- |
  | <-- calibration_done ------- |
  | -- sensor_ppg_imu --------> |
  | <-- vo2_prediction -------- |
  | -- health_request --------> |
  | <-- health_response ------- |
  | -- disconnect ------------> |
```

## Implementation Notes

- TLV multi-byte integers are little-endian.
- CRC32 is standard IEEE CRC32 over `header[0..8] + payload`; the `payload_len` bytes are excluded.
- Max frame size is `4096` bytes; max payload size is `4082` bytes.
- Bad magic, version, size, or CRC should clear/reconnect/resync according to app policy.

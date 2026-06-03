# Receiver Architecture Notes

This project currently runs on Android through the existing classic Bluetooth RFCOMM bridge in `MainActivity.kt` and `lib/bluetooth_bridge.dart`.

To make the receiver side easier to evolve, the Dart layer now has two separate seams:

## Transport seam

- `lib/receiver/receiver_transport.dart`
  - `ReceiverTransport`
  - `ReceiverTransportEvent`
  - `ReceiverDeviceInfo`
- `lib/receiver/classic_bluetooth_transport.dart`
  - production Android wrapper around the current `BluetoothBridge`
- `lib/receiver/ble_receiver_transport.dart`
  - placeholder for the future BLE implementation

`DashboardPage` now depends on `ReceiverTransport`, not directly on raw platform-channel maps.

That means a future BLE path should add or complete `BleReceiverTransport` instead of rewriting dashboard logic.

## Payload parsing seam

- `lib/receiver/raw_sensor_payload_parser.dart`
  - generic parser contract
- `lib/sensor_processing.dart`
  - `CsvSensorSampleParser`

`DashboardPage` now depends on a parser object, not on hardcoded CSV parsing in-place.

That means a future transport or protocol change can add a new parser, for example:

- JSON payload parser
- binary BLE notification parser
- protocol-versioned parser

without changing the dashboard's core receiver flow.

## Current production path

Current Android path is still:

1. `ClassicBluetoothTransport`
2. `BluetoothBridge`
3. Android `MainActivity.kt`
4. line-based payload stream
5. `CsvSensorSampleParser`
6. `MotionEstimator`

## Future BLE integration guidance

When the reference BLE implementation arrives, prefer this order:

1. implement or replace `BleReceiverTransport`
2. keep the dashboard on `ReceiverTransport`
3. add a new parser if payload format changes
4. only touch screen/business logic if the new protocol adds genuinely new concepts

This keeps transport migration and payload migration isolated from workout UI logic.

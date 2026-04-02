import Cocoa
import FlutterMacOS
import IOBluetooth

class MainFlutterWindow: NSWindow {
  private let bluetoothBridge = MacBluetoothBridge()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    bluetoothBridge.configure(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

private final class MacBluetoothBridge: NSObject, FlutterStreamHandler, IOBluetoothRFCOMMChannelDelegate {
  private static let methodChannelName = "vo2_flutter/bluetooth_methods"
  private static let eventChannelName = "vo2_flutter/bluetooth_stream"
  private static let rfcommChannelID: BluetoothRFCOMMChannelID = 1

  private var eventSink: FlutterEventSink?
  private var pendingConnectResult: FlutterResult?
  private var currentDevice: IOBluetoothDevice?
  private var currentChannel: IOBluetoothRFCOMMChannel?
  private var lineBuffer = ""

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler(handleMethodCall)

    let eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: binaryMessenger
    )
    eventChannel.setStreamHandler(self)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissions":
      result(true)
    case "isBluetoothEnabled":
      let controller = IOBluetoothHostController.default()
      result(controller?.powerState == kBluetoothHCIPowerStateON)
    case "getBondedDevices":
      let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).map {
        [
          "name": $0.nameOrAddress,
          "address": $0.addressString,
        ]
      }
      result(devices)
    case "connect":
      guard
        let arguments = call.arguments as? [String: Any],
        let address = arguments["address"] as? String,
        !address.isEmpty
      else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "Bluetooth address is required.",
            details: nil
          )
        )
        return
      }
      connect(to: address, result: result)
    case "disconnect":
      disconnectInternal(notifyFlutter: true)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connect(to address: String, result: @escaping FlutterResult) {
    guard pendingConnectResult == nil else {
      result(
        FlutterError(
          code: "connect_busy",
          message: "Another Bluetooth connection attempt is already in progress.",
          details: nil
        )
      )
      return
    }

    guard let device = IOBluetoothDevice(addressString: address) else {
      result(
        FlutterError(
          code: "device_not_found",
          message: "Bluetooth device \(address) could not be resolved.",
          details: nil
        )
      )
      return
    }

    let controller = IOBluetoothHostController.default()
    guard controller?.powerState == kBluetoothHCIPowerStateON else {
      result(
        FlutterError(
          code: "bluetooth_disabled",
          message: "Bluetooth is turned off on this Mac.",
          details: nil
        )
      )
      return
    }

    disconnectInternal(notifyFlutter: false)

    pendingConnectResult = result
    currentDevice = device
    lineBuffer = ""
    let deviceLabel = device.nameOrAddress ?? device.addressString ?? "Unknown device"
    emitStatus(
      state: "connecting",
      message: "Connecting to \(deviceLabel)..."
    )

    if !device.isConnected() {
      let connectionStatus = device.openConnection()
      guard connectionStatus == kIOReturnSuccess else {
        let message = "Failed to open baseband connection. status=\(connectionStatus)"
        pendingConnectResult = nil
        currentDevice = nil
        emitError(code: "connect_error", message: message)
        result(
          FlutterError(
            code: "connect_error",
            message: message,
            details: nil
          )
        )
        return
      }
    }

    var channel: IOBluetoothRFCOMMChannel?
    let status = device.openRFCOMMChannelAsync(
      &channel,
      withChannelID: Self.rfcommChannelID,
      delegate: self
    )

    guard status == kIOReturnSuccess else {
      let message = "Failed to open RFCOMM channel. status=\(status)"
      pendingConnectResult = nil
      currentDevice = nil
      disconnectInternal(notifyFlutter: false)
      emitError(code: "connect_error", message: message)
      result(
        FlutterError(
          code: "connect_error",
          message: message,
          details: nil
        )
      )
      return
    }

    currentChannel = channel
  }

  private func disconnectInternal(notifyFlutter: Bool) {
    if let channel = currentChannel, channel.isOpen() {
      _ = channel.close()
    }

    currentChannel = nil

    if let device = currentDevice, device.isConnected() {
      device.closeConnection()
    }

    currentDevice = nil
    lineBuffer = ""

    if notifyFlutter {
      emitStatus(state: "disconnected", message: "Bluetooth disconnected.")
    }
  }

  private func emitStatus(state: String, message: String) {
    emitEvent([
      "type": "status",
      "state": state,
      "message": message,
    ])
  }

  private func emitError(code: String, message: String) {
    emitEvent([
      "type": "error",
      "code": code,
      "message": message,
    ])
  }

  private func emitLine(_ line: String) {
    emitEvent([
      "type": "data",
      "line": line,
    ])
  }

  private func emitEvent(_ payload: [String: Any]) {
    eventSink?(payload)
  }

  private func flushBufferedLines() {
    while let delimiterIndex = lineBuffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
      let rawLine = String(lineBuffer[..<delimiterIndex])
      var removalEnd = lineBuffer.index(after: delimiterIndex)
      while removalEnd < lineBuffer.endIndex &&
          (lineBuffer[removalEnd] == "\n" || lineBuffer[removalEnd] == "\r") {
        removalEnd = lineBuffer.index(after: removalEnd)
      }
      lineBuffer.removeSubrange(lineBuffer.startIndex..<removalEnd)
      let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        emitLine(trimmed)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
    guard let result = pendingConnectResult else {
      return
    }

    pendingConnectResult = nil

    if error == kIOReturnSuccess {
      currentChannel = rfcommChannel
      emitStatus(
        state: "connected",
        message: "Connected to \(currentDevice?.nameOrAddress ?? "device")."
      )
      result(true)
      return
    }

    let message = "RFCOMM connection failed. status=\(error)"
    disconnectInternal(notifyFlutter: false)
    emitError(code: "connect_error", message: message)
    result(
      FlutterError(
        code: "connect_error",
        message: message,
        details: nil
      )
    )
  }

  func rfcommChannelData(
    _ rfcommChannel: IOBluetoothRFCOMMChannel!,
    data dataPointer: UnsafeMutableRawPointer!,
    length dataLength: Int
  ) {
    guard dataLength > 0, let dataPointer else {
      return
    }

    let data = Data(bytes: dataPointer, count: dataLength)
    guard let chunk = String(data: data, encoding: .utf8) else {
      return
    }

    lineBuffer.append(chunk)
    flushBufferedLines()
  }

  func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
    disconnectInternal(notifyFlutter: false)
    emitStatus(state: "disconnected", message: "Bluetooth stream closed.")
  }
}

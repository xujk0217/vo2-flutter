import Cocoa
import CoreBluetooth
import FlutterMacOS
import IOBluetooth

class MainFlutterWindow: NSWindow {
  private let bluetoothBridge = MacBluetoothBridge()
  private let bleBridge = MacBleBridge()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    bluetoothBridge.configure(binaryMessenger: flutterViewController.engine.binaryMessenger)
    bleBridge.configure(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

private final class MacBleBridge: NSObject, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate {
  private static let methodChannelName = "vo2_flutter/ble_methods"
  private static let eventChannelName = "vo2_flutter/ble_stream"
  private static let defaultServiceUuid = CBUUID(string: "0000ffee-0000-1000-8000-00805f9b34fb")
  private static let defaultWriteUuid = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
  private static let defaultNotifyUuid = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")

  private var eventSink: FlutterEventSink?
  private lazy var central = CBCentralManager(delegate: self, queue: .main)
  private var discoveredPeripherals: [String: CBPeripheral] = [:]
  private var discoveredDevices: [[String: String]] = []
  private var pendingScanResult: FlutterResult?
  private var pendingConnectResult: FlutterResult?
  private var pendingWriteResult: FlutterResult?
  private var stateWaiters: [() -> Void] = []
  private var stateTimer: Timer?
  private var scanTimer: Timer?
  private var targetServiceUuid = MacBleBridge.defaultServiceUuid
  private var targetWriteUuid = MacBleBridge.defaultWriteUuid
  private var targetNotifyUuid = MacBleBridge.defaultNotifyUuid
  private var acceptedNames: Set<String> = []
  private var includeUnmatched = false
  private var connectedPeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var notifyCharacteristic: CBCharacteristic?

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
      _ = central
      afterStateReady { [weak self] in
        result(self?.isPermissionUsable ?? false)
      }
    case "isBluetoothEnabled":
      _ = central
      afterStateReady { [weak self] in
        result(self?.central.state == .poweredOn)
      }
    case "scanDevices":
      scanDevices(call: call, result: result)
    case "connect":
      connect(call: call, result: result)
    case "disconnect":
      disconnectInternal(notifyFlutter: true)
      result(true)
    case "write":
      write(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isPermissionUsable: Bool {
    switch central.state {
    case .unauthorized, .unsupported:
      return false
    default:
      return true
    }
  }

  private func afterStateReady(_ action: @escaping () -> Void) {
    _ = central
    guard central.state == .unknown || central.state == .resetting else {
      action()
      return
    }

    stateWaiters.append(action)
    stateTimer?.invalidate()
    stateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
      self?.drainStateWaiters()
    }
  }

  private func drainStateWaiters() {
    stateTimer?.invalidate()
    stateTimer = nil
    let waiters = stateWaiters
    stateWaiters.removeAll()
    for waiter in waiters {
      waiter()
    }
  }

  private func scanDevices(call: FlutterMethodCall, result: @escaping FlutterResult) {
    afterStateReady { [weak self] in
      self?.scanDevicesAfterStateReady(call: call, result: result)
    }
  }

  private func scanDevicesAfterStateReady(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingScanResult == nil else {
      result(FlutterError(code: "scan_busy", message: "BLE scan is already running.", details: nil))
      return
    }
    guard central.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_disabled", message: bluetoothStateMessage, details: nil))
      return
    }

    let arguments = call.arguments as? [String: Any] ?? [:]
    targetServiceUuid = uuid(from: arguments["serviceUuid"]) ?? Self.defaultServiceUuid
    acceptedNames = names(from: arguments)
    includeUnmatched = arguments["includeUnmatched"] as? Bool ?? false
    discoveredPeripherals.removeAll()
    discoveredDevices.removeAll()
    pendingScanResult = result

    emitStatus(state: "scanning", message: "Scanning BLE devices...")
    central.stopScan()
    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    scanTimer?.invalidate()
    scanTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
      self?.completeScan()
    }
  }

  private func connect(call: FlutterMethodCall, result: @escaping FlutterResult) {
    afterStateReady { [weak self] in
      self?.connectAfterStateReady(call: call, result: result)
    }
  }

  private func connectAfterStateReady(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingConnectResult == nil else {
      result(FlutterError(code: "connect_busy", message: "BLE connection is already in progress.", details: nil))
      return
    }
    guard central.state == .poweredOn else {
      result(FlutterError(code: "bluetooth_disabled", message: bluetoothStateMessage, details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let deviceId = arguments["deviceId"] as? String,
      !deviceId.isEmpty
    else {
      result(FlutterError(code: "invalid_argument", message: "BLE deviceId is required.", details: nil))
      return
    }

    targetServiceUuid = uuid(from: arguments["serviceUuid"]) ?? Self.defaultServiceUuid
    targetWriteUuid = uuid(from: arguments["writeCharacteristicUuid"]) ?? Self.defaultWriteUuid
    targetNotifyUuid = uuid(from: arguments["notifyCharacteristicUuid"]) ?? Self.defaultNotifyUuid

    guard let peripheral = resolvePeripheral(deviceId: deviceId) else {
      result(FlutterError(code: "device_not_found", message: "BLE device \(deviceId) was not found. Scan before connecting.", details: nil))
      return
    }

    disconnectInternal(notifyFlutter: false)
    pendingConnectResult = result
    connectedPeripheral = peripheral
    peripheral.delegate = self
    emitStatus(state: "connecting", message: "Connecting to \(peripheral.name ?? deviceId)...")
    central.connect(peripheral, options: nil)
  }

  private func write(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingWriteResult == nil else {
      result(FlutterError(code: "write_busy", message: "A BLE write is already in progress.", details: nil))
      return
    }
    guard let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else {
      result(FlutterError(code: "not_connected", message: "BLE is not connected.", details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let bytes = data(from: arguments["bytes"])
    else {
      result(FlutterError(code: "invalid_argument", message: "BLE bytes are required.", details: nil))
      return
    }

    pendingWriteResult = result
    peripheral.writeValue(bytes, for: characteristic, type: .withResponse)
  }

  private func completeScan() {
    central.stopScan()
    scanTimer?.invalidate()
    scanTimer = nil
    let devices = discoveredDevices
    pendingScanResult?(devices)
    pendingScanResult = nil
    emitStatus(state: "scan_complete", message: "Found \(devices.count) BLE device(s).")
  }

  private func disconnectInternal(notifyFlutter: Bool) {
    stateTimer?.invalidate()
    stateTimer = nil
    stateWaiters.removeAll()
    scanTimer?.invalidate()
    scanTimer = nil
    central.stopScan()
    pendingScanResult?(discoveredDevices)
    pendingScanResult = nil
    pendingConnectResult = nil
    pendingWriteResult = nil
    writeCharacteristic = nil
    notifyCharacteristic = nil
    if let peripheral = connectedPeripheral {
      peripheral.delegate = nil
      central.cancelPeripheralConnection(peripheral)
    }
    connectedPeripheral = nil
    if notifyFlutter {
      emitStatus(state: "disconnected", message: "BLE disconnected.")
    }
  }

  private func resolvePeripheral(deviceId: String) -> CBPeripheral? {
    if let peripheral = discoveredPeripherals[deviceId] {
      return peripheral
    }
    guard let uuid = UUID(uuidString: deviceId) else {
      return nil
    }
    return central.retrievePeripherals(withIdentifiers: [uuid]).first
  }

  private func uuid(from value: Any?) -> CBUUID? {
    guard let raw = value as? String, !raw.isEmpty else {
      return nil
    }
    return CBUUID(string: raw)
  }

  private func names(from arguments: [String: Any]) -> Set<String> {
    var names = Set<String>()
    if let advertisedName = arguments["advertisedName"] as? String, !advertisedName.isEmpty {
      names.insert(advertisedName)
    }
    if let advertisedNames = arguments["advertisedNames"] as? [String] {
      names.formUnion(advertisedNames.filter { !$0.isEmpty })
    }
    return names
  }

  private func data(from value: Any?) -> Data? {
    if let typedData = value as? FlutterStandardTypedData {
      return typedData.data
    }
    if let bytes = value as? [UInt8] {
      return Data(bytes)
    }
    if let bytes = value as? [Int] {
      guard bytes.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
        return nil
      }
      return Data(bytes.map(UInt8.init))
    }
    return nil
  }

  private var bluetoothStateMessage: String {
    switch central.state {
    case .unknown, .resetting:
      return "Bluetooth is initializing."
    case .unsupported:
      return "Bluetooth is not supported on this Mac."
    case .unauthorized:
      return "Bluetooth permission was denied."
    case .poweredOff:
      return "Bluetooth is turned off on this Mac."
    case .poweredOn:
      return "Bluetooth is ready."
    @unknown default:
      return "Bluetooth is unavailable."
    }
  }

  private func emitStatus(state: String, message: String) {
    emitEvent(["type": "status", "state": state, "message": message])
  }

  private func emitError(code: String, message: String) {
    emitEvent(["type": "error", "code": code, "message": message])
  }

  private func emitEvent(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
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

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    emitStatus(
      state: central.state == .poweredOn ? "powered_on" : "bluetooth_unavailable",
      message: bluetoothStateMessage
    )
    if central.state != .unknown && central.state != .resetting {
      drainStateWaiters()
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let serviceMatches = serviceUuids.contains(targetServiceUuid)
    let displayName = advertisedName?.isEmpty == false
      ? advertisedName!
      : (peripheral.name?.isEmpty == false ? peripheral.name! : "")
    let nameMatches = acceptedNames.contains(displayName)
    guard includeUnmatched || serviceMatches || nameMatches else {
      return
    }

    let id = peripheral.identifier.uuidString
    if discoveredPeripherals[id] == nil {
      discoveredPeripherals[id] = peripheral
      discoveredDevices.append(["name": displayName, "id": id])
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    emitStatus(state: "discovering_services", message: "BLE connected. Discovering services...")
    peripheral.discoverServices([targetServiceUuid])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    let message = error?.localizedDescription ?? "BLE connection failed."
    pendingConnectResult?(FlutterError(code: "connect_error", message: message, details: nil))
    pendingConnectResult = nil
    emitError(code: "connect_error", message: message)
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if let result = pendingConnectResult {
      result(FlutterError(code: "disconnected", message: "BLE disconnected before setup completed.", details: nil))
      pendingConnectResult = nil
    }
    pendingWriteResult?(FlutterError(code: "disconnected", message: "BLE disconnected before write completed.", details: nil))
    pendingWriteResult = nil
    writeCharacteristic = nil
    notifyCharacteristic = nil
    connectedPeripheral = nil
    emitStatus(state: "disconnected", message: error?.localizedDescription ?? "BLE disconnected.")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      failConnect(code: "service_discovery_error", message: error.localizedDescription)
      return
    }
    guard let service = peripheral.services?.first(where: { $0.uuid == targetServiceUuid }) else {
      failConnect(code: "service_not_found", message: "BLE service \(targetServiceUuid.uuidString) was not found.")
      return
    }
    peripheral.discoverCharacteristics([targetWriteUuid, targetNotifyUuid], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error {
      failConnect(code: "characteristic_discovery_error", message: error.localizedDescription)
      return
    }
    writeCharacteristic = service.characteristics?.first(where: { $0.uuid == targetWriteUuid })
    notifyCharacteristic = service.characteristics?.first(where: { $0.uuid == targetNotifyUuid })
    guard let notifyCharacteristic, writeCharacteristic != nil else {
      failConnect(code: "characteristic_not_found", message: "BLE write or notify characteristic was not found.")
      return
    }
    peripheral.setNotifyValue(true, for: notifyCharacteristic)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == targetNotifyUuid else {
      return
    }
    if let error {
      failConnect(code: "notify_setup_error", message: error.localizedDescription)
      return
    }
    emitStatus(state: "connected", message: "BLE connected and notifications enabled.")
    pendingConnectResult?(true)
    pendingConnectResult = nil
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == targetWriteUuid else {
      return
    }
    if let error {
      pendingWriteResult?(FlutterError(code: "write_error", message: error.localizedDescription, details: nil))
      emitError(code: "write_error", message: error.localizedDescription)
    } else {
      emitStatus(state: "write_complete", message: "BLE write complete.")
      pendingWriteResult?(true)
    }
    pendingWriteResult = nil
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == targetNotifyUuid else {
      return
    }
    if let error {
      emitError(code: "notify_error", message: error.localizedDescription)
      return
    }
    guard let data = characteristic.value else {
      return
    }
    emitEvent(["type": "data", "chunk": FlutterStandardTypedData(bytes: data)])
  }

  private func failConnect(code: String, message: String) {
    pendingConnectResult?(FlutterError(code: code, message: message, details: nil))
    pendingConnectResult = nil
    emitError(code: code, message: message)
    if let peripheral = connectedPeripheral {
      central.cancelPeripheralConnection(peripheral)
    }
    connectedPeripheral = nil
    writeCharacteristic = nil
    notifyCharacteristic = nil
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

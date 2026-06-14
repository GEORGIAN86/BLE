import Cocoa
import CoreBluetooth
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// MARK: - Native model

/// Native-side snapshot of a discovered characteristic. The raw
/// `CBCharacteristicProperties` is retained so the clone can mirror it exactly.
struct CharacteristicInfo {
  let uuid: String
  let rawProperties: CBCharacteristicProperties
}

struct ServiceInfo {
  let uuid: String
  let isPrimary: Bool
  var characteristics: [CharacteristicInfo]
}

// MARK: - BLE Bridge (Method + Event channels)

/// Owns all CoreBluetooth objects and bridges them to Flutter.
///
/// * Commands arrive on a `FlutterMethodChannel` ("ble/methods").
/// * State is pushed to Flutter on a single multiplexed `FlutterEventChannel`
///   ("ble/events"); each event is a `[String: Any]` with a `type` field.
///
/// CoreBluetooth objects never cross the channel — only serialized primitives.
final class BleBridge: NSObject {
  static let methodChannelName = "ble/methods"
  static let eventChannelName = "ble/events"

  private var central: CBCentralManager!
  private var peripheralManager: CBPeripheralManager!
  private var eventSink: FlutterEventSink?

  // Central state
  private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
  private var orderedPeripherals: [Peripheral] = []
  private var connectedPeripheralUUID: UUID?
  private var discoveredServices: [ServiceInfo] = []

  // Peripheral (clone) state
  private var pendingName = "Cloned Device"
  private var servicesToAdd: [CBMutableService] = []
  private var addedCount = 0
  private var valueStore: [CBUUID: Data] = [:]
  private var wantsToAdvertise = false
  private var isAdvertising = false

  private let reservedServiceUUIDs: Set<String> = [
    "1800", "1801", "1805", "180A", "180D", "180F", "1810", "1811",
    "1814", "1816", "1818", "181A", "181B", "181C", "181D", "181E",
    "181F", "1820", "1821", "1823", "1829",
  ]

  struct Peripheral {
    let id: UUID
    let name: String
    let rssi: Int
  }

  init(messenger: FlutterBinaryMessenger) {
    super.init()

    let methodChannel = FlutterMethodChannel(
      name: BleBridge.methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(
      name: BleBridge.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)

    central = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    peripheralManager = CBPeripheralManager(delegate: self, queue: DispatchQueue.main)
  }

  // MARK: - Method handling

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startScan":
      startScanning()
      result(nil)
    case "stopScan":
      stopScanning()
      result(nil)
    case "connect":
      guard let args = call.arguments as? [String: Any],
        let id = args["id"] as? String
      else {
        result(FlutterError(code: "BAD_ARGS", message: "connect requires id", details: nil))
        return
      }
      connect(idString: id)
      result(nil)
    case "startClone":
      let args = call.arguments as? [String: Any]
      let name = (args?["name"] as? String) ?? ""
      startCloning(name: name)
      result(nil)
    case "stopClone":
      stopCloning()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Event emission

  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(payload) }
  }

  private func emitState() {
    emit(["type": "state", "isOn": central.state == .poweredOn])
  }

  private func emitDevices() {
    let devices = orderedPeripherals.map {
      ["id": $0.id.uuidString, "name": $0.name, "rssi": $0.rssi] as [String: Any]
    }
    emit(["type": "devices", "devices": devices])
  }

  private func emitConnection() {
    emit(["type": "connection", "connectedId": connectedPeripheralUUID?.uuidString as Any])
  }

  private func emitServices() {
    let services = discoveredServices.map { svc in
      [
        "uuid": svc.uuid,
        "isPrimary": svc.isPrimary,
        "characteristics": svc.characteristics.map { ch in
          ["uuid": ch.uuid, "rawProperties": Int(ch.rawProperties.rawValue)] as [String: Any]
        },
      ] as [String: Any]
    }
    emit(["type": "services", "services": services])
  }

  private func emitAdvertising(_ status: String) {
    emit(["type": "advertising", "isAdvertising": isAdvertising, "status": status])
  }

  // MARK: - Central role

  private func startScanning() {
    guard central.state == .poweredOn else { return }
    discoveredPeripherals.removeAll()
    orderedPeripherals.removeAll()
    emitDevices()
    central.scanForPeripherals(withServices: nil, options: nil)
  }

  private func stopScanning() {
    guard central.state == .poweredOn else { return }
    central.stopScan()
  }

  /// Stop scanning but keep results (used right before cloning).
  private func stopScanningKeepingResults() {
    guard central.state == .poweredOn else { return }
    central.stopScan()
  }

  private func connect(idString: String) {
    guard let uuid = UUID(uuidString: idString),
      let cbPeripheral = discoveredPeripherals[uuid]
    else { return }

    if let current = connectedPeripheralUUID, current != uuid,
      let currentPeripheral = discoveredPeripherals[current] {
      central.cancelPeripheralConnection(currentPeripheral)
    }

    discoveredServices = []
    emitServices()
    connectedPeripheralUUID = uuid
    cbPeripheral.delegate = self
    central.connect(cbPeripheral, options: nil)
  }

  // MARK: - Peripheral (clone) role

  private func startCloning(name: String) {
    pendingName = name.isEmpty ? "Cloned Device" : name
    wantsToAdvertise = true
    switch peripheralManager.state {
    case .poweredOn:
      buildAndAdvertise()
    case .poweredOff:
      emitAdvertising("Turn on Bluetooth to broadcast")
    default:
      emitAdvertising("Peripheral mode isn't available here")
    }
  }

  private func stopCloning() {
    peripheralManager.stopAdvertising()
    peripheralManager.removeAllServices()
    servicesToAdd.removeAll()
    addedCount = 0
    valueStore.removeAll()
    wantsToAdvertise = false
    isAdvertising = false
    emitAdvertising("")
  }

  private func buildAndAdvertise() {
    peripheralManager.stopAdvertising()
    peripheralManager.removeAllServices()
    servicesToAdd.removeAll()
    addedCount = 0

    var skipped = 0
    for service in discoveredServices {
      if reservedServiceUUIDs.contains(service.uuid.uppercased()) {
        skipped += 1
        continue
      }
      let mutable = CBMutableService(type: CBUUID(string: service.uuid), primary: service.isPrimary)
      mutable.characteristics = service.characteristics.map { ch in
        var props: CBCharacteristicProperties = []
        if ch.rawProperties.contains(.read) { props.insert(.read) }
        if ch.rawProperties.contains(.write) { props.insert(.write) }
        if ch.rawProperties.contains(.writeWithoutResponse) { props.insert(.writeWithoutResponse) }
        if ch.rawProperties.contains(.notify)
          || ch.rawProperties.contains(.notifyEncryptionRequired) { props.insert(.notify) }
        if ch.rawProperties.contains(.indicate)
          || ch.rawProperties.contains(.indicateEncryptionRequired) { props.insert(.indicate) }

        var permissions: CBAttributePermissions = []
        if props.contains(.read) { permissions.insert(.readable) }
        if props.contains(.write) || props.contains(.writeWithoutResponse) {
          permissions.insert(.writeable)
        }
        return CBMutableCharacteristic(
          type: CBUUID(string: ch.uuid), properties: props, value: nil, permissions: permissions)
      }
      servicesToAdd.append(mutable)
    }

    guard !servicesToAdd.isEmpty else {
      if skipped > 0 {
        emitAdvertising("⚠️ Skipped \(skipped) standard service(s) (not allowed)")
      } else {
        emitAdvertising("Nothing to broadcast (no clonable services)")
      }
      return
    }

    let skippedMsg = skipped > 0 ? " (skipped \(skipped) standard service)" : ""
    emitAdvertising("Adding \(servicesToAdd.count) service(s)…\(skippedMsg)")
    for service in servicesToAdd { peripheralManager.add(service) }
  }

  private func startAdvertising() {
    let primaryUUIDs = servicesToAdd.filter { $0.isPrimary }.map { $0.uuid }
    peripheralManager.startAdvertising([
      CBAdvertisementDataLocalNameKey: pendingName,
      CBAdvertisementDataServiceUUIDsKey: primaryUUIDs,
    ])
  }
}

// MARK: - FlutterStreamHandler

extension BleBridge: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    // Push current snapshots immediately so the UI is correct on attach.
    emitState()
    emitDevices()
    emitConnection()
    emitServices()
    emitAdvertising(isAdvertising ? "Broadcasting as \"\(pendingName)\"" : "")
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

// MARK: - CBCentralManagerDelegate

extension BleBridge: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ manager: CBCentralManager) {
    emitState()
  }

  func centralManager(
    _ manager: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let device = Peripheral(
      id: peripheral.identifier, name: peripheral.name ?? "Unknown", rssi: RSSI.intValue)
    discoveredPeripherals[device.id] = peripheral
    if let index = orderedPeripherals.firstIndex(where: { $0.id == device.id }) {
      orderedPeripherals[index] = device
    } else {
      orderedPeripherals.append(device)
    }
    emitDevices()
  }

  func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.discoverServices(nil)
  }

  func centralManager(
    _ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    if peripheral.identifier == connectedPeripheralUUID { connectedPeripheralUUID = nil }
    emitConnection()
  }

  func centralManager(
    _ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    if peripheral.identifier == connectedPeripheralUUID { connectedPeripheralUUID = nil }
    emitConnection()
  }
}

// MARK: - CBPeripheralDelegate

extension BleBridge: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let discovered = peripheral.services else { return }
    discoveredServices = discovered.map {
      ServiceInfo(uuid: $0.uuid.uuidString, isPrimary: $0.isPrimary, characteristics: [])
    }
    emitConnection()
    emitServices()
    for service in discovered { peripheral.discoverCharacteristics(nil, for: service) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard let chars = service.characteristics else { return }
    let serviceUUID = service.uuid.uuidString
    let mapped = chars.map { CharacteristicInfo(uuid: $0.uuid.uuidString, rawProperties: $0.properties) }
    if let index = discoveredServices.firstIndex(where: { $0.uuid == serviceUUID }) {
      discoveredServices[index].characteristics = mapped
    }
    emitServices()
  }
}

// MARK: - CBPeripheralManagerDelegate

extension BleBridge: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
    switch manager.state {
    case .poweredOn:
      if wantsToAdvertise && !isAdvertising { buildAndAdvertise() }
    case .poweredOff:
      if wantsToAdvertise || isAdvertising { emitAdvertising("Bluetooth is off") }
      isAdvertising = false
    default:
      if wantsToAdvertise {
        emitAdvertising("Bluetooth unavailable (state \(manager.state.rawValue))")
      }
    }
  }

  func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    if let error = error {
      emitAdvertising("Couldn't add \(service.uuid): \(error.localizedDescription)")
      return
    }
    addedCount += 1
    if addedCount == servicesToAdd.count { startAdvertising() }
  }

  func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
    if let error = error {
      isAdvertising = false
      emitAdvertising("Advertising failed: \(error.localizedDescription)")
    } else {
      isAdvertising = true
      emitAdvertising("Broadcasting as \"\(pendingName)\"")
    }
  }

  func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    request.value = valueStore[request.characteristic.uuid] ?? Data()
    manager.respond(to: request, withResult: .success)
  }

  func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      if let value = request.value { valueStore[request.characteristic.uuid] = value }
    }
    if let first = requests.first { manager.respond(to: first, withResult: .success) }
  }

  func peripheralManager(
    _ manager: CBPeripheralManager, central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    emitAdvertising("Central subscribed to \(characteristic.uuid)")
  }
}

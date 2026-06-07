//
//  BLEPeripheralManager.swift
//  BLUE
//
//  Created by Awasthi, Sumit on 07/06/26.
//

import Combine
import CoreBluetooth


class BLEPeripheralManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {

    private var manager: CBPeripheralManager!

    @Published var isAdvertising = false
    @Published var statusMessage = ""

    private var pendingServices: [DiscoveredService] = []
    private var pendingName = "Cloned Device"
    private var servicesToAdd: [CBMutableService] = []
    private var addedCount = 0
    private var valueStore: [CBUUID: Data] = [:]
    // Services that iOS doesn't allow peripheral managers to advertise
    private let reservedServiceUUIDs: Set<String> = [
        "1800",  // Generic Access
        "1801",  // Generic Attribute
        "1805",  // Current Time Service
        "180A",  // Device Information
        "180D",  // Heart Rate
        "180F",  // Battery Service
        "1810",  // Blood Pressure
        "1811",  // Alert Notification Service
        "1814",  // Running Speed and Cadence
        "1816",  // Cycling Speed and Cadence
        "1818",  // Cycling Power
        "181A",  // Glucose
        "181B",  // Health Thermometer
        "181C",  // Blood Pressure
        "181D",  // Internet Protocol Support
        "181E",  // HTTP Proxy
        "181F",  // Transport Discovery
        "1820",  // Mesh Provisioning
        "1821",  // Mesh Proxy
        "1823",  // Mesh Beacon
        "1829"   // GATT over BLE
    ]

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func startCloning(services: [DiscoveredService], name: String) {
        pendingServices = services
        pendingName = name.isEmpty ? "Cloned Device" : name
        switch manager.state {
        case .poweredOn:
            statusMessage = "Preparing to broadcast…"
            buildAndAdvertise()
        case .poweredOff:
            statusMessage = "Turn on Bluetooth to broadcast"
        default:
            statusMessage = "Peripheral mode isn't available here (use a real device)"
        }
    }

    func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
        servicesToAdd.removeAll()
        addedCount = 0
        valueStore.removeAll()
        pendingServices = []
        isAdvertising = false
        statusMessage = ""
    }

    private func buildAndAdvertise() {
        manager.stopAdvertising()
        manager.removeAllServices()
        servicesToAdd.removeAll()
        addedCount = 0

        var skippedCount = 0
        
        for service in pendingServices {
            if reservedServiceUUIDs.contains(service.uuid.uppercased()) {
                skippedCount += 1
                continue
            }

            let mutableService = CBMutableService(type: CBUUID(string: service.uuid),
                                                  primary: service.isPrimary)

            mutableService.characteristics = service.characteristics.map { ch in
                var props: CBCharacteristicProperties = []
                if ch.rawProperties.contains(.read)                 { props.insert(.read) }
                if ch.rawProperties.contains(.write)                { props.insert(.write) }
                if ch.rawProperties.contains(.writeWithoutResponse) { props.insert(.writeWithoutResponse) }
                if ch.rawProperties.contains(.notify) ||
                   ch.rawProperties.contains(.notifyEncryptionRequired)   { props.insert(.notify) }
                if ch.rawProperties.contains(.indicate) ||
                   ch.rawProperties.contains(.indicateEncryptionRequired) { props.insert(.indicate) }

                var permissions: CBAttributePermissions = []
                if props.contains(.read) { permissions.insert(.readable) }
                if props.contains(.write) || props.contains(.writeWithoutResponse) {
                    permissions.insert(.writeable)
                }

                return CBMutableCharacteristic(type: CBUUID(string: ch.uuid),
                                               properties: props,
                                               value: nil,
                                               permissions: permissions)
            }
            servicesToAdd.append(mutableService)
        }

        guard !servicesToAdd.isEmpty else {
            if skippedCount > 0 {
                statusMessage = "⚠️ Skipped \(skippedCount) standard service(s) (not allowed by iOS)"
            } else {
                statusMessage = "Nothing to broadcast (no clonable services)"
            }
            return
        }

        let skippedMsg = skippedCount > 0 ? " (skipped \(skippedCount) standard service)" : ""
        statusMessage = "Adding \(servicesToAdd.count) service(s)…\(skippedMsg)"
        for service in servicesToAdd { manager.add(service) }
    }

    private func startAdvertising() {
        let primaryUUIDs = servicesToAdd.filter { $0.isPrimary }.map { $0.uuid }
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: pendingName,
            CBAdvertisementDataServiceUUIDsKey: primaryUUIDs
        ])
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if !pendingServices.isEmpty && !isAdvertising {
                statusMessage = "Preparing to broadcast…"
                buildAndAdvertise()
            }
        case .poweredOff:
            if !pendingServices.isEmpty || isAdvertising { statusMessage = "Bluetooth is off" }
            isAdvertising = false
        default:
            if !pendingServices.isEmpty {
                statusMessage = "Bluetooth unavailable (state \(peripheral.state.rawValue))"
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            statusMessage = "Couldn't add \(service.uuid): \(error.localizedDescription)"
            return
        }
        addedCount += 1
        if addedCount == servicesToAdd.count { startAdvertising() }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            statusMessage = "Advertising failed: \(error.localizedDescription)"
            isAdvertising = false
        } else {
            statusMessage = "Broadcasting as \"\(pendingName)\""
            isAdvertising = true
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        request.value = valueStore[request.characteristic.uuid] ?? Data()
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value { valueStore[request.characteristic.uuid] = value }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        statusMessage = "Central subscribed to \(characteristic.uuid)"
    }
}

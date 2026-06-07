//
//  BLEManager.swift
//  BLUE
//
//  Created by Awasthi, Sumit on 07/06/26.
//

import ObjectiveC
import Combine
import CoreBluetooth


// MARK: - Bluetooth Manager

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var myCentral: CBCentralManager!
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    @Published var connectedPeripheralUUID: UUID?
    @Published var services: [DiscoveredService] = []

    // Keep a reference to each discovered CBPeripheral so we can connect to it later.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        myCentral = CBCentralManager(delegate: self, queue: nil)
    }

    // Called when the central manager's state updates
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isSwitchedOn = central.state == .poweredOn
    }

    // Called when a peripheral is discovered
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let newPeripheral = Peripheral(id: peripheral.identifier,
                                       name: peripheral.name ?? "Unknown",
                                       rssi: RSSI.intValue)
        DispatchQueue.main.async {
            // Remember the underlying CBPeripheral so connect(to:) can use it.
            self.discoveredPeripherals[peripheral.identifier] = peripheral

            // Doing the "already in the list?" check and the change together, here on
            // the main thread, prevents the same device being added twice (the duplicate
            // ID warning). If it's already known we just refresh it (updates RSSI).
            if let index = self.peripherals.firstIndex(where: { $0.id == newPeripheral.id }) {
                self.peripherals[index] = newPeripheral
            } else {
                self.peripherals.append(newPeripheral)
            }
        }
    }
    
    // new method
    func stopScanningKeepingResults() {
        guard myCentral.state == .poweredOn else { return }
        myCentral.stopScan()        // stops scanning but keeps the list
    }

    
    private func describeProperties(_ p: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if p.contains(.broadcast)                  { names.append("Broadcast") }
        if p.contains(.read)                       { names.append("Read") }
        if p.contains(.writeWithoutResponse)       { names.append("Write Without Response") }
        if p.contains(.write)                      { names.append("Write") }
        if p.contains(.notify)                     { names.append("Notify") }
        if p.contains(.indicate)                   { names.append("Indicate") }
        if p.contains(.authenticatedSignedWrites)  { names.append("Signed Write") }
        if p.contains(.extendedProperties)         { names.append("Extended Properties") }
        if p.contains(.notifyEncryptionRequired)   { names.append("Notify (Encrypted)") }
        if p.contains(.indicateEncryptionRequired) { names.append("Indicate (Encrypted)") }
        return names
    }

    // "Permissions" aren't visible to a central, so we infer access from properties.
    private func deriveAccess(_ p: CBCharacteristicProperties) -> [String] {
        var access: [String] = []
        if p.contains(.read) { access.append("Readable") }
        if p.contains(.write) || p.contains(.writeWithoutResponse) { access.append("Writable") }
        if p.contains(.notify) || p.contains(.indicate) { access.append("Notifiable") }
        return access
    }

    // Start scanning for peripherals
    func startScanning() {
        guard myCentral.state == .poweredOn else {
            print("Can't scan — Bluetooth isn't powered on yet")
            return
        }
        print("startScanning")
        myCentral.scanForPeripherals(withServices: nil, options: nil)
    }

    // Stop scanning for peripherals
    func stopScanning() {
        guard myCentral.state == .poweredOn else { return }
        print("stopScanning")
        myCentral.stopScan()
        peripherals.removeAll()
    }

    // Connect to a peripheral
    func connect(to peripheral: Peripheral) {
        guard let cbPeripheral = discoveredPeripherals[peripheral.id] else {
            print("Peripheral not found for connection")
            return
        }
        
        // Disconnect whatever was connected before switching.
        if let currentUUID = connectedPeripheralUUID,
           currentUUID != peripheral.id,
           let current = discoveredPeripherals[currentUUID] {
            myCentral.cancelPeripheralConnection(current)
        }
        
        services = []
        connectedPeripheralUUID = cbPeripheral.identifier
        cbPeripheral.delegate = self
        myCentral.connect(cbPeripheral, options: nil)
    }

    // Called when a peripheral connects
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil)
    }

    // Called when a connection fails
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error information")")
        if peripheral.identifier == connectedPeripheralUUID {
            connectedPeripheralUUID = nil
        }
    }

    // Called when a peripheral disconnects
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown")")
        if peripheral.identifier == connectedPeripheralUUID {
            connectedPeripheralUUID = nil
        }
    }

    // Called when services are discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let discovered = peripheral.services else { return }
        
        DispatchQueue.main.async {
            // Create a section per service; characteristics fill in next.
            self.services = discovered.map {
                DiscoveredService(uuid: $0.uuid.uuidString, isPrimary:$0.isPrimary,
                                  characteristics: [])
            }
        }
        for service in discovered {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    // Called when characteristics are discovered
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        let serviceUUID = service.uuid.uuidString
        let mapped = characteristics.map { ch in
            DiscoveredCharacteristic(
                uuid: ch.uuid.uuidString,
                properties: self.describeProperties(ch.properties),
                access: self.deriveAccess(ch.properties),
                rawProperties: ch.properties
            )
        }
        DispatchQueue.main.async {
            if let index = self.services.firstIndex(where: { $0.uuid == serviceUUID }) {
                self.services[index].characteristics = mapped
            }
        }
    }
}

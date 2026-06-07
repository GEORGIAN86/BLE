//
//  DeviceDetailView.swift
//  BLUE
//
//  Created by Awasthi, Sumit on 07/06/26.
//

import SwiftUI
import CoreBluetooth

struct DiscoveredService: Identifiable {
    let id = UUID()
    let uuid: String
    var isPrimary: Bool = true
    var characteristics: [DiscoveredCharacteristic]
}

struct DiscoveredCharacteristic: Identifiable {
    let id = UUID()
    let uuid: String
    let properties: [String]
    let access: [String]
    let rawProperties: CBCharacteristicProperties
}


// Discovered Pheripherals -> Connects to BroadCaster
struct DeviceDetailView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var advertiser: BLEPeripheralManager
    let peripheral: Peripheral
    
    @State private var isConnecting = false

    var body: some View {
        // at the top of the List { } — added:
        if !advertiser.statusMessage.isEmpty {
            Section("Broadcast") {
                Label(advertiser.statusMessage,
                      systemImage: advertiser.isAdvertising
                          ? "antenna.radiowaves.left.and.right"
                          : "info.circle")
                    .foregroundColor(advertiser.isAdvertising ? .green : .secondary)
            }
        }
        
        List {
            Section("Device") {
                LabeledContent("Name", value: peripheral.name)
                LabeledContent("UUID", value: peripheral.id.uuidString)
            }

            if bleManager.services.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Discovering services…")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ForEach(bleManager.services) { service in
                    Section("Service \(service.uuid)") {
                        ForEach(service.characteristics) { characteristic in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(characteristic.uuid)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                if !characteristic.properties.isEmpty {
                                    Text("Properties: \(characteristic.properties.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if !characteristic.access.isEmpty {
                                    Text("Access: \(characteristic.access.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(peripheral.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if advertiser.isAdvertising {
                    Button("Stop") {
                        advertiser.stop()
                    }
                } else if bleManager.connectedPeripheralUUID == peripheral.id && !bleManager.services.isEmpty {
                    // Already connected with services discovered
                    Button("Clone") {
                        bleManager.stopScanningKeepingResults()
                        advertiser.startCloning(services: bleManager.services,
                                                name: peripheral.name)
                    }
                } else if bleManager.connectedPeripheralUUID == peripheral.id {
                    // Connected but still waiting for services
                    Button("Clone") {
                        ProgressView()
                    }
                    .disabled(true)
                } else {
                    // Not connected yet
                    Button(isConnecting ? "Connecting…" : "Connect & Clone") {
                        isConnecting = true
                        // Connect to peripheral — this will trigger service discovery
                        bleManager.connect(to: peripheral)
                    }
                    .disabled(isConnecting || !bleManager.isSwitchedOn)
                }
            }
        }
        // Monitor connection state
        .onChange(of: bleManager.connectedPeripheralUUID) { oldValue, newValue in
            if newValue == peripheral.id {
                isConnecting = false
            }
        }
    }
}



//
//  BLUEApp.swift
//  BLUE
//
//  Created by Awasthi, Sumit on 03/06/26.
//

import SwiftUI
import CoreBluetooth
import Combine

// MARK: - Model

struct Peripheral: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int   // Signal strength of the peripheral the value is logarithmic , Hence low the value Higher the Strength
}


// MARK: - Main View

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var selectedPeripheralID: UUID?
    @StateObject private var advertiser = BLEPeripheralManager()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Bluetooth status
                HStack {
                    Circle()
                        .fill(bleManager.isSwitchedOn ? .green : .red)
                        .frame(width: 12, height: 12)
                    Text(bleManager.isSwitchedOn ? "Bluetooth is ON" : "Bluetooth is OFF")
                        .foregroundColor(bleManager.isSwitchedOn ? .green : .red)
                    Spacer()
                }
                .padding()

                // Discovered devices — tap to select (shows detail on the other side)
                List(bleManager.peripherals, selection: $selectedPeripheralID) { peripheral in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(peripheral.name)
                                .font(.headline)
                            Text(peripheral.id.uuidString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(peripheral.rssi) dBm")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if bleManager.connectedPeripheralUUID == peripheral.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if bleManager.peripherals.isEmpty {
                        Text("No devices found yet.\nTap Start Scanning to begin.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                }

                // Scan controls
                HStack(spacing: 16) {
                    Button("Start Scanning") {
                        bleManager.startScanning()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bleManager.isSwitchedOn)

                    Button("Stop Scanning") {
                        bleManager.stopScanning()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bleManager.isSwitchedOn)
                }
                .padding()
            }
            .navigationTitle("Bluetooth Devices")
        } detail: {
            if let id = selectedPeripheralID,
               let peripheral = bleManager.peripherals.first(where: { $0.id == id }) {
                DeviceDetailView(bleManager: bleManager, advertiser: advertiser, peripheral: peripheral)
                    .id(peripheral.id)
            } else {
                Text("Select a device to view its services and characteristics.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct BLUEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#Preview {
    ContentView()
}

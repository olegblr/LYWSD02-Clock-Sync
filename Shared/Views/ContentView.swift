//
//  ContentView.swift
//  Shared
//
//  Created by Rick Kerkhof on 05/11/2021.
//

import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @StateObject private var bleClient = BLEClient()
    @State private var selectedPeripheral: BLEDeviceModel? = nil

    var body: some View {
        Group {
            if let device = selectedPeripheral {
                // Directly show the device view once discovered
                DeviceView(peripheral: device)
            } else {
                VStack(spacing: 16) {
                    ProgressView("Scanning for device…")
                    if bleClient.scanning {
                        Text("Searching…").foregroundColor(.secondary).font(.footnote)
                    } else {
                        Button { bleClient.triggerScan() } label: { Label("Retry Scan", systemImage: "arrow.clockwise") }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environmentObject(bleClient)
        .onAppear {
            // Start scan if nothing yet
            if bleClient.discoveredPeripherals.isEmpty { bleClient.triggerScan() }
            // If a device already discovered (e.g. returning from background), select it
            if selectedPeripheral == nil, let first = bleClient.discoveredPeripherals.first { selectedPeripheral = first }
        }
        .onDisappear { bleClient.stopScan() }
        .adaptiveOnChange(of: bleClient.discoveredPeripherals) { list in
            if selectedPeripheral == nil, let first = list.first {
                selectedPeripheral = first
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

// Adaptive onChange extension handling API differences (macOS 14+/iOS 17+ two-parameter vs older single-parameter)
private extension View {
    @ViewBuilder
    func adaptiveOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value) { newValue in action(newValue) }
        }
    }
}

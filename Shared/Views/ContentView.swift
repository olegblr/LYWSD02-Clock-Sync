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
    // Automatically selected peripheral (only one expected)
    @State private var selectedPeripheral: BLEDeviceModel? = nil
    @State private var navigateToDevice: Bool = false

    var body: some View {
        Group {
            if #available(macOS 13.0, iOS 16.0, *) {
                NavigationStack {
                    deviceListView
                        .navigationTitle("Discovered Devices")
                        .navigationDestination(isPresented: $navigateToDevice) {
                            if let device = selectedPeripheral {
                                DeviceView(peripheral: device)
                            } else { EmptyView() }
                        }
                }
            } else {
                NavigationView { deviceListView.navigationTitle("Discovered Devices") }
            }
        }
        .environmentObject(bleClient)
        .onDisappear { bleClient.stopScan() }
        // Replaced deprecated single-parameter onChange with adaptive helper
        .adaptiveOnChange(of: bleClient.discoveredPeripherals) { list in
            if selectedPeripheral == nil, let first = list.first {
                selectedPeripheral = first
                DispatchQueue.main.async { navigateToDevice = true }
            }
        }
        .onAppear {
            if selectedPeripheral == nil, let first = bleClient.discoveredPeripherals.first {
                selectedPeripheral = first
                navigateToDevice = true
            }
        }
    }

    // MARK: Subviews
    private var deviceListView: some View {
        ZStack {
            List {
                ForEach(bleClient.discoveredPeripherals, id: \.identifier) { peripheral in
                    NavigationLink(destination: DeviceView(peripheral: peripheral)) {
                        VStack(alignment: .leading) {
                            Text(peripheral.name)
                            Text(peripheral.identifier).font(.footnote)
                        }
                    }
                }
            }
            if bleClient.discoveredPeripherals.isEmpty && !bleClient.scanning {
                ProgressView("Waiting for device...")
            }
        }
        .toolbar {
            Button(action: {
                if bleClient.scanning { bleClient.stopScan() } else { bleClient.triggerScan() }
            }) {
                Image(systemName: bleClient.scanning ? "stop.circle.fill" : "arrow.clockwise")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// Adaptive onChange extension handling API differences (macOS 14+/iOS 17+ two-parameter vs older single-parameter)
private extension View {
    @ViewBuilder
    func adaptiveOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

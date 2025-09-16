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
        NavigationView {
            ZStack { // Use ZStack so we can place hidden navigation link
                List {
                    // Optional: show devices if more than one ever appears
                    ForEach(bleClient.discoveredPeripherals, id: \.identifier) { peripheral in
                        NavigationLink(destination: DeviceView(peripheral: peripheral)) {
                            VStack(alignment: .leading) {
                                Text(peripheral.name)
                                Text(peripheral.identifier).font(.footnote)
                            }
                        }
                    }
                }
                // Hidden programmatic navigation link triggered once first device is found
                NavigationLink(isActive: $navigateToDevice) {
                    if let device = selectedPeripheral {
                        DeviceView(peripheral: device)
                    } else { EmptyView() }
                } label: { EmptyView() }.hidden()

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
            }.navigationTitle("Discovered Devices")
        }.environmentObject(bleClient)
            .onDisappear { bleClient.stopScan() }
            .onChange(of: bleClient.discoveredPeripherals) { list in
                // Auto select first discovered peripheral once
                if selectedPeripheral == nil, let first = list.first {
                    selectedPeripheral = first
                    // Defer navigation to next runloop to avoid SwiftUI warnings
                    DispatchQueue.main.async { navigateToDevice = true }
                }
            }
            .onAppear {
                // If already discovered (unlikely on cold start), navigate immediately
                if selectedPeripheral == nil, let first = bleClient.discoveredPeripherals.first {
                    selectedPeripheral = first
                    navigateToDevice = true
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

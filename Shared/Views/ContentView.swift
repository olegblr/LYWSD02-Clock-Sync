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
            switch bleClient.bluetoothState {
            case .poweredOn:
                deviceContent
            case .poweredOff:
                statusView(symbol: "wifi.slash",
                           title: "Bluetooth is Off",
                           message: "Enable Bluetooth in system settings to discover devices.")
            case .unauthorized:
                statusView(symbol: "lock.shield",
                           title: "Bluetooth Access Required",
                           message: "Allow Bluetooth access in system settings.")
            case .unsupported:
                statusView(symbol: "exclamationmark.triangle",
                           title: "Bluetooth Not Supported",
                           message: "This device doesn't support Bluetooth Low Energy.")
            case .resetting:
                statusView(symbol: "arrow.triangle.2.circlepath",
                           title: "Resetting…",
                           message: "Bluetooth is resetting. Please wait.")
            case .unknown:
                ProgressView("Initializing Bluetooth…")
            @unknown default:
                ProgressView()
            }
        }
        .environmentObject(bleClient)
        .onAppear {
            if bleClient.discoveredPeripherals.isEmpty, bleClient.bluetoothState == .poweredOn {
                bleClient.triggerScan()
            }
            if selectedPeripheral == nil, let first = bleClient.discoveredPeripherals.first {
                selectedPeripheral = first
            }
        }
        .onDisappear { bleClient.stopScan() }
        .adaptiveOnChange(of: bleClient.discoveredPeripherals) { list in
            if selectedPeripheral == nil, let first = list.first {
                selectedPeripheral = first
            }
        }
        .alert(item: errorBinding) { wrapped in
            Alert(
                title: Text("Bluetooth Error"),
                message: Text([wrapped.error.errorDescription, wrapped.error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")),
                dismissButton: .default(Text("OK")) { bleClient.lastError = nil }
            )
        }
    }

    @ViewBuilder
    private var deviceContent: some View {
        if let device = selectedPeripheral {
            DeviceView(peripheral: device)
        } else {
            VStack(spacing: 16) {
                ProgressView("Scanning for device…")
                if bleClient.scanning {
                    Text("Searching…").foregroundColor(.secondary).font(.footnote)
                } else {
                    Button {
                        bleClient.triggerScan()
                    } label: {
                        Label("Retry Scan", systemImage: "arrow.clockwise")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusView(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error binding (Identifiable wrapper for alert)

    private struct ErrorWrapper: Identifiable {
        let id = UUID()
        let error: BLEError
    }

    private var errorBinding: Binding<ErrorWrapper?> {
        Binding(
            get: { bleClient.lastError.map { ErrorWrapper(error: $0) } },
            set: { _ in bleClient.lastError = nil }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

// Adaptive onChange extension handling API differences (macOS 14+/iOS 17+ two-parameter vs older single-parameter)
extension View {
    @ViewBuilder
    func adaptiveOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value) { newValue in action(newValue) }
        }
    }
}

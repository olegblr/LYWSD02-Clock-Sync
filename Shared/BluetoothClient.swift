//
//  BluetoothClient.swift
//  LYWSD02 Clock Sync
//
//  Created by Rick Kerkhof on 05/11/2021.
//

import CoreBluetooth
import Foundation
import os.log

@MainActor
final class BLEClient: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published public private(set) var discoveredPeripherals: [BLEDeviceModel] = []
    @Published private(set) var scanning: Bool = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published var lastError: BLEError?

    private var manager: CBCentralManager!

    // Cache for peripheral models
    private var peripheralCache: [UUID: BLEDeviceModel] = [:]
    private var lastSeen: [UUID: Date] = [:]

    // Connection management
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var reconnectionAttempts: [UUID: Int] = [:]
    /// IDs we explicitly asked to disconnect — prevents auto-reconnect for them.
    private var intentionalDisconnects: Set<UUID> = []

    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "BLEClient")

    override required init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Central state

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.bluetoothState = state
            self.logger.info("Central state changed: \(state.rawValue, privacy: .public)")

            switch state {
            case .poweredOff:
                self.lastError = .bluetoothPoweredOff
                self.stopScan()
            case .unauthorized:
                self.lastError = .bluetoothUnauthorized
                self.stopScan()
            case .unsupported:
                self.lastError = .bluetoothUnsupported
                self.stopScan()
            case .poweredOn:
                self.lastError = nil
                self.triggerScan()
            case .resetting, .unknown:
                self.stopScan()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Scanning

    func triggerScan() {
        guard manager.state == .poweredOn else { return }
        // Don't wipe currently connected devices; just refresh "lastSeen".
        manager.scanForPeripherals(
            withServices: LYWSD02UUID.serviceCBUUIDs,
            options: nil
        )
        scanning = true
        logger.info("Scanning started")
        scheduleStaleCleanup()
    }

    func stopScan() {
        guard scanning else { return }
        manager.stopScan()
        scanning = false
        logger.info("Scanning stopped")
    }

    private var staleCleanupTask: Task<Void, Never>?
    private func scheduleStaleCleanup() {
        staleCleanupTask?.cancel()
        staleCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LYWSD02Constants.staleDeviceTimeout * 1_000_000_000))
                guard let self = self else { return }
                await MainActor.run { self.purgeStaleDevices() }
            }
        }
    }

    private func purgeStaleDevices() {
        let cutoff = Date().addingTimeInterval(-LYWSD02Constants.staleDeviceTimeout)
        let stale = lastSeen.filter { $0.value < cutoff }.map(\.key)
        for id in stale {
            // Don't drop a device we're connected to.
            if let model = peripheralCache[id], model.peripheral.state == .connected || model.peripheral.state == .connecting {
                continue
            }
            discoveredPeripherals.removeAll { $0.peripheral.identifier == id }
            peripheralCache.removeValue(forKey: id)
            lastSeen.removeValue(forKey: id)
        }
    }

    // MARK: - Connect / Disconnect

    func connect(to model: BLEDeviceModel) {
        let id = model.peripheral.identifier
        intentionalDisconnects.remove(id)

        switch model.peripheral.state {
        case .connected, .connecting:
            return
        default:
            break
        }

        manager.connect(model.peripheral, options: nil)
        model.updateConnectionState(.connecting)
        startConnectionTimeout(for: model)
        logger.info("Connecting to \(model.name, privacy: .public)")
    }

    func disconnect(_ model: BLEDeviceModel) {
        let id = model.peripheral.identifier
        intentionalDisconnects.insert(id)

        connectionTimeouts[id]?.cancel()
        connectionTimeouts.removeValue(forKey: id)
        reconnectionAttempts.removeValue(forKey: id)

        guard model.peripheral.state != .disconnected else {
            model.updateConnectionState(.disconnected)
            return
        }

        manager.cancelPeripheralConnection(model.peripheral)
        logger.info("Disconnecting from \(model.name, privacy: .public)")
    }

    private func startConnectionTimeout(for model: BLEDeviceModel) {
        let id = model.peripheral.identifier
        connectionTimeouts[id]?.cancel()
        connectionTimeouts[id] = Task { [weak self, weak model] in
            try? await Task.sleep(nanoseconds: UInt64(LYWSD02Constants.connectionTimeout * 1_000_000_000))
            guard !Task.isCancelled,
                  let self = self,
                  let model = model else { return }
            if model.peripheral.state != .connected {
                self.logger.error("Connection timeout for \(model.name, privacy: .public)")
                self.lastError = .connectionTimeout
                self.manager.cancelPeripheralConnection(model.peripheral)
            }
            self.connectionTimeouts.removeValue(forKey: id)
        }
    }

    // MARK: - Discovery

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.lastSeen[id] = Date()

            let model: BLEDeviceModel
            if let cached = self.peripheralCache[id] {
                model = cached
            } else {
                model = BLEDeviceModel(peripheral)
                self.peripheralCache[id] = model
                self.logger.info("Discovered new device: \(peripheral.name ?? "Unknown", privacy: .private(mask: .hash))")
            }

            if !self.discoveredPeripherals.contains(where: { $0.peripheral.identifier == id }) {
                self.discoveredPeripherals.append(model)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionTimeouts[id]?.cancel()
            self.connectionTimeouts.removeValue(forKey: id)
            self.reconnectionAttempts.removeValue(forKey: id)

            if let model = self.peripheralCache[id] {
                model.updateConnectionState(.connected)
            }
            self.logger.info("Connected to \(peripheral.name ?? "Unknown", privacy: .private(mask: .hash))")
        }

        peripheral.discoverServices([LYWSD02UUID.Service.Data.cbuuid])
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        let id = peripheral.identifier
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.logger.warning("Disconnected from \(peripheral.name ?? "Unknown", privacy: .private(mask: .hash))")
            if let errorDescription = errorDescription {
                self.logger.error("Disconnect error: \(errorDescription, privacy: .public)")
            }

            if let model = self.peripheralCache[id] {
                model.updateConnectionState(.disconnected)
                model.handleDisconnection()
            }

            // Skip auto-reconnect if user explicitly disconnected.
            if self.intentionalDisconnects.contains(id) {
                self.intentionalDisconnects.remove(id)
                self.reconnectionAttempts.removeValue(forKey: id)
                return
            }

            let attempts = self.reconnectionAttempts[id, default: 0]
            guard attempts < LYWSD02Constants.maxReconnectionAttempts else {
                self.logger.error("Max reconnection attempts reached")
                self.reconnectionAttempts.removeValue(forKey: id)
                return
            }
            self.reconnectionAttempts[id] = attempts + 1

            let delay = LYWSD02Constants.reconnectionDelays[
                min(attempts, LYWSD02Constants.reconnectionDelays.count - 1)
            ]
            self.logger.info("Will reconnect in \(delay, privacy: .public)s (attempt \(attempts + 1, privacy: .public))")

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self = self else { return }
                await MainActor.run {
                    if let model = self.peripheralCache[id], !self.intentionalDisconnects.contains(id) {
                        self.connect(to: model)
                    }
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        let id = peripheral.identifier
        let desc = error?.localizedDescription ?? "Unknown error"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionTimeouts[id]?.cancel()
            self.connectionTimeouts.removeValue(forKey: id)
            if let model = self.peripheralCache[id] {
                model.updateConnectionState(.disconnected)
            }
            self.lastError = error.map { .connectionFailed($0) } ?? .connectionTimeout
            self.logger.error("Failed to connect: \(desc, privacy: .public)")
        }
    }

    deinit {
        staleCleanupTask?.cancel()
        for task in connectionTimeouts.values { task.cancel() }
    }
}

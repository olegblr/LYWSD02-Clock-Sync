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
    @Published public var discoveredPeripherals: [BLEDeviceModel] = []
    @Published var scanning: Bool = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var errorMessage: String?
    
    private var manager: CBCentralManager!
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "BLE")
    
    override required init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
        }
        
        switch central.state {
        case .unknown:
            logger.info("Bluetooth state: unknown")
        case .resetting:
            logger.info("Bluetooth state: resetting")
        case .unsupported:
            logger.warning("Bluetooth state: unsupported")
            Task { @MainActor in
                self.errorMessage = "Bluetooth is not supported on this device"
            }
        case .unauthorized:
            logger.warning("Bluetooth state: unauthorized")
            Task { @MainActor in
                self.errorMessage = "Bluetooth access is not authorized. Please enable it in Settings."
            }
        case .poweredOff:
            logger.info("Bluetooth state: powered off")
            Task { @MainActor in
                self.stopScan()
                self.errorMessage = "Bluetooth is powered off. Please turn it on."
            }
        case .poweredOn:
            logger.info("Bluetooth state: powered on")
            Task { @MainActor in
                self.errorMessage = nil
                self.triggerScan()
            }
        @unknown default:
            logger.warning("Bluetooth state: unknown default case")
        }
    }
    
    func triggerScan() {
        guard manager.state == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on")
            return
        }
        
        discoveredPeripherals.removeAll()
        manager.scanForPeripherals(
            withServices: LYWSD02UUID.serviceCBUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanning = true
        logger.info("Started scanning for peripherals")
    }
    
    func stopScan() {
        manager.stopScan()
        scanning = false
        logger.info("Stopped scanning for peripherals")
    }
    
    func connect(to model: BLEDeviceModel) {
        if model.peripheral.state == .connected {
            logger.info("Already connected to \(model.name)")
            return
        }
        
        logger.info("Connecting to \(model.name)")
        manager.connect(model.peripheral, options: nil)
    }
    
    func disconnect(_ model: BLEDeviceModel) {
        if model.peripheral.state == .disconnected {
            logger.info("Already disconnected from \(model.name)")
            return
        }
        
        logger.info("Disconnecting from \(model.name)")
        manager.cancelPeripheralConnection(model.peripheral)
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        Task { @MainActor in
            logger.debug("Discovered peripheral: \(peripheral.identifier.uuidString)")
            
            if !self.discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                let deviceModel = BLEDeviceModel(peripheral)
                self.discoveredPeripherals.append(deviceModel)
                logger.info("Added new device: \(peripheral.name ?? "Unknown")")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil)
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.error("Failed to connect to peripheral: \(error.localizedDescription)")
            Task { @MainActor in
                self.errorMessage = "Failed to connect: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.error("Disconnected with error: \(error.localizedDescription)")
        } else {
            logger.info("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        }
    }
}

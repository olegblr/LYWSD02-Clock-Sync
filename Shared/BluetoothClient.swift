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
class BLEClient: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published public var discoveredPeripherals: [BLEDeviceModel] = []
    
    // detached from the manager because this lets us use a published property
    @Published var scanning: Bool = false
    
    private var manager: CBCentralManager!
    
    // Cache for peripheral models
    private var peripheralCache: [UUID: BLEDeviceModel] = [:]
    
    // Connection management
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var reconnectionAttempts: [UUID: Int] = [:]
    private let maxReconnectionAttempts = 3
    
    // Logger
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "BLEClient")
    
    override required init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .unknown:
                print("central.state is .unknown")
            case .resetting:
                print("central.state is .resetting")
            case .unsupported:
                print("central.state is .unsupported")
            case .unauthorized:
                print("central.state is .unauthorized")
            case .poweredOff:
                print("central.state is .poweredOff")
                stopScan()
            case .poweredOn:
                print("central.state is .poweredOn")
                triggerScan()
            @unknown default:
                print("Unknown state")
            }
        }
    }
    
    func triggerScan() {
        discoveredPeripherals.removeAll()
        manager.scanForPeripherals(withServices: [CBUUID(string: LYWSD02UUID.Service.Unknown1.rawValue), CBUUID(string: LYWSD02UUID.Service.Unknown2.rawValue)], options: nil)
        scanning = true
    }
    
    func stopScan() {
        manager.stopScan()
        scanning = false
    }
    
    func connect(to model: BLEDeviceModel) {
        if model.peripheral.state == .connected {
            return
        }
        
        manager.connect(model.peripheral, options: nil)
    }
    
    func disconnect(_ model: BLEDeviceModel) {
        if model.peripheral.state == .disconnected {
            return
        }
        
        let peripheralID = model.peripheral.identifier
        
        // Cancel any pending timeout
        connectionTimeouts[peripheralID]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheralID)
        
        // Reset reconnection attempts
        reconnectionAttempts.removeValue(forKey: peripheralID)
        
        manager.cancelPeripheralConnection(model.peripheral)
        logger.info("🔌 Disconnecting from \(model.name)")
    }
    
    // ✅ УЛУЧШЕНО: С кэшированием (O(1) вместо O(n))
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name ?? "Unknown"
        
        Task { @MainActor in
            // Переиспользовать модель из кэша или создать новую
            let model: BLEDeviceModel
            if let cached = peripheralCache[peripheralID] {
                model = cached
            } else {
                model = BLEDeviceModel(peripheral)
                peripheralCache[peripheralID] = model
                logger.info("📱 Discovered new device: \(peripheralName) (\(peripheralID.uuidString))")
            }
            
            // Добавить в список если еще нет
            if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheralID }) {
                discoveredPeripherals.append(model)
            }
        }
    }
    
    // ✅ НОВОЕ: Обработка успешного подключения
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name ?? "Unknown"
        
        Task { @MainActor in
            // Отменить таймаут
            connectionTimeouts[peripheralID]?.cancel()
            connectionTimeouts.removeValue(forKey: peripheralID)
            
            // Сбросить счетчик переподключений
            reconnectionAttempts.removeValue(forKey: peripheralID)
            
            logger.info("✅ Connected to \(peripheralName)")
        }
        
        peripheral.discoverServices(nil)
    }
    
    // ✅ НОВОЕ: Обработка отключения с auto-reconnect
    nonisolated func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name ?? "Unknown"
        let errorDescription = error?.localizedDescription
        
        Task { @MainActor in
            logger.warning("⚠️ Disconnected from \(peripheralName)")
            
            if let errorDescription = errorDescription {
                logger.error("Disconnect error: \(errorDescription)")
            }
            
            // Попытаться переподключиться
            let attempts = reconnectionAttempts[peripheralID, default: 0]
            
            guard attempts < self.maxReconnectionAttempts else {
                logger.error("❌ Max reconnection attempts reached for \(peripheralName)")
                reconnectionAttempts.removeValue(forKey: peripheralID)
                return
            }
            
            reconnectionAttempts[peripheralID] = attempts + 1
            
            // Экспоненциальная задержка: 1s, 2s, 4s
            let delay = pow(2.0, Double(attempts))
            
            logger.info("🔄 Will reconnect to \(peripheralName) in \(delay)s (attempt \(attempts + 1)/\(self.maxReconnectionAttempts))")
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // Найти модель устройства
                if let model = self.peripheralCache[peripheralID] {
                    self.connect(to: model)
                }
            }
        }
    }
    
    // ✅ НОВОЕ: Обработка неудачного подключения
    nonisolated func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name ?? "Unknown"
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        
        Task { @MainActor in
            connectionTimeouts[peripheralID]?.cancel()
            connectionTimeouts.removeValue(forKey: peripheralID)
            
            logger.error("❌ Failed to connect to \(peripheralName): \(errorDescription)")
        }
    }
}

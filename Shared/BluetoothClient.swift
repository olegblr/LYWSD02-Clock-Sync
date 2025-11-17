//
//  BluetoothClient.swift
//  LYWSD02 Clock Sync
//
//  Created by Rick Kerkhof on 05/11/2021.
//  Improved by AI Assistant on 17/11/2025
//

import CoreBluetooth
import Foundation
import os.log

// MARK: - Custom Errors

enum BLEError: LocalizedError {
    case bluetoothNotReady
    case connectionTimeout
    case deviceNotFound
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .bluetoothNotReady:
            return "Bluetooth is not ready"
        case .connectionTimeout:
            return "Connection timed out"
        case .deviceNotFound:
            return "Device not found"
        case .unauthorized:
            return "Bluetooth access not authorized"
        }
    }
}

// MARK: - BLEClient Protocol (для тестируемости)

@MainActor
protocol BLEClientProtocol: AnyObject {
    var discoveredPeripherals: [BLEDeviceModel] { get }
    var scanning: Bool { get }
    var bluetoothState: CBManagerState { get }
    var errorMessage: String? { get }
    
    func triggerScan(timeout: TimeInterval)
    func stopScan()
    func connect(to model: BLEDeviceModel, timeout: TimeInterval)
    func disconnect(_ model: BLEDeviceModel)
}

// MARK: - Enhanced BLEClient

@MainActor
final class BLEClient: NSObject, ObservableObject, CBCentralManagerDelegate, BLEClientProtocol {
    
    // MARK: - Published Properties
    
    @Published public var discoveredPeripherals: [BLEDeviceModel] = []
    @Published var scanning: Bool = false
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var errorMessage: String?
    @Published var autoReconnectEnabled: Bool = true
    
    // MARK: - Private Properties
    
    private var manager: CBCentralManager!
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "BLE")
    
    // Device caching для предотвращения потери состояния
    private var deviceCache: [UUID: BLEDeviceModel] = [:]
    
    // Connection management
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var reconnectionAttempts: [UUID: Int] = [:]
    private let maxReconnectionAttempts = 3
    
    // Scan management
    private var scanTimeoutTask: Task<Void, Never>?
    private let defaultScanTimeout: TimeInterval = 30.0
    
    // MARK: - Initialization
    
    override required init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.cleanup()
        }
    }
    
    // MARK: - Public Methods
    
    /// Начать сканирование устройств с таймаутом
    func triggerScan(timeout: TimeInterval = 30.0) {
        guard manager.state == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on (state: \(String(describing: self.manager.state)))")
            errorMessage = bluetoothStateMessage(for: self.manager.state)
            return
        }
        
        logger.info("Starting scan with \(timeout)s timeout")
        
        // Не очищаем deviceCache, но обновляем discoveredPeripherals
        discoveredPeripherals.removeAll()
        
        manager.scanForPeripherals(
            withServices: LYWSD02UUID.serviceCBUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanning = true
        errorMessage = nil
        
        // Автоматическая остановка сканирования через timeout
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                if self.scanning {
                    self.stopScan()
                    self.logger.info("Scan stopped automatically after \(timeout)s")
                    
                    if self.discoveredPeripherals.isEmpty {
                        self.errorMessage = "No devices found. Make sure the device is nearby and powered on."
                    }
                }
            } catch {
                // Task was cancelled
            }
        }
    }
    
    /// Остановить сканирование
    func stopScan() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        manager.stopScan()
        scanning = false
        logger.info("Stopped scanning for peripherals")
    }
    
    /// Подключиться к устройству с таймаутом
    func connect(to model: BLEDeviceModel, timeout: TimeInterval = 10.0) {
        if model.peripheral.state == .connected {
            logger.info("Already connected to \(model.name)")
            return
        }
        
        if model.peripheral.state == .connecting {
            logger.info("Already connecting to \(model.name)")
            return
        }
        
        logger.info("Connecting to \(model.name) with \(timeout)s timeout")
        manager.connect(model.peripheral, options: nil)
        
        // Запустить таймаут подключения
        let peripheralID = model.peripheral.identifier
        connectionTimeouts[peripheralID]?.cancel()
        connectionTimeouts[peripheralID] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                if model.peripheral.state != .connected {
                    logger.error("Connection timeout for \(model.name)")
                    manager.cancelPeripheralConnection(model.peripheral)
                    self.errorMessage = "Connection timeout: \(model.name)"
                }
            } catch {
                // Task was cancelled - successful connection
            }
        }
    }
    
    /// Отключиться от устройства
    func disconnect(_ model: BLEDeviceModel) {
        if model.peripheral.state == .disconnected {
            logger.info("Already disconnected from \(model.name)")
            return
        }
        
        logger.info("Disconnecting from \(model.name)")
        
        // Отменить попытки переподключения
        reconnectionAttempts.removeValue(forKey: model.peripheral.identifier)
        
        manager.cancelPeripheralConnection(model.peripheral)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            let oldState = self.bluetoothState
            self.bluetoothState = central.state
            
            self.handleStateTransition(from: oldState, to: central.state)
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
                // Автоматически запускать сканирование только если нет устройств
                if self.discoveredPeripherals.isEmpty {
                    self.triggerScan()
                }
            }
        @unknown default:
            logger.warning("Bluetooth state: unknown default case")
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            logger.debug("Discovered peripheral: \(peripheral.identifier.uuidString) RSSI: \(RSSI.intValue)dBm")
            
            // Проверяем, есть ли устройство в кэше
            let device: BLEDeviceModel
            if let cachedDevice = deviceCache[peripheral.identifier] {
                device = cachedDevice
                logger.debug("Reusing cached device model for \(peripheral.name ?? "Unknown")")
            } else {
                // Создаём новое устройство и добавляем в кэш
                device = BLEDeviceModel(peripheral)
                deviceCache[peripheral.identifier] = device
                logger.info("Created new device model: \(peripheral.name ?? "Unknown")")
            }
            
            // Добавляем в список обнаруженных, если ещё нет
            if !self.discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                self.discoveredPeripherals.append(device)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            // Отменяем таймаут подключения
            self.connectionTimeouts[peripheral.identifier]?.cancel()
            self.connectionTimeouts.removeValue(forKey: peripheral.identifier)
            
            // Сбрасываем счётчик попыток переподключения
            self.reconnectionAttempts.removeValue(forKey: peripheral.identifier)
            
            logger.info("✅ Connected to peripheral: \(peripheral.name ?? "Unknown")")
            peripheral.discoverServices(nil)
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            // Отменяем таймаут
            self.connectionTimeouts[peripheral.identifier]?.cancel()
            self.connectionTimeouts.removeValue(forKey: peripheral.identifier)
            
            let errorMsg = error?.localizedDescription ?? "Unknown error"
            logger.error("❌ Failed to connect to \(peripheral.name ?? "Unknown"): \(errorMsg)")
            self.errorMessage = "Failed to connect: \(errorMsg)"
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            // Отменяем таймаут
            self.connectionTimeouts[peripheral.identifier]?.cancel()
            self.connectionTimeouts.removeValue(forKey: peripheral.identifier)
            
            if let error = error {
                logger.error("⚠️ Disconnected with error: \(error.localizedDescription)")
                
                // Автоматическое переподключение при ошибке
                if self.autoReconnectEnabled {
                    await self.attemptReconnection(to: peripheral)
                }
            } else {
                logger.info("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
                self.reconnectionAttempts.removeValue(forKey: peripheral.identifier)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleStateTransition(from oldState: CBManagerState, to newState: CBManagerState) {
        switch (oldState, newState) {
        case (.poweredOn, .poweredOff):
            logger.warning("Bluetooth was turned off - all connections will be lost")
            // Очищаем состояние подключений
            connectionTimeouts.values.forEach { $0.cancel() }
            connectionTimeouts.removeAll()
            reconnectionAttempts.removeAll()
            
        case (.poweredOff, .poweredOn):
            logger.info("Bluetooth was turned on - ready for operations")
            
        case (_, .unauthorized):
            logger.error("Bluetooth authorization was revoked")
            stopScan()
            
        case (_, .unsupported):
            logger.error("Bluetooth is not supported on this device")
            stopScan()
            
        default:
            break
        }
    }
    
    private func attemptReconnection(to peripheral: CBPeripheral) async {
        let attempts = reconnectionAttempts[peripheral.identifier] ?? 0
        
        guard attempts < self.maxReconnectionAttempts else {
            logger.error("Maximum reconnection attempts reached for \(peripheral.name ?? "Unknown")")
            errorMessage = "Failed to reconnect after \(self.maxReconnectionAttempts) attempts"
            reconnectionAttempts.removeValue(forKey: peripheral.identifier)
            return
        }
        
        reconnectionAttempts[peripheral.identifier] = attempts + 1
        
        // Экспоненциальная задержка: 1s, 2s, 4s
        let delay = TimeInterval(1 << attempts)
        logger.info("🔄 Auto-reconnection attempt \(attempts + 1)/\(self.maxReconnectionAttempts) in \(delay)s")
        
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            if let device = deviceCache[peripheral.identifier] {
                connect(to: device)
            }
        } catch {
            // Task was cancelled
            logger.debug("Reconnection cancelled")
        }
    }
    
    private func bluetoothStateMessage(for state: CBManagerState) -> String {
        switch state {
        case .poweredOff:
            return "Bluetooth is powered off. Please turn it on."
        case .unauthorized:
            return "Bluetooth access is not authorized. Please enable it in Settings."
        case .unsupported:
            return "Bluetooth is not supported on this device"
        case .resetting:
            return "Bluetooth is resetting..."
        case .unknown:
            return "Bluetooth state is unknown"
        default:
            return ""
        }
    }
    
    private func cleanup() {
        logger.info("Cleaning up BLEClient resources")
        
        // Остановить сканирование
        if scanning {
            manager.stopScan()
        }
        
        // Отключить все устройства
        for device in discoveredPeripherals {
            if device.peripheral.state == .connected || device.peripheral.state == .connecting {
                manager.cancelPeripheralConnection(device.peripheral)
            }
        }
        
        // Отменить все таймауты
        scanTimeoutTask?.cancel()
        connectionTimeouts.values.forEach { $0.cancel() }
        connectionTimeouts.removeAll()
    }
}

// MARK: - Mock для тестирования

#if DEBUG
@MainActor
final class MockBLEClient: BLEClientProtocol {
    var discoveredPeripherals: [BLEDeviceModel] = []
    var scanning: Bool = false
    var bluetoothState: CBManagerState = .poweredOn
    var errorMessage: String?
    
    var scanCalled = false
    var connectCalled = false
    var disconnectCalled = false
    
    func triggerScan(timeout: TimeInterval = 30.0) {
        scanCalled = true
        scanning = true
    }
    
    func stopScan() {
        scanning = false
    }
    
    func connect(to model: BLEDeviceModel, timeout: TimeInterval = 10.0) {
        connectCalled = true
    }
    
    func disconnect(_ model: BLEDeviceModel) {
        disconnectCalled = true
    }
}
#endif

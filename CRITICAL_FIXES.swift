// CRITICAL_FIXES.swift
// Готовые к применению критические исправления
// Скопировать соответствующие части в оригинальные файлы

import Foundation
import CoreBluetooth
import os.log

// ============================================================================
// ИСПРАВЛЕНИЕ #1: BluetoothClient.swift - Добавить deinit и cleanup
// ============================================================================

@MainActor
final class BLEClient_FIXED: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published public var discoveredPeripherals: [BLEDeviceModel] = []
    @Published var scanning: Bool = false
    
    private var manager: CBCentralManager!
    private var peripheralCache: [UUID: BLEDeviceModel] = [:]  // ✅ Кэш для предотвращения дублирования
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var reconnectionAttempts: [UUID: Int] = [:]
    
    private let connectionTimeout: TimeInterval = 10.0
    private let maxReconnectionAttempts = 3
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "BLEClient")
    
    override required init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // ✅ КРИТИЧНО: Добавить cleanup
    deinit {
        logger.info("🧹 BLEClient deinit - cleaning up")
        stopScan()
        
        // Отключить все устройства
        discoveredPeripherals.forEach { model in
            if model.peripheral.state != .disconnected {
                manager.cancelPeripheralConnection(model.peripheral)
            }
        }
        
        // Отменить все таймауты
        connectionTimeouts.values.forEach { $0.cancel() }
        connectionTimeouts.removeAll()
        
        // Очистить делегата
        manager.delegate = nil
        
        logger.info("✅ BLEClient cleanup complete")
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            logger.info("📡 Bluetooth state: unknown")
        case .resetting:
            logger.info("📡 Bluetooth state: resetting")
        case .unsupported:
            logger.error("❌ Bluetooth not supported on this device")
        case .unauthorized:
            logger.error("❌ Bluetooth access not authorized")
        case .poweredOff:
            logger.warning("⚠️ Bluetooth powered off")
            stopScan()
        case .poweredOn:
            logger.info("✅ Bluetooth powered on")
            triggerScan()
        @unknown default:
            logger.warning("⚠️ Unknown Bluetooth state")
        }
    }
    
    func triggerScan() {
        discoveredPeripherals.removeAll()
        // ✅ Не очищаем кэш - переиспользуем модели
        manager.scanForPeripherals(
            withServices: [
                CBUUID(string: LYWSD02UUID.Service.Unknown1.rawValue),
                CBUUID(string: LYWSD02UUID.Service.Unknown2.rawValue)
            ],
            options: nil
        )
        scanning = true
        logger.info("🔍 Started scanning for devices")
    }
    
    func stopScan() {
        guard scanning else { return }
        manager.stopScan()
        scanning = false
        logger.info("🛑 Stopped scanning")
    }
    
    // ✅ УЛУЧШЕНО: С таймаутом
    func connect(to model: BLEDeviceModel) {
        guard model.peripheral.state != .connected else {
            logger.info("ℹ️ Already connected to \(model.name)")
            return
        }
        
        let peripheralID = model.peripheral.identifier
        logger.info("🔗 Connecting to \(model.name)...")
        
        manager.connect(model.peripheral, options: nil)
        
        // Установить таймаут
        connectionTimeouts[peripheralID]?.cancel()
        connectionTimeouts[peripheralID] = Task {
            try? await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            if model.peripheral.state != .connected {
                logger.error("❌ Connection timeout for \(model.name)")
                manager.cancelPeripheralConnection(model.peripheral)
            }
        }
    }
    
    func disconnect(_ model: BLEDeviceModel) {
        guard model.peripheral.state != .disconnected else {
            logger.info("ℹ️ Already disconnected from \(model.name)")
            return
        }
        
        logger.info("🔌 Disconnecting from \(model.name)")
        manager.cancelPeripheralConnection(model.peripheral)
    }
    
    // ✅ УЛУЧШЕНО: С кэшированием
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let peripheralID = peripheral.identifier
        
        // Переиспользовать модель из кэша или создать новую
        let model: BLEDeviceModel
        if let cached = peripheralCache[peripheralID] {
            model = cached
        } else {
            model = BLEDeviceModel(peripheral)
            peripheralCache[peripheralID] = model
            logger.info("📱 Discovered new device: \(peripheral.name ?? "Unknown") (\(peripheralID.uuidString))")
        }
        
        // Добавить в список если еще нет
        if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheralID }) {
            discoveredPeripherals.append(model)
        }
    }
    
    // ✅ НОВОЕ: Обработка успешного подключения
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peripheralID = peripheral.identifier
        
        // Отменить таймаут
        connectionTimeouts[peripheralID]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheralID)
        
        // Сбросить счетчик переподключений
        reconnectionAttempts.removeValue(forKey: peripheralID)
        
        logger.info("✅ Connected to \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil)
    }
    
    // ✅ НОВОЕ: Обработка отключения с auto-reconnect
    func centralManager(_ central: CBCentralManager, 
                       didDisconnectPeripheral peripheral: CBPeripheral, 
                       error: Error?) {
        let peripheralID = peripheral.identifier
        
        logger.warning("⚠️ Disconnected from \(peripheral.name ?? "Unknown")")
        
        if let error = error {
            logger.error("Disconnect error: \(error.localizedDescription)")
        }
        
        // Попытаться переподключиться
        let attempts = reconnectionAttempts[peripheralID, default: 0]
        
        guard attempts < maxReconnectionAttempts else {
            logger.error("❌ Max reconnection attempts reached for \(peripheral.name ?? "Unknown")")
            reconnectionAttempts.removeValue(forKey: peripheralID)
            return
        }
        
        reconnectionAttempts[peripheralID] = attempts + 1
        
        // Экспоненциальная задержка: 1s, 2s, 4s
        let delay = pow(2.0, Double(attempts))
        
        logger.info("🔄 Will reconnect to \(peripheral.name ?? "Unknown") in \(delay)s (attempt \(attempts + 1)/\(maxReconnectionAttempts))")
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Найти модель устройства
            if let model = peripheralCache[peripheralID] {
                connect(to: model)
            }
        }
    }
    
    // ✅ НОВОЕ: Обработка неудачного подключения
    func centralManager(_ central: CBCentralManager, 
                       didFailToConnect peripheral: CBPeripheral, 
                       error: Error?) {
        let peripheralID = peripheral.identifier
        
        connectionTimeouts[peripheralID]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheralID)
        
        logger.error("❌ Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")")
    }
}

// ============================================================================
// ИСПРАВЛЕНИЕ #2: BLEDeviceModel.swift - Добавить deinit и cleanup
// ============================================================================

@MainActor
final class BLEDeviceModel_FIXED: NSObject, ObservableObject, CBPeripheralDelegate {
    @Published private(set) var hasTimeSupport = false
    @Published private(set) var hasBatterySupport = false
    @Published private(set) var hasTemperatureSupport = false
    @Published private(set) var hasHumiditySupport = false
    
    @Published private(set) var batteryPercentage: Int? = nil
    @Published private(set) var currentTime: Date? = nil
    @Published private(set) var currentTemperature: Double? = nil
    @Published private(set) var currentHumidity: Int? = nil
    
    @Published private(set) var name: String
    
    private var _peripheral: CBPeripheral
    private var autoTimeSynced = false
    private var autoSyncTask: Task<Void, Never>?  // ✅ Хранить Task для отмены
    
    @Published private(set) var lastAutoTimeSyncAt: Date? = nil
    
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "Device")
    
    var identifier: String { peripheral.identifier.uuidString }
    var peripheral: CBPeripheral { self._peripheral }
    
    required init(_ peripheral: CBPeripheral) {
        self._peripheral = peripheral
        self.name = peripheral.name ?? "Unknown name"
        super.init()
        peripheral.delegate = self
    }
    
    // ✅ КРИТИЧНО: Добавить cleanup
    deinit {
        logger.info("🧹 BLEDeviceModel deinit for \(name)")
        
        // Отменить auto-sync task
        autoSyncTask?.cancel()
        
        // Отписаться от всех уведомлений
        if let service = _peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }) {
            service.characteristics?.forEach { char in
                if char.isNotifying {
                    _peripheral.setNotifyValue(false, for: char)
                }
            }
        }
        
        // Очистить делегата
        _peripheral.delegate = nil
        
        logger.info("✅ BLEDeviceModel cleanup complete")
    }
    
    // ... остальные методы ...
    
    // ✅ УЛУЧШЕНО: Безопасный auto-sync
    private func scheduleAutoTimeSync() {
        guard !autoTimeSynced else { return }
        autoTimeSynced = true
        
        logger.info("⏰ Scheduling auto time sync...")
        
        autoSyncTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Задержка 200ms
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            guard !Task.isCancelled else {
                self.logger.info("⚠️ Auto-sync cancelled")
                return
            }
            
            // Проверить состояние подключения
            guard self.peripheral.state == .connected else {
                self.logger.warning("⚠️ Auto-sync skipped: device disconnected")
                return
            }
            
            // Выполнить синхронизацию
            do {
                try self.syncTime(target: Date())
                self.lastAutoTimeSyncAt = Date()
                self.logger.info("✅ Auto time sync completed")
            } catch {
                self.logger.error("❌ Auto-sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // ✅ УЛУЧШЕНО: С валидацией и error handling
    func syncTime(target: Date) throws {
        guard hasTimeSupport else {
            throw BLEError.characteristicNotFound
        }
        
        // Валидация времени
        let now = Date()
        let maxFuture = now.addingTimeInterval(365 * 24 * 3600) // +1 год
        let minPast = now.addingTimeInterval(-10 * 365 * 24 * 3600) // -10 лет
        
        guard (minPast...maxFuture).contains(target) else {
            throw BLEError.invalidData(reason: "Time out of valid range")
        }
        
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }),
              let timeCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.cbuuid }) else {
            throw BLEError.characteristicNotFound
        }
        
        let timezone = TimeZone.current
        let offsetHours = timezone.secondsFromGMT() / 3600
        
        guard (-12...14).contains(offsetHours) else {
            throw BLEError.invalidData(reason: "Invalid timezone offset: \(offsetHours)")
        }
        
        let time = Time(timestamp: Int(target.timeIntervalSince1970), timezoneOffset: offsetHours)
        peripheral.writeValue(time.data(), for: timeCharacteristic, type: .withResponse)
        
        logger.info("⏰ Writing time to device: \(target)")
    }
}

// ============================================================================
// ИСПРАВЛЕНИЕ #3: Time.swift - Убрать зависимость от pack()
// ============================================================================

struct Time_FIXED {
    var timestamp: Int
    var timezoneOffset: Int
    
    init(timestamp: Int, timezoneOffset: Int) {
        self.timestamp = timestamp
        self.timezoneOffset = timezoneOffset
    }
    
    init(date: Date = Date(), timezone: TimeZone = .current) {
        self.timestamp = Int(date.timeIntervalSince1970)
        self.timezoneOffset = timezone.secondsFromGMT() / 3600
    }
    
    // ✅ ИСПРАВЛЕНО: Без зависимости от pack()
    func data() -> Data {
        var data = Data()
        
        // 4 bytes для timestamp (little-endian Int32)
        withUnsafeBytes(of: Int32(timestamp).littleEndian) {
            data.append(contentsOf: $0)
        }
        
        // 1 byte для timezoneOffset
        withUnsafeBytes(of: Int8(timezoneOffset).littleEndian) {
            data.append(contentsOf: $0)
        }
        
        return data
    }
    
    // ✅ НОВОЕ: Парсинг из Data
    static func from(data: Data) -> Time? {
        guard data.count >= 5 else { return nil }
        
        let timestamp = data.withUnsafeBytes { $0.load(as: Int32.self) }
        let offset = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int8.self) }
        
        return Time(timestamp: Int(timestamp), timezoneOffset: Int(offset))
    }
}

// ============================================================================
// ИСПРАВЛЕНИЕ #4: BinUtils.swift - Безопасная работа с памятью
// ============================================================================

enum BinUtilsError_EXTENDED: Error {
    case formatDoesMatchDataLength(format:String, dataSize:Int)
    case unsupportedFormat(character:Character)
    case insufficientBytes(needed: Int, available: Int)  // ✅ НОВОЕ
    case invalidData(bytes: [UInt8], type: String)      // ✅ НОВОЕ
    case objectQueueEmpty(format: String)                // ✅ НОВОЕ
}

// ✅ ИСПРАВЛЕНО: С error handling вместо force unwrap
func readIntegerType_SAFE<T:DataConvertible>(_ type:T.Type, bytes:[UInt8], loc:inout Int) throws -> T {
    let size = MemoryLayout<T>.size
    
    // ✅ Проверка границ
    guard loc + size <= bytes.count else {
        throw BinUtilsError_EXTENDED.insufficientBytes(needed: size, available: bytes.count - loc)
    }
    
    let sub = Array(bytes[loc..<(loc+size)])
    loc += size
    
    // ✅ Проверка конвертации
    guard let value = T(bytes: sub) else {
        throw BinUtilsError_EXTENDED.invalidData(bytes: sub, type: String(describing: T.self))
    }
    
    return value
}

// ✅ ИСПРАВЛЕНО: pack() с валидацией
public func pack_SAFE(_ format:String, _ objects:[Any], _ stringEncoding:String.Encoding=String.Encoding.windowsCP1252) throws -> Data {
    
    var objectsQueue = objects
    var mutableFormat = format
    var mutableData = Data()
    
    guard let firstCharacter = mutableFormat.first else {
        throw BinUtilsError_EXTENDED.unsupportedFormat(character: " ")
    }
    
    mutableFormat.removeFirst()
    
    let isBigEndian: Bool
    switch firstCharacter {
    case "<", "=":
        isBigEndian = false
    case ">", "!":
        isBigEndian = true
    default:
        throw BinUtilsError_EXTENDED.unsupportedFormat(character: firstCharacter)
    }
    
    var n = 0
    
    while !mutableFormat.isEmpty {
        let c = mutableFormat.removeFirst()
        
        if let i = Int(String(c)), 0...9 ~= i {
            if n > 0 { n *= 10 }
            n += i
            continue
        }
        
        // ... остальная логика ...
        
        for _ in 0..<max(n,1) {
            var bytes : [UInt8] = []
            
            if c != "x" {
                // ✅ Проверка наличия объектов
                guard !objectsQueue.isEmpty else {
                    throw BinUtilsError_EXTENDED.objectQueueEmpty(format: format)
                }
                let o = objectsQueue.removeFirst()
                
                // ... обработка объекта ...
            }
        }
        
        n = 0
    }
    
    return mutableData
}

// ============================================================================
// ИСПРАВЛЕНИЕ #5: Единая система ошибок
// ============================================================================

enum BLEError: LocalizedError {
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case deviceNotFound
    case connectionTimeout
    case connectionFailed(Error)
    case characteristicNotFound
    case invalidData(reason: String)
    case writeFailure(Error)
    case readFailure(Error)
    case scanTimeout
    
    var errorDescription: String? {
        switch self {
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Please enable it in Settings."
        case .bluetoothUnauthorized:
            return "Bluetooth access is not authorized. Please grant permission in Settings."
        case .bluetoothUnsupported:
            return "This device doesn't support Bluetooth Low Energy."
        case .deviceNotFound:
            return "Device not found. Make sure it's turned on and nearby."
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .connectionFailed(let error):
            return "Failed to connect: \(error.localizedDescription)"
        case .characteristicNotFound:
            return "Device doesn't support required features."
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .writeFailure(let error):
            return "Failed to write data: \(error.localizedDescription)"
        case .readFailure(let error):
            return "Failed to read data: \(error.localizedDescription)"
        case .scanTimeout:
            return "Scan timeout. No devices found."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .bluetoothPoweredOff, .bluetoothUnauthorized:
            return "Open Settings and enable Bluetooth."
        case .deviceNotFound:
            return "Make sure the device is turned on, has battery, and is within range."
        case .connectionTimeout, .connectionFailed:
            return "Try moving closer to the device and retry."
        case .characteristicNotFound:
            return "This device may not be compatible with this app."
        default:
            return "Please try again or restart the app."
        }
    }
}

// ============================================================================
// ИСПРАВЛЕНИЕ #6: Constants вместо magic numbers
// ============================================================================

enum LYWSD02Constants {
    // Timing
    static let autoSyncDelay: TimeInterval = 0.2
    static let connectionTimeout: TimeInterval = 10.0
    static let scanTimeout: TimeInterval = 30.0
    static let reconnectionDelays: [TimeInterval] = [1.0, 2.0, 4.0]
    
    // Data sizes
    static let timeDataSize = 5  // 4 bytes timestamp + 1 byte offset
    static let sensorDataSize = 3  // 2 bytes temp + 1 byte humidity
    static let batteryDataSize = 1
    static let historyRecordSize = 14
    static let numRecordsDataSize = 8
    
    // Scaling factors
    static let temperatureScale = 100.0
    
    // Validation ranges
    enum Ranges {
        static let temperature: ClosedRange<Double> = -40...80
        static let humidity: ClosedRange<Int> = 0...100
        static let battery: ClosedRange<Int> = 0...100
        static let timezoneOffset: ClosedRange<Int> = -12...14
    }
    
    // Limits
    static let maxHistoryRecords = 500
    static let maxReconnectionAttempts = 3
    static let historyPageSize = 100
}

// Использование:
// try? await Task.sleep(nanoseconds: UInt64(LYWSD02Constants.autoSyncDelay * 1_000_000_000))
// guard data.count == LYWSD02Constants.sensorDataSize else { return }
// let temperature = Double(tempRaw) / LYWSD02Constants.temperatureScale
// guard LYWSD02Constants.Ranges.temperature.contains(temperature) else { return }

// ============================================================================
// КОНЕЦ КРИТИЧЕСКИХ ИСПРАВЛЕНИЙ
// ============================================================================

/*
 ИНСТРУКЦИИ ПО ПРИМЕНЕНИЮ:
 
 1. BluetoothClient.swift:
    - Скопировать методы из BLEClient_FIXED
    - Добавить все новые свойства (peripheralCache, connectionTimeouts, etc.)
    - Добавить deinit
    - Добавить новые методы делегата
 
 2. BLEDeviceModel.swift:
    - Добавить autoSyncTask свойство
    - Добавить deinit
    - Заменить scheduleAutoTimeSync на улучшенную версию
    - Обновить syncTime с валидацией
 
 3. Time.swift:
    - Полностью заменить на Time_FIXED
 
 4. BinUtils.swift:
    - Добавить новые ошибки в BinUtilsError
    - Заменить readIntegerType на readIntegerType_SAFE
    - Обновить pack и unpack с error handling
 
 5. Создать новый файл BLEError.swift:
    - Скопировать enum BLEError
 
 6. Создать новый файл LYWSD02Constants.swift:
    - Скопировать enum LYWSD02Constants
 
 ПРИОРИТЕТ: Применить в порядке 1 → 2 → 3 → 5 → 6 → 4
 */

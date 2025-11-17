# BluetoothClient.swift - Полный анализ и рекомендации по улучшению

**Дата:** 17 ноября 2025  
**Файл:** `/Shared/BluetoothClient.swift`  
**Статус:** ✅ Код в целом хорошего качества, но есть возможности для улучшения

---

## 📊 Общая оценка

| Критерий | Оценка | Комментарий |
|----------|--------|-------------|
| Безопасность потоков | 🟢 Отлично | Правильное использование `@MainActor` и `nonisolated` |
| Обработка ошибок | 🟡 Хорошо | Есть базовая обработка, но можно улучшить |
| Производительность | 🟢 Отлично | Нет явных проблем |
| Память | 🟡 Хорошо | Возможна утечка при повторном сканировании |
| Тестируемость | 🔴 Требует улучшения | Жёсткая зависимость от CBCentralManager |
| Документация | 🔴 Отсутствует | Нет комментариев к публичным методам |

---

## 🎯 Критические улучшения (High Priority)

### 1. **Управление жизненным циклом устройств**

**Проблема:** При повторных сканированиях создаются новые экземпляры `BLEDeviceModel` для тех же периферийных устройств, что может привести к:
- Потере состояния устройства (history, autoTimeSynced)
- Утечкам памяти из-за накопления делегатов
- Несогласованности данных

**Решение:**
```swift
// Хранить словарь устройств по UUID
private var deviceCache: [UUID: BLEDeviceModel] = [:]

func triggerScan() {
    guard manager.state == .poweredOn else {
        logger.warning("Cannot scan: Bluetooth not powered on")
        return
    }
    
    // Не очищать полностью, а пометить устройства как неактивные
    deviceCache.values.forEach { $0.markAsStale() }
    
    manager.scanForPeripherals(
        withServices: LYWSD02UUID.serviceCBUUIDs,
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    scanning = true
    logger.info("Started scanning for peripherals")
}

nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any], rssi RSSI: NSNumber)
{
    Task { @MainActor in
        logger.debug("Discovered peripheral: \(peripheral.identifier.uuidString)")
        
        let device: BLEDeviceModel
        if let existingDevice = deviceCache[peripheral.identifier] {
            device = existingDevice
            device.markAsActive()
            logger.info("Reusing existing device model: \(peripheral.name ?? "Unknown")")
        } else {
            device = BLEDeviceModel(peripheral)
            deviceCache[peripheral.identifier] = device
            logger.info("Created new device model: \(peripheral.name ?? "Unknown")")
        }
        
        if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(device)
        }
    }
}
```

---

### 2. **Таймаут подключения**

**Проблема:** Нет таймаута для операций подключения. Если устройство не отвечает, подключение может "висеть" бесконечно.

**Решение:**
```swift
private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]

func connect(to model: BLEDeviceModel, timeout: TimeInterval = 10.0) {
    if model.peripheral.state == .connected {
        logger.info("Already connected to \(model.name)")
        return
    }
    
    logger.info("Connecting to \(model.name)")
    manager.connect(model.peripheral, options: nil)
    
    // Запустить таймаут
    let timeoutTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        if model.peripheral.state != .connected {
            logger.error("Connection timeout for \(model.name)")
            manager.cancelPeripheralConnection(model.peripheral)
            errorMessage = "Connection timeout: \(model.name)"
        }
    }
    
    connectionTimeouts[model.peripheral.identifier] = timeoutTask
}

nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task { @MainActor in
        // Отменить таймаут
        connectionTimeouts[peripheral.identifier]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheral.identifier)
        
        logger.info("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil)
    }
}

nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    Task { @MainActor in
        // Отменить таймаут
        connectionTimeouts[peripheral.identifier]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheral.identifier)
        
        if let error = error {
            logger.error("Failed to connect to peripheral: \(error.localizedDescription)")
            errorMessage = "Failed to connect: \(error.localizedDescription)"
        }
    }
}
```

---

### 3. **Автоматическое переподключение**

**Проблема:** При потере соединения нет автоматической попытки переподключиться.

**Решение:**
```swift
@Published var autoReconnectEnabled: Bool = true
private var reconnectionAttempts: [UUID: Int] = [:]
private let maxReconnectionAttempts = 3

nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    Task { @MainActor in
        if let error = error {
            logger.error("Disconnected with error: \(error.localizedDescription)")
            
            // Попытка автопереподключения
            if autoReconnectEnabled {
                let attempts = reconnectionAttempts[peripheral.identifier] ?? 0
                if attempts < maxReconnectionAttempts {
                    reconnectionAttempts[peripheral.identifier] = attempts + 1
                    
                    logger.info("Auto-reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts)")
                    
                    // Экспоненциальная задержка: 1s, 2s, 4s
                    let delay = TimeInterval(1 << attempts)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    if let device = deviceCache[peripheral.identifier] {
                        connect(to: device)
                    }
                } else {
                    errorMessage = "Failed to reconnect after \(maxReconnectionAttempts) attempts"
                    reconnectionAttempts.removeValue(forKey: peripheral.identifier)
                }
            }
        } else {
            logger.info("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
            reconnectionAttempts.removeValue(forKey: peripheral.identifier)
        }
    }
}
```

---

### 4. **Очистка ресурсов при deinit**

**Проблема:** При уничтожении `BLEClient` нет очистки подключений и таймаутов.

**Решение:**
```swift
deinit {
    // Отключить все устройства
    for device in discoveredPeripherals {
        if device.peripheral.state == .connected || device.peripheral.state == .connecting {
            manager.cancelPeripheralConnection(device.peripheral)
        }
    }
    
    // Остановить сканирование
    if scanning {
        manager.stopScan()
    }
    
    // Отменить все таймауты
    connectionTimeouts.values.forEach { $0.cancel() }
}
```

---

## 🔧 Важные улучшения (Medium Priority)

### 5. **Protocol-Oriented Design для тестируемости**

**Проблема:** Жёсткая зависимость от `CBCentralManager` делает тестирование невозможным без реального Bluetooth.

**Решение:**
```swift
// Создать протокол для абстракции
protocol BluetoothManager {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

// Обёртка над CBCentralManager
class CoreBluetoothManager: NSObject, BluetoothManager, CBCentralManagerDelegate {
    private let manager: CBCentralManager
    weak var delegate: BLEClient?
    
    var state: CBManagerState {
        manager.state
    }
    
    init(delegate: BLEClient?) {
        self.delegate = delegate
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) {
        manager.scanForPeripherals(withServices: withServices, options: options)
    }
    
    func stopScan() {
        manager.stopScan()
    }
    
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        manager.connect(peripheral, options: options)
    }
    
    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        manager.cancelPeripheralConnection(peripheral)
    }
    
    // Делегировать вызовы обратно к BLEClient
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.centralManagerDidUpdateState(central)
    }
    
    // ... остальные методы делегата
}

// Модифицировать BLEClient
final class BLEClient: NSObject, ObservableObject {
    private var bluetoothManager: BluetoothManager
    
    init(bluetoothManager: BluetoothManager? = nil) {
        self.bluetoothManager = bluetoothManager ?? CoreBluetoothManager(delegate: nil)
        super.init()
        if let coreManager = self.bluetoothManager as? CoreBluetoothManager {
            coreManager.delegate = self
        }
    }
}

// Теперь можно создать Mock для тестирования
class MockBluetoothManager: BluetoothManager {
    var state: CBManagerState = .poweredOn
    var scanCalled = false
    
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) {
        scanCalled = true
    }
    
    // ... реализация остальных методов
}
```

---

### 6. **Мониторинг состояния сканирования с таймаутом**

**Проблема:** Сканирование может работать бесконечно, расходуя батарею.

**Решение:**
```swift
private var scanTimeoutTask: Task<Void, Never>?
private let defaultScanTimeout: TimeInterval = 30.0

func triggerScan(timeout: TimeInterval = 30.0) {
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
    
    // Автоматическая остановка сканирования
    scanTimeoutTask?.cancel()
    scanTimeoutTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        if scanning {
            stopScan()
            logger.info("Scan stopped automatically after \(timeout)s timeout")
            
            if discoveredPeripherals.isEmpty {
                errorMessage = "No devices found. Make sure the device is nearby and powered on."
            }
        }
    }
}

func stopScan() {
    scanTimeoutTask?.cancel()
    scanTimeoutTask = nil
    manager.stopScan()
    scanning = false
    logger.info("Stopped scanning for peripherals")
}
```

---

### 7. **Улучшенная обработка состояния Bluetooth**

**Проблема:** При изменении состояния Bluetooth из `.poweredOn` в `.poweredOff` теряются подключения.

**Решение:**
```swift
nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
    Task { @MainActor in
        let oldState = self.bluetoothState
        self.bluetoothState = central.state
        
        // Обработать переход состояний
        handleStateTransition(from: oldState, to: central.state)
    }
    
    // ... существующий код ...
}

@MainActor
private func handleStateTransition(from oldState: CBManagerState, to newState: CBManagerState) {
    switch (oldState, newState) {
    case (.poweredOn, .poweredOff):
        logger.warning("Bluetooth was turned off - disconnecting all devices")
        // Очистить состояние подключённых устройств
        discoveredPeripherals.forEach { device in
            if device.peripheral.state == .connected {
                // Устройство будет отключено автоматически, но мы обновляем UI
                device.resetConnectionState()
            }
        }
        
    case (.poweredOff, .poweredOn):
        logger.info("Bluetooth was turned on - ready to scan")
        // Опционально: автоматически начать сканирование или переподключение
        
    case (_, .unauthorized):
        logger.error("Bluetooth authorization was revoked")
        
    default:
        break
    }
}
```

---

### 8. **Кэширование RSSI значений**

**Проблема:** RSSI (сила сигнала) не сохраняется и может быть полезна для UI (показать расстояние до устройства).

**Решение:**
```swift
// В BLEDeviceModel добавить:
@Published private(set) var rssi: Int?

// В BLEClient:
nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any], rssi RSSI: NSNumber)
{
    Task { @MainActor in
        logger.debug("Discovered peripheral: \(peripheral.identifier.uuidString) RSSI: \(RSSI)")
        
        if let existingDevice = discoveredPeripherals.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            existingDevice.updateRSSI(RSSI.intValue)
        } else {
            let deviceModel = BLEDeviceModel(peripheral)
            deviceModel.updateRSSI(RSSI.intValue)
            self.discoveredPeripherals.append(deviceModel)
            logger.info("Added new device: \(peripheral.name ?? "Unknown")")
        }
    }
}
```

---

## 💡 Рекомендуемые улучшения (Low Priority)

### 9. **Structured Concurrency для async/await**

**Улучшение:** Использовать современные паттерны Swift Concurrency.

```swift
func connect(to model: BLEDeviceModel) async throws {
    guard manager.state == .poweredOn else {
        throw BLEError.bluetoothNotReady
    }
    
    guard model.peripheral.state != .connected else {
        logger.info("Already connected to \(model.name)")
        return
    }
    
    return try await withCheckedThrowingContinuation { continuation in
        pendingConnections[model.peripheral.identifier] = continuation
        manager.connect(model.peripheral, options: nil)
    }
}

// В делегате:
nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task { @MainActor in
        if let continuation = pendingConnections.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: ())
        }
        logger.info("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices(nil)
    }
}
```

---

### 10. **Добавить статистику и метрики**

**Улучшение:** Собирать метрики для отладки и мониторинга.

```swift
struct BLEStatistics {
    var totalScans: Int = 0
    var successfulConnections: Int = 0
    var failedConnections: Int = 0
    var disconnections: Int = 0
    var averageConnectionTime: TimeInterval = 0
}

@Published private(set) var statistics = BLEStatistics()
```

---

### 11. **Локализация сообщений об ошибках**

**Улучшение:** Вынести строки в Localizable.strings для поддержки многоязычности.

```swift
// Создать enum для локализованных сообщений
enum BLEErrorMessage: String {
    case bluetoothUnsupported = "bluetooth_unsupported"
    case bluetoothUnauthorized = "bluetooth_unauthorized"
    case bluetoothPoweredOff = "bluetooth_powered_off"
    case connectionTimeout = "connection_timeout"
    
    var localized: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

// Использовать:
errorMessage = BLEErrorMessage.bluetoothPoweredOff.localized
```

---

### 12. **Background Mode Support**

**Улучшение:** Поддержка работы в фоновом режиме (для iOS).

```swift
// В Info.plist добавить:
// UIBackgroundModes: bluetooth-central

// В BLEClient добавить:
private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?

func enterBackground() {
    backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
        self?.endBackgroundTask()
    }
}

func enterForeground() {
    endBackgroundTask()
}

private func endBackgroundTask() {
    if let identifier = backgroundTaskIdentifier {
        UIApplication.shared.endBackgroundTask(identifier)
        backgroundTaskIdentifier = nil
    }
}
```

---

## 📝 Документация

### 13. **Добавить DocC комментарии**

```swift
/// Manages Bluetooth Low Energy device discovery and connection.
///
/// `BLEClient` handles scanning for BLE peripherals, managing connections,
/// and maintaining a list of discovered devices. It provides reactive updates
/// through Combine publishers.
///
/// ## Topics
///
/// ### Discovery
/// - ``triggerScan()``
/// - ``stopScan()``
/// - ``discoveredPeripherals``
///
/// ### Connection Management
/// - ``connect(to:)``
/// - ``disconnect(_:)``
///
/// ### State
/// - ``scanning``
/// - ``bluetoothState``
/// - ``errorMessage``
@MainActor
final class BLEClient: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    /// List of discovered BLE peripherals.
    ///
    /// This array is automatically updated as devices are discovered during scanning.
    /// Each device is represented by a ``BLEDeviceModel`` instance.
    @Published public var discoveredPeripherals: [BLEDeviceModel] = []
    
    /// Indicates whether a scan is currently in progress.
    @Published var scanning: Bool = false
    
    /// Current state of the Bluetooth adapter.
    ///
    /// Use this property to determine if Bluetooth is available and powered on.
    /// Common states include `.poweredOn`, `.poweredOff`, `.unauthorized`.
    @Published var bluetoothState: CBManagerState = .unknown
    
    /// User-facing error message, if any.
    ///
    /// Set to `nil` when there are no errors. Use this to display alerts to the user.
    @Published var errorMessage: String?
    
    // ... rest of implementation
}
```

---

## 🧪 Тестирование

### 14. **Unit Tests**

```swift
import XCTest
@testable import LYWSD02_Clock_Sync

final class BLEClientTests: XCTestCase {
    var sut: BLEClient!
    var mockManager: MockBluetoothManager!
    
    override func setUp() {
        super.setUp()
        mockManager = MockBluetoothManager()
        sut = BLEClient(bluetoothManager: mockManager)
    }
    
    override func tearDown() {
        sut = nil
        mockManager = nil
        super.tearDown()
    }
    
    @MainActor
    func testTriggerScan_whenBluetoothPoweredOn_startsScan() {
        // Given
        mockManager.state = .poweredOn
        
        // When
        sut.triggerScan()
        
        // Then
        XCTAssertTrue(sut.scanning)
        XCTAssertTrue(mockManager.scanCalled)
    }
    
    @MainActor
    func testTriggerScan_whenBluetoothPoweredOff_doesNotStartScan() {
        // Given
        mockManager.state = .poweredOff
        
        // When
        sut.triggerScan()
        
        // Then
        XCTAssertFalse(sut.scanning)
        XCTAssertFalse(mockManager.scanCalled)
    }
}
```

---

## 🔒 Безопасность

### 15. **Валидация Peripheral**

**Улучшение:** Проверять, что обнаруженное устройство действительно LYWSD02.

```swift
nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                    advertisementData: [String: Any], rssi RSSI: NSNumber)
{
    Task { @MainActor in
        // Валидация по имени или UUID сервиса
        guard validateDevice(peripheral, advertisementData: advertisementData) else {
            logger.warning("Discovered device failed validation: \(peripheral.identifier)")
            return
        }
        
        // ... остальной код
    }
}

private func validateDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
    // Проверить наличие нужных сервисов в рекламных данных
    if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
        let hasRequiredService = serviceUUIDs.contains { uuid in
            LYWSD02UUID.serviceCBUUIDs.contains(uuid)
        }
        if !hasRequiredService {
            return false
        }
    }
    
    // Опционально: проверить по имени устройства
    if let name = peripheral.name {
        return name.contains("LYWSD02") || name.contains("MJ_HT_V1")
    }
    
    return true
}
```

---

## 📊 Производительность

### 16. **Lazy Initialization периферийных устройств**

```swift
// Вместо создания BLEDeviceModel сразу при обнаружении,
// создавать только при подключении

struct DiscoveredDevice {
    let peripheral: CBPeripheral
    let rssi: Int
    let advertisementData: [String: Any]
    var lastSeen: Date
}

@Published private var discoveredDevices: [UUID: DiscoveredDevice] = [:]
@Published private var activeDevices: [UUID: BLEDeviceModel] = [:]

// Создавать BLEDeviceModel только при connect()
```

---

## ✅ Checklist для внедрения

### Немедленно (Critical):
- [ ] Добавить управление жизненным циклом устройств (кэш)
- [ ] Реализовать таймаут подключения
- [ ] Добавить deinit с очисткой ресурсов
- [ ] Реализовать автопереподключение

### В ближайшее время (High):
- [ ] Добавить protocol для тестируемости
- [ ] Реализовать таймаут сканирования
- [ ] Улучшить обработку переходов состояний Bluetooth
- [ ] Добавить кэширование RSSI

### По возможности (Medium):
- [ ] Перейти на async/await API
- [ ] Добавить метрики и статистику
- [ ] Локализовать сообщения об ошибках
- [ ] Добавить DocC документацию

### Опционально (Low):
- [ ] Написать Unit Tests
- [ ] Реализовать Background Mode
- [ ] Добавить валидацию устройств
- [ ] Оптимизировать создание объектов

---

## 🎓 Выводы

**Сильные стороны текущей реализации:**
- ✅ Правильное использование `@MainActor` для безопасности потоков
- ✅ Хорошее логирование через `os.Logger`
- ✅ Reactive UI через `@Published` свойства
- ✅ Обработка основных состояний Bluetooth

**Основные области для улучшения:**
- 🔴 Управление жизненным циклом объектов
- 🔴 Обработка edge cases (таймауты, переподключения)
- 🔴 Тестируемость кода
- 🟡 Документация

**Рекомендуемый план действий:**
1. Внедрить кэш устройств (1-2 часа)
2. Добавить таймауты (30 мин)
3. Реализовать автопереподключение (1 час)
4. Создать protocol для тестирования (2 часа)
5. Написать базовые тесты (2-3 часа)

**Общая оценка:** 7.5/10 - хороший промышленный код с потенциалом для улучшения до 9/10.


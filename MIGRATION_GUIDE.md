# Migration Guide - Пошаговое руководство по применению улучшений

## 📋 Подготовка (5 минут)

### 1. Создайте резервную копию
```bash
cd /Users/Aleh_Chachotka/Documents/GitHub/LYWSD02-Clock-Sync

# Создать ветку для улучшений
git checkout -b bluetooth-improvements

# Сохранить текущую версию
cp Shared/BluetoothClient.swift Shared/BluetoothClient.swift.backup
```

### 2. Проверьте текущее состояние
```bash
# Убедитесь, что проект компилируется
xcodebuild -project "LYWSD02 Clock Sync.xcodeproj" -scheme "LYWSD02 Clock Sync (macOS)" clean build

# Запустите текущую версию и протестируйте
open "LYWSD02 Clock Sync.xcodeproj"
```

---

## 🎯 Вариант А: Полная миграция (рекомендуется)

### Шаг 1: Замена файла (2 минуты)

```bash
# Заменить текущий BluetoothClient.swift улучшенной версией
cp BluetoothClient_Improvements.swift Shared/BluetoothClient.swift
```

### Шаг 2: Проверка компиляции (1 минута)

```bash
# Открыть проект в Xcode
open "LYWSD02 Clock Sync.xcodeproj"

# Скомпилировать проект (⌘B)
```

**Возможные ошибки и решения:**

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `Cannot find type 'BLEError'` | Enum не импортирован | Уже включен в улучшенный файл ✅ |
| `Ambiguous use of 'triggerScan'` | Конфликт сигнатур | Обновите вызовы: `triggerScan(timeout: 30)` |
| Build успешен | Всё хорошо! | Перейдите к тестированию ✅ |

### Шаг 3: Тестирование (10 минут)

#### Test 1: Базовое сканирование
```swift
// В ContentView.onAppear уже есть:
bleClient.triggerScan()

// ✅ Ожидаемый результат:
// - Сканирование запускается
// - Через 30 секунд автоматически останавливается
// - Если устройств нет, показывается сообщение об ошибке
```

**Что проверить:**
- [ ] Сканирование запускается
- [ ] Устройства появляются в списке
- [ ] Сканирование останавливается через 30с
- [ ] При повторном сканировании устройства не дублируются

#### Test 2: Подключение с таймаутом
```swift
// В DeviceView при подключении
bleClient.connect(to: device)

// ✅ Ожидаемый результат:
// - Подключение происходит < 10 секунд
// - При успехе таймаут отменяется
// - При провале показывается ошибка через 10с
```

**Что проверить:**
- [ ] Успешное подключение < 10с
- [ ] При выключенном устройстве таймаут срабатывает
- [ ] Сообщение об ошибке отображается

#### Test 3: Автопереподключение
```swift
// 1. Подключитесь к устройству
// 2. Выключите устройство (или отойдите далеко)
// 3. Включите устройство обратно

// ✅ Ожидаемый результат:
// - При потере соединения показывается ошибка
// - Автоматически 3 попытки переподключения с задержками 1s, 2s, 4s
// - При успехе подключается обратно
```

**Что проверить:**
- [ ] Обнаруживается потеря соединения
- [ ] Видны попытки переподключения в логах
- [ ] Успешное переподключение работает
- [ ] После 3 неудачных попыток показывается финальная ошибка

#### Test 4: Сохранение состояния
```swift
// 1. Подключитесь к устройству
// 2. Синхронизируйте время
// 3. Просмотрите историю
// 4. Отключитесь
// 5. Запустите новое сканирование
// 6. Найдите то же устройство

// ✅ Ожидаемый результат:
// - При повторном обнаружении используется тот же объект BLEDeviceModel
// - Флаг autoTimeSynced остаётся true (время не синхронизируется повторно)
// - История сохраняется
```

**Что проверить:**
- [ ] Устройство не синхронизирует время повторно при новом сканировании
- [ ] История не теряется между сканированиями

### Шаг 4: Просмотр логов (5 минут)

```bash
# Открыть Console.app
open -a Console

# Фильтр по subsystem:
# com.lywsd02.clocksync

# Фильтр по категории:
# BLE
```

**Что искать в логах:**

```
✅ Положительные индикаторы:
[INFO] Started scanning with 30.0s timeout
[DEBUG] Reusing cached device model for LYWSD02
[INFO] ✅ Connected to peripheral: LYWSD02
[INFO] 🔄 Auto-reconnection attempt 1/3 in 1.0s

❌ Проблемы:
[ERROR] ❌ Failed to connect
[ERROR] Connection timeout for Device
[WARNING] Maximum reconnection attempts reached
```

---

## 🔧 Вариант Б: Постепенная миграция

Если вы хотите применять улучшения по частям:

### Улучшение 1: Device Cache (10 минут)

```swift
// Добавить в BLEClient:
private var deviceCache: [UUID: BLEDeviceModel] = [:]

// Изменить в didDiscover:
let device: BLEDeviceModel
if let cachedDevice = deviceCache[peripheral.identifier] {
    device = cachedDevice
    logger.debug("Reusing cached device")
} else {
    device = BLEDeviceModel(peripheral)
    deviceCache[peripheral.identifier] = device
    logger.info("Created new device")
}

if !self.discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
    self.discoveredPeripherals.append(device)
}
```

✅ **Скомпилировать и протестировать**

### Улучшение 2: Connection Timeout (15 минут)

```swift
// Добавить в BLEClient:
private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]

// Изменить метод connect:
func connect(to model: BLEDeviceModel, timeout: TimeInterval = 10.0) {
    // ... существующие проверки ...
    
    manager.connect(model.peripheral, options: nil)
    
    let peripheralID = model.peripheral.identifier
    connectionTimeouts[peripheralID] = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        if model.peripheral.state != .connected {
            logger.error("Connection timeout")
            manager.cancelPeripheralConnection(model.peripheral)
            self.errorMessage = "Connection timeout: \(model.name)"
        }
    }
}

// В didConnect добавить:
connectionTimeouts[peripheral.identifier]?.cancel()
connectionTimeouts.removeValue(forKey: peripheral.identifier)

// В didFailToConnect добавить:
connectionTimeouts[peripheral.identifier]?.cancel()
connectionTimeouts.removeValue(forKey: peripheral.identifier)
```

✅ **Скомпилировать и протестировать**

### Улучшение 3: Scan Timeout (10 минут)

```swift
// Добавить в BLEClient:
private var scanTimeoutTask: Task<Void, Never>?

// Изменить triggerScan:
func triggerScan(timeout: TimeInterval = 30.0) {
    // ... существующий код до manager.scanForPeripherals ...
    
    scanTimeoutTask?.cancel()
    scanTimeoutTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        if self.scanning {
            self.stopScan()
            logger.info("Scan stopped after timeout")
            
            if self.discoveredPeripherals.isEmpty {
                self.errorMessage = "No devices found"
            }
        }
    }
}

// Изменить stopScan:
func stopScan() {
    scanTimeoutTask?.cancel()
    scanTimeoutTask = nil
    manager.stopScan()
    scanning = false
}
```

✅ **Скомпилировать и протестировать**

### Улучшение 4: Auto-Reconnection (20 минут)

```swift
// Добавить в BLEClient:
@Published var autoReconnectEnabled: Bool = true
private var reconnectionAttempts: [UUID: Int] = [:]
private let maxReconnectionAttempts = 3

// Добавить метод:
private func attemptReconnection(to peripheral: CBPeripheral) async {
    let attempts = reconnectionAttempts[peripheral.identifier] ?? 0
    
    guard attempts < maxReconnectionAttempts else {
        logger.error("Max reconnection attempts reached")
        errorMessage = "Failed to reconnect after \(maxReconnectionAttempts) attempts"
        reconnectionAttempts.removeValue(forKey: peripheral.identifier)
        return
    }
    
    reconnectionAttempts[peripheral.identifier] = attempts + 1
    let delay = TimeInterval(1 << attempts) // 1s, 2s, 4s
    
    logger.info("🔄 Auto-reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts) in \(delay)s")
    
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    
    if let device = deviceCache[peripheral.identifier] {
        connect(to: device)
    }
}

// Изменить didDisconnectPeripheral:
nonisolated func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
) {
    Task { @MainActor in
        connectionTimeouts[peripheral.identifier]?.cancel()
        connectionTimeouts.removeValue(forKey: peripheral.identifier)
        
        if let error = error {
            logger.error("Disconnected with error: \(error.localizedDescription)")
            
            if self.autoReconnectEnabled {
                await self.attemptReconnection(to: peripheral)
            }
        } else {
            logger.info("Disconnected normally")
            reconnectionAttempts.removeValue(forKey: peripheral.identifier)
        }
    }
}

// В didConnect добавить:
reconnectionAttempts.removeValue(forKey: peripheral.identifier)
```

✅ **Скомпилировать и протестировать**

### Улучшение 5: Cleanup (5 минут)

```swift
// Добавить deinit в BLEClient:
deinit {
    logger.info("Cleaning up BLEClient")
    
    if scanning {
        manager.stopScan()
    }
    
    for device in discoveredPeripherals {
        if device.peripheral.state == .connected || device.peripheral.state == .connecting {
            manager.cancelPeripheralConnection(device.peripheral)
        }
    }
    
    scanTimeoutTask?.cancel()
    connectionTimeouts.values.forEach { $0.cancel() }
}
```

✅ **Скомпилировать и протестировать**

---

## 🧪 Финальное тестирование (15 минут)

### Тест-кейсы

#### ✅ Тест 1: Happy Path
1. Запустить приложение
2. Подождать автоматического сканирования
3. Устройство найдено и подключено
4. Синхронизация времени прошла успешно
5. Данные (температура, влажность) обновляются

#### ✅ Тест 2: No Device Found
1. Выключить все BLE устройства поблизости
2. Запустить сканирование
3. Подождать 30 секунд
4. Должно появиться сообщение: "No devices found"

#### ✅ Тест 3: Connection Timeout
1. Начать подключение к устройству
2. Выключить устройство до завершения подключения
3. Подождать 10 секунд
4. Должно появиться: "Connection timeout"

#### ✅ Тест 4: Unexpected Disconnection
1. Подключиться к устройству
2. Выключить устройство
3. Должны быть 3 попытки переподключения
4. Включить устройство во время попыток
5. Должно переподключиться автоматически

#### ✅ Тест 5: Bluetooth Off/On
1. Подключиться к устройству
2. Выключить Bluetooth на компьютере/телефоне
3. Должно появиться: "Bluetooth is powered off"
4. Включить Bluetooth обратно
5. Должно автоматически начаться сканирование

#### ✅ Тест 6: Multiple Scans
1. Сканирование → находит Device A
2. Остановка сканирования
3. Новое сканирование → снова находит Device A
4. Проверить, что в логах: "Reusing cached device"
5. Device A должен иметь то же состояние (history, flags)

---

## 📊 Чеклист результатов

После завершения миграции убедитесь:

- [ ] ✅ Проект компилируется без ошибок
- [ ] ✅ Сканирование работает с таймаутом 30с
- [ ] ✅ Подключение работает с таймаутом 10с
- [ ] ✅ Автопереподключение работает (3 попытки)
- [ ] ✅ Device cache предотвращает дубликаты
- [ ] ✅ Логи показывают правильные сообщения
- [ ] ✅ UI реагирует на изменения состояния
- [ ] ✅ Bluetooth состояния обрабатываются корректно
- [ ] ✅ Нет crash'ей при выключении Bluetooth
- [ ] ✅ Память не утекает при повторных сканированиях

---

## 🐛 Troubleshooting

### Проблема: "Cannot find 'BLEError' in scope"

**Решение:** Убедитесь, что enum BLEError определён в том же файле перед классом BLEClient:

```swift
enum BLEError: LocalizedError {
    case bluetoothNotReady
    case connectionTimeout
    // ...
}

@MainActor
final class BLEClient: NSObject, ObservableObject {
    // ...
}
```

### Проблема: Компилятор жалуется на "ambiguous use of 'triggerScan'"

**Решение:** Обновите все вызовы метода:

```swift
// Старый код:
bleClient.triggerScan()

// Новый код (с явным параметром по умолчанию):
bleClient.triggerScan()  // Использует default timeout: 30.0
// или
bleClient.triggerScan(timeout: 15.0)  // Кастомный таймаут
```

### Проблема: Устройство не переподключается автоматически

**Проверьте:**
1. `autoReconnectEnabled` установлен в `true`
2. В логах видны попытки переподключения
3. Устройство включается в пределах 7 секунд (1+2+4)

**Отладка:**
```swift
// Добавить временно в attemptReconnection:
print("🔍 Reconnection attempts: \(attempts)/\(maxReconnectionAttempts)")
print("🔍 Delay: \(delay) seconds")
```

### Проблема: Сканирование не останавливается через 30 секунд

**Проверьте:**
1. Task не отменяется раньше времени
2. В логах есть сообщение "Scan stopped after timeout"

**Отладка:**
```swift
// В triggerScan добавить:
logger.info("Scan will stop in \(timeout) seconds")
```

---

## 🎓 Откат изменений (если что-то пошло не так)

```bash
# Вернуться к оригинальной версии
cp Shared/BluetoothClient.swift.backup Shared/BluetoothClient.swift

# Или через git:
git checkout Shared/BluetoothClient.swift

# Скомпилировать снова
xcodebuild -project "LYWSD02 Clock Sync.xcodeproj" -scheme "LYWSD02 Clock Sync (macOS)" clean build
```

---

## 📝 Коммит изменений

После успешного тестирования:

```bash
git add Shared/BluetoothClient.swift
git add BluetoothClient_*.md
git add BluetoothClient_Improvements.swift

git commit -m "Improve BLEClient: timeouts, auto-reconnect, device caching

- Add connection timeout (10s default)
- Add scan timeout (30s default)
- Implement auto-reconnection (3 attempts with exponential backoff)
- Add device caching to prevent memory leaks
- Improve state transition handling
- Add protocol for testability
- Add comprehensive cleanup in deinit

See BluetoothClient_Analysis.md for details"

git push origin bluetooth-improvements
```

---

## 🚀 Следующие шаги

После успешной миграции рассмотрите:

1. **Добавить Unit Tests** (см. BluetoothClient_Analysis.md, раздел 14)
2. **Создать MockBLEClient** для тестирования UI
3. **Добавить метрики** (статистика подключений)
4. **Локализовать сообщения** об ошибках
5. **Добавить DocC документацию**

---

**Последнее обновление:** 17 ноября 2025  
**Время на полную миграцию:** ~45 минут  
**Время на постепенную миграцию:** ~60 минут  
**Сложность:** ⭐⭐⭐ (средняя)

---

## 💬 Поддержка

Если возникли проблемы:

1. **Проверьте логи** в Console.app (фильтр: com.lywsd02.clocksync)
2. **Посмотрите примеры** в BluetoothClient_Improvements.swift
3. **Изучите диаграммы** в BluetoothClient_Architecture.md
4. **Используйте чеклист** в BluetoothClient_QuickReference.md

**Удачи! 🍀**

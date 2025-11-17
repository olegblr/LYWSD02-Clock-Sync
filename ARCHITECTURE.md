# Architecture Documentation
## LYWSD02 Clock Sync - System Design

**Last Updated:** November 17, 2025  
**Version:** 1.0  
**Authors:** Development Team

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Component Design](#component-design)
4. [Data Flow](#data-flow)
5. [State Management](#state-management)
6. [Concurrency Model](#concurrency-model)
7. [Error Handling Strategy](#error-handling-strategy)
8. [Security Architecture](#security-architecture)
9. [Performance Considerations](#performance-considerations)
10. [Future Architecture](#future-architecture)

---

## Overview

LYWSD02 Clock Sync is a native iOS/macOS application built with **SwiftUI** and **CoreBluetooth**, following **MVVM (Model-View-ViewModel)** architecture with clean separation of concerns.

### Design Principles

- ✅ **Separation of Concerns** - Clear boundaries between UI, business logic, and data
- ✅ **Single Responsibility** - Each component has one well-defined purpose
- ✅ **Dependency Injection** - Components are loosely coupled
- ✅ **Testability** - Architecture supports unit and integration testing
- ✅ **Scalability** - Easy to add new features without major refactoring

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                      │
│                        (SwiftUI)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ ContentView  │  │  DeviceView  │  │   StyleKit      │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │ @ObservedObject
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                   ViewModel Layer                           │
│                (@MainActor ObservableObject)                │
│  ┌──────────────┐  ┌──────────────────────────────────┐   │
│  │  BLEClient   │  │      BLEDeviceModel              │   │
│  │              │  │                                  │   │
│  │ - Scanning   │  │ - State Management               │   │
│  │ - Discovery  │  │ - Characteristic Handling        │   │
│  │ - Connection │  │ - Data Parsing                   │   │
│  └──────────────┘  └──────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │ Delegates
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                    Service Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  BinUtils    │  │     Time     │  │  LYWSD02UUID    │  │
│  │  (pack/      │  │  (encoding)  │  │  (constants)    │  │
│  │   unpack)    │  │              │  │                 │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                  System Frameworks                          │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │CoreBluetooth │  │  Foundation  │  │     os.log      │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                   LYWSD02 Device                            │
│                 (Bluetooth LE Hardware)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Design

### 1. BLEClient (Central Manager)

**Responsibility:** Manage Bluetooth scanning and device connections

```
┌─────────────────────────────────────┐
│          BLEClient                  │
├─────────────────────────────────────┤
│ Properties:                         │
│ - discoveredPeripherals: [Model]    │
│ - scanning: Bool                    │
│ - manager: CBCentralManager         │
│ - peripheralCache: [UUID: Model]    │
│ - connectionTimeouts: [UUID: Task]  │
├─────────────────────────────────────┤
│ Methods:                            │
│ + triggerScan()                     │
│ + stopScan()                        │
│ + connect(to:)                      │
│ + disconnect(_:)                    │
├─────────────────────────────────────┤
│ Delegates:                          │
│ - centralManagerDidUpdateState()    │
│ - didDiscover()                     │
│ - didConnect()                      │
│ - didDisconnect()                   │
│ - didFailToConnect()                │
└─────────────────────────────────────┘
```

**Design Patterns:**
- **Singleton-like** - One instance per app
- **Observer** - Publishes state changes via `@Published`
- **Delegate** - Implements `CBCentralManagerDelegate`
- **Cache** - O(1) peripheral lookup via Dictionary

---

### 2. BLEDeviceModel (Peripheral Manager)

**Responsibility:** Manage per-device state and operations

```
┌─────────────────────────────────────┐
│       BLEDeviceModel                │
├─────────────────────────────────────┤
│ Published Properties:               │
│ - currentTime: Date?                │
│ - currentTemperature: Double?       │
│ - currentHumidity: Int?             │
│ - batteryPercentage: Int?           │
│ - history: [HistoryRecord]          │
│ - hasXXXSupport: Bool (various)     │
├─────────────────────────────────────┤
│ Methods:                            │
│ + sync()                            │
│ + syncTime(target:)                 │
│ + fetchHistory()                    │
├─────────────────────────────────────┤
│ Delegates:                          │
│ - didDiscoverServices()             │
│ - didDiscoverCharacteristics()      │
│ - didUpdateValue()                  │
│ - didWriteValue()                   │
└─────────────────────────────────────┘
```

**Design Patterns:**
- **Observer** - Publishes state via `@Published`
- **Delegate** - Implements `CBPeripheralDelegate`
- **State Machine** - Manages connection/discovery states
- **Strategy** - Different parsing for each characteristic

---

### 3. Views (Presentation)

#### ContentView
```
┌─────────────────────────────────────┐
│         ContentView                 │
├─────────────────────────────────────┤
│ Responsibilities:                   │
│ - Device scanning UI                │
│ - Auto-selection of first device    │
│ - Navigation to DeviceView          │
├─────────────────────────────────────┤
│ State:                              │
│ - @StateObject bleClient            │
│ - @State selectedPeripheral         │
└─────────────────────────────────────┘
```

#### DeviceView
```
┌─────────────────────────────────────┐
│         DeviceView                  │
├─────────────────────────────────────┤
│ Responsibilities:                   │
│ - Display device data               │
│ - Time sync controls                │
│ - History visualization             │
│ - Battery/sensor metrics            │
├─────────────────────────────────────┤
│ Sections:                           │
│ 1. Header (time, drift)             │
│ 2. Metrics (temp, humidity, battery)│
│ 3. Capabilities                     │
│ 4. History (charts)                 │
└─────────────────────────────────────┘
```

---

## Data Flow

### Device Discovery Flow

```
User Opens App
    ↓
ContentView.onAppear()
    ↓
BLEClient.triggerScan()
    ↓
CBCentralManager.scanForPeripherals()
    ↓
[Bluetooth Advertisement Received]
    ↓
BLEClient.centralManager(_:didDiscover:...)
    ↓
Create/Cache BLEDeviceModel
    ↓
Append to discoveredPeripherals
    ↓
SwiftUI Updates List
    ↓
ContentView Selects First Device
    ↓
Navigate to DeviceView
```

### Connection Flow

```
DeviceView.onAppear()
    ↓
BLEClient.connect(to: device)
    ↓
CBCentralManager.connect(peripheral)
    ↓
[10s timeout scheduled]
    ↓
[Connection Success]
    ↓
BLEClient.centralManager(_:didConnect:)
    ↓
Cancel timeout task
    ↓
CBPeripheral.discoverServices()
    ↓
BLEDeviceModel.peripheral(_:didDiscoverServices:)
    ↓
CBPeripheral.discoverCharacteristics()
    ↓
BLEDeviceModel.peripheral(_:didDiscoverCharacteristics:)
    ↓
Set hasXXXSupport flags
    ↓
Schedule auto time sync (200ms delay)
    ↓
BLEDeviceModel.sync()
    ↓
Read battery, time, sensor data
```

### Data Update Flow

```
[Characteristic Value Updated]
    ↓
CBPeripheral.didUpdateValueForCharacteristic
    ↓
BLEDeviceModel.peripheral(_:didUpdateValueFor:...)
    ↓
Task { @MainActor in
    handleCharacteristicUpdate()
}
    ↓
switch characteristic.uuid {
    case Time: Parse timestamp → currentTime
    case Battery: Parse byte → batteryPercentage
    case SensorData: Parse temp/humidity
    case History: Append to history array
}
    ↓
@Published property updates
    ↓
SwiftUI automatically re-renders UI
```

---

## State Management

### BLEClient State

```swift
enum BluetoothState {
    case unknown
    case poweredOff
    case poweredOn
    case unauthorized
    case unsupported
}

// Managed by CBCentralManager.state
```

### Connection State

```swift
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// Per-device, managed by CBPeripheral.state
```

### Discovery State

```swift
enum DiscoveryState {
    case idle              // Not scanning
    case scanning          // Active scan
    case deviceFound       // At least one device found
    case deviceSelected    // User selected device
}
```

### Sync State

```swift
enum SyncState {
    case idle
    case syncing
    case completed(Date)
    case failed(Error)
}
```

---

## Concurrency Model

### Thread Safety Strategy

```
┌─────────────────────────────────────┐
│        Main Thread (UI)             │
│      @MainActor isolated            │
│                                     │
│  - SwiftUI Views                    │
│  - BLEClient                        │
│  - BLEDeviceModel                   │
│  - @Published property updates      │
└─────────────┬───────────────────────┘
              │
              │ Task { @MainActor in ... }
              │
┌─────────────▼───────────────────────┐
│    Bluetooth Queue (Background)     │
│     (CBCentralManager queue)        │
│                                     │
│  - Scanning                         │
│  - Connection/Disconnection         │
│  - Service/Characteristic Discovery │
│  - Data Read/Write                  │
└─────────────────────────────────────┘
```

### Actor Isolation

```swift
@MainActor
class BLEClient: ObservableObject {
    // All properties accessed on main thread
    @Published var discoveredPeripherals: [BLEDeviceModel] = []
    
    // Delegate methods are nonisolated
    nonisolated func centralManager(...) {
        // Dispatch to main actor for property updates
        Task { @MainActor in
            self.discoveredPeripherals.append(device)
        }
    }
}
```

### Task Management

```swift
// Auto-sync task with cancellation
private var autoSyncTask: Task<Void, Never>?

func scheduleAutoSync() {
    autoSyncTask?.cancel()
    autoSyncTask = Task {
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        try await syncTime()
    }
}

func cleanup() {
    autoSyncTask?.cancel()
    autoSyncTask = nil
}
```

---

## Error Handling Strategy

### Error Hierarchy

```
Error (Protocol)
    │
    ├── BLEError (Custom)
    │   ├── bluetoothPoweredOff
    │   ├── characteristicNotFound
    │   ├── invalidData(reason: String)
    │   ├── connectionTimeout
    │   └── ...
    │
    ├── BinUtilsError
    │   ├── formatDoesMatchDataLength
    │   └── unsupportedFormat
    │
    └── Foundation Errors
        ├── NSError
        └── ...
```

### Error Propagation

```
Device Layer (throws)
    ↓
ViewModel Layer (catches, logs, publishes)
    ↓
View Layer (displays to user)
```

### Example Error Flow

```swift
// Device Layer
func syncTime(target: Date) throws {
    guard hasTimeSupport else {
        throw BLEError.characteristicNotFound
    }
    // ...
}

// ViewModel Layer
func performSync() {
    do {
        try syncTime(target: Date())
        logger.info("Sync successful")
    } catch let error as BLEError {
        logger.error("Sync failed: \(error.localizedDescription)")
        errorState = error
    } catch {
        logger.error("Unknown error: \(error)")
    }
}

// View Layer
if let error = viewModel.errorState {
    Text(error.localizedDescription)
        .foregroundColor(.red)
}
```

---

## Security Architecture

### Threat Model

| Threat | Mitigation |
|--------|------------|
| **Malicious BLE device** | Input validation, bounds checking |
| **Data injection** | Type checking, range validation |
| **Buffer overflow** | Proper array bounds checking |
| **Privacy leak** | No external network calls, sandboxed |
| **Code injection** | Swift type safety, no eval() |

### Security Layers

```
┌─────────────────────────────────────┐
│      Application Sandbox            │
│  (iOS/macOS System Enforcement)     │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│      Input Validation Layer         │
│  - Range checks                     │
│  - Type validation                  │
│  - Bounds checking                  │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│      Business Logic Layer           │
│  - Data parsing                     │
│  - State management                 │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│      System Framework Layer         │
│  - CoreBluetooth (Apple verified)   │
└─────────────────────────────────────┘
```

### Data Validation

```swift
// Example: Temperature validation
func validateTemperature(_ raw: Int) throws -> Double {
    let temp = Double(raw) / 100.0
    
    guard LYWSD02Constants.Ranges.temperature.contains(temp) else {
        throw BLEError.invalidData(
            reason: "Temperature \(temp)°C out of range"
        )
    }
    
    return temp
}
```

---

## Performance Considerations

### Optimization Strategies

#### 1. Caching
```swift
// O(1) peripheral lookup instead of O(n)
private var peripheralCache: [UUID: BLEDeviceModel] = [:]

func findDevice(uuid: UUID) -> BLEDeviceModel? {
    return peripheralCache[uuid]  // O(1)
    // vs Array.first { $0.id == uuid }  // O(n)
}
```

#### 2. Lazy Loading
```swift
// History fetched on demand, not automatically
func fetchHistory() {
    guard hasHistorySupport else { return }
    // Fetch only when user requests
}
```

#### 3. Throttling
```swift
// Sync timer runs every 60s, not continuously
private let timer = Timer.publish(every: 60, on: .main, in: .common)
```

#### 4. Efficient Data Structures
```swift
// Use Set for O(1) contains checks
var connectedDeviceIDs: Set<UUID> = []

// vs Array (O(n))
var connectedDeviceIDs: [UUID] = []
```

### Memory Management

```swift
// Weak references in closures
Task { [weak self] in
    guard let self = self else { return }
    // ...
}

// Task cancellation
private var tasks: [UUID: Task<Void, Never>] = [:]

func cleanup(for device: UUID) {
    tasks[device]?.cancel()
    tasks.removeValue(forKey: device)
}
```

---

## Future Architecture

### Planned Improvements

#### 1. Repository Pattern
```swift
protocol DeviceRepository {
    func saveDevice(_ device: BLEDeviceModel)
    func loadDevices() -> [BLEDeviceModel]
    func deleteDevice(id: UUID)
}

class UserDefaultsDeviceRepository: DeviceRepository {
    // Persistent storage implementation
}
```

#### 2. Dependency Injection
```swift
protocol BluetoothService {
    func scan()
    func connect(to: UUID)
}

class BLEClient: BluetoothService {
    // Implementation
}

// Easier testing with mock
class MockBluetoothService: BluetoothService {
    // Test implementation
}
```

#### 3. State Machine
```swift
enum AppState {
    case idle
    case scanning
    case connecting(device: BLEDeviceModel)
    case connected(device: BLEDeviceModel)
    case error(BLEError)
    
    mutating func handle(event: AppEvent) {
        // State transition logic
    }
}
```

#### 4. Coordinator Pattern
```swift
class AppCoordinator {
    func start()
    func showDeviceList()
    func showDevice(_ device: BLEDeviceModel)
    func showSettings()
}
```

---

## Architecture Decision Records (ADRs)

### ADR-001: SwiftUI over UIKit
**Decision:** Use SwiftUI for UI layer  
**Rationale:**
- Modern, declarative syntax
- Less boilerplate
- Automatic state updates
- Cross-platform (iOS/macOS)

**Trade-offs:**
- ✅ Faster development
- ❌ Some advanced customization harder
- ❌ Requires iOS 16+/macOS 13+

---

### ADR-002: MVVM Architecture
**Decision:** Use MVVM pattern  
**Rationale:**
- Natural fit for SwiftUI
- Clear separation of concerns
- Testable business logic

**Trade-offs:**
- ✅ Easy to understand
- ✅ Scalable
- ❌ Can lead to massive ViewModels

---

### ADR-003: No External Dependencies
**Decision:** Use only system frameworks  
**Rationale:**
- Reduce attack surface
- Faster build times
- No version conflicts

**Trade-offs:**
- ✅ Smaller binary
- ✅ More secure
- ❌ More code to write

---

### ADR-004: Main Actor Isolation
**Decision:** Isolate ViewModels to MainActor  
**Rationale:**
- Thread safety for UI updates
- Prevent race conditions
- Swift 5.9 best practice

**Trade-offs:**
- ✅ Safer concurrency
- ✅ Clearer code
- ❌ Must be careful with nonisolated code

---

## Diagrams

### Component Interaction

```
┌─────────┐      ┌─────────┐      ┌──────────┐
│  User   │─────→│  View   │─────→│ViewModel│
└─────────┘      └─────────┘      └──────────┘
                       ↑                 │
                       │                 ↓
                       │            ┌─────────┐
                       │            │ Service │
                       │            └─────────┘
                       │                 │
                       │                 ↓
                       │            ┌─────────┐
                       └────────────│  Model  │
                                    └─────────┘
```

### Deployment Architecture

```
┌──────────────────────────────────────┐
│         User Device                  │
│  ┌────────────────────────────┐     │
│  │  LYWSD02 Clock Sync App    │     │
│  │  (Sandboxed)               │     │
│  └────────────┬───────────────┘     │
│               │                      │
│  ┌────────────▼───────────────┐     │
│  │  iOS/macOS System          │     │
│  │  - CoreBluetooth           │     │
│  │  - Foundation              │     │
│  └────────────┬───────────────┘     │
└───────────────┼──────────────────────┘
                │ Bluetooth LE
                ↓
┌───────────────────────────────────────┐
│      LYWSD02 Device                   │
│  (Xiaomi Temperature/Humidity Sensor) │
└───────────────────────────────────────┘
```

---

## Summary

The LYWSD02 Clock Sync architecture prioritizes:

1. **Simplicity** - Easy to understand and maintain
2. **Safety** - Thread-safe, error-handled, validated
3. **Performance** - Efficient caching and data structures
4. **Scalability** - Room to grow without major refactoring
5. **Testability** - Clear separation enables testing

**Next Steps:**
- Implement repository pattern for persistence
- Add comprehensive test suite
- Consider state machine for complex flows
- Explore coordinator pattern for navigation

---

**Document Version:** 1.0  
**Last Updated:** November 17, 2025  
**Maintained by:** Development Team

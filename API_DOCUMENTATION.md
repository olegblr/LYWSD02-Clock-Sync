# 📚 API Documentation
## LYWSD02 Clock Sync - Developer Reference

**Last Updated:** November 17, 2025  
**API Version:** 1.0  
**Swift Version:** 5.9+

---

## Table of Contents

1. [Overview](#overview)
2. [Core Components](#core-components)
3. [BLEClient API](#bleclient-api)
4. [BLEDeviceModel API](#bledevicemodel-api)
5. [Data Models](#data-models)
6. [Error Handling](#error-handling)
7. [Binary Utilities](#binary-utilities)
8. [Usage Examples](#usage-examples)

---

## Overview

The LYWSD02 Clock Sync API provides a high-level Swift interface for:
- Discovering LYWSD02 Bluetooth sensors
- Connecting to devices
- Reading sensor data (temperature, humidity, battery)
- Synchronizing device time
- Fetching historical data

### Architecture Diagram

```
┌─────────────────────────────────────────┐
│          SwiftUI Views                  │
│    (ContentView, DeviceView)            │
└────────────────┬────────────────────────┘
                 │
                 ↓ ObservableObject
┌─────────────────────────────────────────┐
│           BLEClient                     │
│  - Scanning                             │
│  - Connection Management                │
│  - Device Discovery                     │
└────────────────┬────────────────────────┘
                 │
                 ↓ CBCentralManagerDelegate
┌─────────────────────────────────────────┐
│        CoreBluetooth                    │
└────────────────┬────────────────────────┘
                 │
                 ↓ Bluetooth LE
┌─────────────────────────────────────────┐
│         BLEDeviceModel                  │
│  - Characteristic Management            │
│  - Data Parsing                         │
│  - State Management                     │
└────────────────┬────────────────────────┘
                 │
                 ↓ CBPeripheralDelegate
┌─────────────────────────────────────────┐
│       LYWSD02 Device                    │
└─────────────────────────────────────────┘
```

---

## Core Components

### 1. BLEClient

**File:** `BluetoothClient.swift`  
**Type:** `@MainActor class`  
**Conforms to:** `ObservableObject`, `CBCentralManagerDelegate`

Central Bluetooth manager responsible for device discovery and connection lifecycle.

### 2. BLEDeviceModel

**File:** `BLEDeviceModel.swift`  
**Type:** `@MainActor final class`  
**Conforms to:** `ObservableObject`, `CBPeripheralDelegate`

Per-device model managing state, data synchronization, and characteristics.

### 3. LYWSD02UUID

**File:** `LYWSD02.swift`  
**Type:** `struct`

Constants for LYWSD02 Bluetooth UUIDs and characteristics.

---

## BLEClient API

### Class Definition

```swift
@MainActor
class BLEClient: NSObject, ObservableObject, CBCentralManagerDelegate
```

### Published Properties

#### discoveredPeripherals
```swift
@Published public var discoveredPeripherals: [BLEDeviceModel]
```
**Description:** Array of discovered LYWSD02 devices.  
**Thread:** Main actor  
**Updates:** Automatically when devices are discovered

#### scanning
```swift
@Published var scanning: Bool
```
**Description:** Indicates if Bluetooth scanning is active.  
**Thread:** Main actor  
**Default:** `false`

### Methods

#### triggerScan()
```swift
func triggerScan()
```
**Description:** Starts scanning for LYWSD02 devices.  
**Preconditions:** Bluetooth must be powered on  
**Side Effects:**
- Clears `discoveredPeripherals`
- Sets `scanning` to `true`
- Begins BLE scan for service UUIDs

**Example:**
```swift
let client = BLEClient()
client.triggerScan()
```

---

#### stopScan()
```swift
func stopScan()
```
**Description:** Stops active Bluetooth scan.  
**Side Effects:** Sets `scanning` to `false`

**Example:**
```swift
client.stopScan()
```

---

#### connect(to:)
```swift
func connect(to model: BLEDeviceModel)
```
**Description:** Initiates connection to a device.  
**Parameters:**
- `model`: Device model to connect to

**Behavior:**
- Ignores if already connected
- Triggers auto-sync on successful connection
- Handles reconnection automatically on disconnect

**Example:**
```swift
if let device = client.discoveredPeripherals.first {
    client.connect(to: device)
}
```

---

#### disconnect(_:)
```swift
func disconnect(_ model: BLEDeviceModel)
```
**Description:** Disconnects from a device.  
**Parameters:**
- `model`: Device model to disconnect

**Example:**
```swift
client.disconnect(device)
```

---

### Delegate Methods

#### centralManagerDidUpdateState(_:)
```swift
nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager)
```
**Description:** Called when Bluetooth state changes.  
**Behavior:**
- `.poweredOff`: Stops scanning
- `.poweredOn`: Triggers scan automatically

---

#### centralManager(_:didDiscover:advertisementData:rssi:)
```swift
nonisolated func centralManager(
    _ central: CBCentralManager, 
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], 
    rssi RSSI: NSNumber
)
```
**Description:** Called when a device is discovered.  
**Implementation:** 
- Uses cache for O(1) lookup
- Creates `BLEDeviceModel` if new
- Appends to `discoveredPeripherals`

---

#### centralManager(_:didConnect:)
```swift
nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
```
**Description:** Called on successful connection.  
**Behavior:**
- Cancels connection timeout
- Resets reconnection attempts
- Discovers services

---

#### centralManager(_:didDisconnectPeripheral:error:)
```swift
nonisolated func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
)
```
**Description:** Called on device disconnect.  
**Behavior:**
- Attempts auto-reconnection (up to 3 times)
- Uses exponential backoff: 1s, 2s, 4s

---

## BLEDeviceModel API

### Class Definition

```swift
@MainActor
final class BLEDeviceModel: NSObject, ObservableObject, CBPeripheralDelegate
```

### Published Properties

#### Device Capabilities

```swift
@Published private(set) var hasTimeSupport: Bool = false
@Published private(set) var hasBatterySupport: Bool = false
@Published private(set) var hasTemperatureSupport: Bool = false
@Published private(set) var hasHumiditySupport: Bool = false
@Published private(set) var hasHistorySupport: Bool = false
```

#### Sensor Data

```swift
@Published private(set) var batteryPercentage: Int? = nil
@Published private(set) var currentTime: Date? = nil
@Published private(set) var currentTemperature: Double? = nil  // Celsius
@Published private(set) var currentHumidity: Int? = nil        // Percentage
```

#### History

```swift
@Published private(set) var history: [HistoryRecord] = []
@Published private(set) var totalHistoryRecords: Int? = nil
@Published private(set) var currentHistoryRecords: Int? = nil
@Published private(set) var isFetchingHistory: Bool = false
```

#### Metadata

```swift
@Published private(set) var name: String
@Published private(set) var lastAutoTimeSyncAt: Date? = nil
```

---

### Methods

#### sync()
```swift
func sync()
```
**Description:** Reads current values from device.  
**Updates:** Battery, time (if supported)  
**Thread:** Must be called on main actor

**Example:**
```swift
device.sync()
```

---

#### syncTime(target:)
```swift
func syncTime(target: Date) throws
```
**Description:** Synchronizes device time to target date.  
**Parameters:**
- `target`: Date to sync to

**Throws:**
- `BLEError.characteristicNotFound` - Device doesn't support time sync
- `BLEError.invalidData` - Target date out of valid range

**Validation:**
- Must be within ±10 years from now
- Timezone offset must be -12...+14

**Example:**
```swift
do {
    try device.syncTime(target: Date())
    print("Time synced successfully")
} catch {
    print("Sync failed: \(error)")
}
```

---

#### fetchHistory()
```swift
func fetchHistory()
```
**Description:** Fetches historical sensor data from device.  
**Preconditions:** `hasHistorySupport` must be `true`  
**Side Effects:**
- Clears existing history
- Sets `isFetchingHistory` to `true`
- Populates `history` array asynchronously

**Example:**
```swift
if device.hasHistorySupport {
    device.fetchHistory()
}
```

---

### Computed Properties

#### identifier
```swift
var identifier: String { peripheral.identifier.uuidString }
```
**Returns:** UUID string of the peripheral

#### peripheral
```swift
var peripheral: CBPeripheral { _peripheral }
```
**Returns:** Underlying `CBPeripheral` instance

---

### Nested Types

#### HistoryRecord
```swift
struct HistoryRecord: Identifiable {
    let id: Int                      // Index from device
    let timestamp: Date              // When recorded
    let minTemperature: Double       // Min temp in period (°C)
    let minHumidity: Int            // Min humidity in period (%)
    let maxTemperature: Double       // Max temp in period (°C)
    let maxHumidity: Int            // Max humidity in period (%)
}
```

---

## Data Models

### LYWSD02UUID

#### Services

```swift
enum Service: String {
    case Unknown1 = "181A"     // Advertising service
    case Unknown2 = "FEF5"     // Advertising service
    case Data = "EBE0CCB0-7A0A-4B0C-8A1A-6FF2997DA3A6"
    
    var cbuuid: CBUUID { CBUUID(string: self.rawValue) }
}
```

#### Characteristics

```swift
enum Characteristic: String {
    case Time       = "EBE0CCB7-7A0A-4B0C-8A1A-6FF2997DA3A6"  // 5 bytes, READ WRITE
    case Battery    = "EBE0CCC4-7A0A-4B0C-8A1A-6FF2997DA3A6"  // 1 byte, READ
    case SensorData = "EBE0CCC1-7A0A-4B0C-8A1A-6FF2997DA3A6"  // 3 bytes, READ NOTIFY
    case Units      = "EBE0CCBE-7A0A-4B0C-8A1A-6FF2997DA3A6"  // READ WRITE
    case History    = "EBE0CCBC-7A0A-4B0C-8A1A-6FF2997DA3A6"  // READ NOTIFY
    case NumRecords = "EBE0CCB9-7A0A-4B0C-8A1A-6FF2997DA3A6"  // 8 bytes, READ
    case RecordIndex = "EBE0CCBA-7A0A-4B0C-8A1A-6FF2997DA3A6" // 4 bytes, READ WRITE
    
    var cbuuid: CBUUID { CBUUID(string: self.rawValue) }
}
```

---

### Time

```swift
struct Time {
    var timestamp: Int           // Unix timestamp
    var timezoneOffset: Int      // Hours from UTC (-12...+14)
    
    func data() -> Data          // Encodes to BLE data format
}
```

**Binary Format:** `<Ib` (little-endian 4-byte int + 1-byte signed int)

---

### LYWSD02Constants

```swift
enum LYWSD02Constants {
    // Timing
    static let autoSyncDelay: TimeInterval = 0.2
    static let connectionTimeout: TimeInterval = 10.0
    static let scanTimeout: TimeInterval = 30.0
    
    // Data sizes
    static let timeDataSize = 5
    static let sensorDataSize = 3
    static let batteryDataSize = 1
    
    // Validation ranges
    enum Ranges {
        static let temperature: ClosedRange<Double> = -40...80
        static let humidity: ClosedRange<Int> = 0...100
        static let battery: ClosedRange<Int> = 0...100
        static let timezoneOffset: ClosedRange<Int> = -12...14
    }
    
    static let maxReconnectionAttempts = 3
}
```

---

## Error Handling

### BLEError

```swift
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
}
```

### Error Properties

#### errorDescription
```swift
var errorDescription: String?
```
Human-readable error message for display to users.

#### recoverySuggestion
```swift
var recoverySuggestion: String?
```
Actionable suggestion for resolving the error.

---

### Error Handling Example

```swift
do {
    try device.syncTime(target: Date())
} catch BLEError.characteristicNotFound {
    showAlert("Your device doesn't support time synchronization")
} catch BLEError.invalidData(let reason) {
    showAlert("Invalid time: \(reason)")
} catch {
    showAlert("Sync failed: \(error.localizedDescription)")
}
```

---

## Binary Utilities

### pack(_:_:_:)

```swift
public func pack(
    _ format: String, 
    _ objects: [Any], 
    _ stringEncoding: String.Encoding = .windowsCP1252
) -> Data
```

**Description:** Packs data into binary format (Python struct-like).  
**Parameters:**
- `format`: Format string (e.g., `"<I"`, `"<hB"`)
- `objects`: Array of values to pack
- `stringEncoding`: String encoding (default CP1252)

**Format Specifiers:**
| Code | Type | Size |
|------|------|------|
| `<` | Little-endian | - |
| `>` | Big-endian | - |
| `b` | Signed byte | 1 |
| `B` | Unsigned byte | 1 |
| `h` | Short | 2 |
| `H` | Unsigned short | 2 |
| `i`, `l` | Int | 4 |
| `I`, `L` | Unsigned int | 4 |
| `q` | Long long | 8 |
| `Q` | Unsigned long long | 8 |
| `f` | Float | 4 |
| `d` | Double | 8 |

**Example:**
```swift
let timestamp = Int(Date().timeIntervalSince1970)
let offset = 1
let data = pack("<Ib", [timestamp, offset])
```

---

### unpack(_:_:_:)

```swift
public func unpack(
    _ format: String, 
    _ data: Data, 
    _ stringEncoding: String.Encoding = .windowsCP1252
) throws -> [Unpackable]
```

**Description:** Unpacks binary data (Python struct-like).  
**Returns:** Array of unpacked values  
**Throws:** `BinUtilsError` if format/data mismatch

**Example:**
```swift
let data = characteristic.value!
let values = try unpack("<hB", data)
let temperature = (values[0] as! Int) / 100.0
let humidity = values[1] as! Int
```

---

## Usage Examples

### Example 1: Basic Scanning & Connection

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var bleClient = BLEClient()
    
    var body: some View {
        VStack {
            if bleClient.scanning {
                ProgressView("Scanning...")
            }
            
            List(bleClient.discoveredPeripherals, id: \.identifier) { device in
                Button(device.name) {
                    bleClient.connect(to: device)
                }
            }
        }
        .onAppear {
            bleClient.triggerScan()
        }
    }
}
```

---

### Example 2: Reading Sensor Data

```swift
struct SensorView: View {
    @ObservedObject var device: BLEDeviceModel
    
    var body: some View {
        VStack(spacing: 20) {
            if let temp = device.currentTemperature {
                Text("\(temp, specifier: "%.1f")°C")
                    .font(.largeTitle)
            }
            
            if let humidity = device.currentHumidity {
                Text("\(humidity)%")
                    .font(.title)
            }
            
            if let battery = device.batteryPercentage {
                Text("Battery: \(battery)%")
                    .font(.caption)
            }
        }
        .onAppear {
            device.sync()
        }
    }
}
```

---

### Example 3: Time Synchronization

```swift
struct TimeSyncView: View {
    @ObservedObject var device: BLEDeviceModel
    @State private var customTime = Date()
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            DatePicker("Time", selection: $customTime)
            
            Button("Sync Time") {
                syncTime()
            }
            .disabled(!device.hasTimeSupport)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func syncTime() {
        do {
            try device.syncTime(target: customTime)
            errorMessage = nil
        } catch let error as BLEError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Unknown error: \(error)"
        }
    }
}
```

---

### Example 4: History Visualization

```swift
import Charts

struct HistoryView: View {
    @ObservedObject var device: BLEDeviceModel
    
    var body: some View {
        VStack {
            if device.isFetchingHistory {
                ProgressView("Loading history...")
            } else if device.history.isEmpty {
                Button("Load History") {
                    device.fetchHistory()
                }
            } else {
                Chart(device.history) { record in
                    LineMark(
                        x: .value("Time", record.timestamp),
                        y: .value("Temp", record.maxTemperature)
                    )
                }
                .frame(height: 200)
            }
        }
    }
}
```

---

### Example 5: Custom Data Parsing

```swift
// Parse sensor data manually
func parseSensorData(_ data: Data) throws -> (temp: Double, humidity: Int) {
    guard data.count == 3 else {
        throw BLEError.invalidData(reason: "Expected 3 bytes")
    }
    
    let values = try unpack("<hB", data)
    let tempRaw = values[0] as! Int
    let humidity = values[1] as! Int
    
    let temperature = Double(tempRaw) / 100.0
    
    // Validate
    guard LYWSD02Constants.Ranges.temperature.contains(temperature),
          LYWSD02Constants.Ranges.humidity.contains(humidity) else {
        throw BLEError.invalidData(reason: "Values out of range")
    }
    
    return (temperature, humidity)
}
```

---

## Best Practices

### 1. Always Handle Errors
```swift
// ❌ Bad
try! device.syncTime(target: Date())

// ✅ Good
do {
    try device.syncTime(target: Date())
} catch {
    handleError(error)
}
```

### 2. Check Capabilities
```swift
// ❌ Bad
device.fetchHistory()

// ✅ Good
if device.hasHistorySupport {
    device.fetchHistory()
} else {
    showAlert("Device doesn't support history")
}
```

### 3. Use Main Actor
```swift
// ✅ All UI updates on main thread
Task { @MainActor in
    device.sync()
}
```

### 4. Manage Connections
```swift
// ✅ Clean up on view disappear
.onDisappear {
    bleClient.disconnect(device)
}
```

### 5. Validate Data
```swift
// ✅ Always validate sensor data
if let temp = device.currentTemperature,
   LYWSD02Constants.Ranges.temperature.contains(temp) {
    updateUI(with: temp)
}
```

---

## Performance Considerations

### Caching
- `BLEClient` uses `Dictionary` for O(1) peripheral lookup
- Characteristic references should be cached
- Avoid redundant `sync()` calls

### Concurrency
- All Bluetooth operations run on background queue
- UI updates dispatched to main actor
- Use `Task` for async operations

### Memory
- Devices are weakly referenced in tasks
- Connection timeouts auto-cancel
- History limited to reasonable size

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Nov 2025 | Initial API documentation |
| 0.9 | Nov 2021 | Beta release |

---

## See Also

- [README.md](./README.md) - Project overview
- [CODE_REVIEW_REPORT.md](./CODE_REVIEW_REPORT.md) - Security & quality audit
- [CoreBluetooth Documentation](https://developer.apple.com/documentation/corebluetooth)

---

**Documentation Last Updated:** November 17, 2025  
**Maintained by:** LYWSD02 Clock Sync Contributors

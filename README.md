# LYWSD02 Clock Sync

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

> **🍴 Fork notice:** This project is a fork of [rkerkhof/LYWSD02-Clock-Sync](https://github.com/rkerkhof/LYWSD02-Clock-Sync) originally created by **Rick Kerkhof**. Significant improvements have been made including Swift 6 strict concurrency support, connection timeouts, reconnection logic, history charts, and bug fixes. Original MIT license is preserved.

A native iOS and macOS application for synchronizing time and reading sensor data from **LYWSD02 Bluetooth temperature and humidity sensors** manufactured by Xiaomi.

---

## 📱 Features

- 🔍 **Automatic Device Discovery** - Scans and finds nearby LYWSD02 sensors
- ⏰ **Time Synchronization** - Syncs device clock with phone/Mac time
- 🌡️ **Temperature Monitoring** - Real-time temperature readings in Celsius
- 💧 **Humidity Monitoring** - Live humidity percentage updates
- 🔋 **Battery Status** - Monitor device battery level
- 📊 **History Charts** - View historical temperature and humidity data with interactive charts
- 🔄 **Auto-Reconnection** - Automatically reconnects to devices with exponential backoff
- 📱 **Universal App** - Single codebase for iOS and macOS

---

## 🖼️ Screenshots

### iOS
| Device Discovery | Live Monitoring | History |
|-----------------|-----------------|---------|
| *(Screenshot)* | *(Screenshot)* | *(Screenshot)* |

### macOS
| Main Interface |
|----------------|
| *(Screenshot)* |

---

## 🏗️ Architecture

### Technology Stack

- **UI Framework:** SwiftUI
- **Bluetooth:** CoreBluetooth
- **Charts:** Swift Charts (iOS 16+, macOS 13+)
- **Concurrency:** Swift Async/Await
- **Logging:** OSLog (unified logging)

### Design Pattern

The app follows **MVVM (Model-View-ViewModel)** architecture with clean separation:

```
Views (SwiftUI)
    ↓
ViewModels (@MainActor ObservableObject)
    ↓
Models & Services
    ↓
CoreBluetooth Framework
```

### Key Components

| Component | Description |
|-----------|-------------|
| **BLEClient** | Central Bluetooth manager handling device discovery and connections |
| **BLEDeviceModel** | Per-device model managing state, data sync, and characteristics |
| **ContentView** | Main scanning and device selection interface |
| **DeviceView** | Device detail view with live data and controls |
| **BinUtils** | Binary data packing/unpacking (Python struct-like) |

---

## 🚀 Getting Started

### Prerequisites

- Xcode 15.0 or later
- iOS 16.0+ or macOS 13.0+
- LYWSD02 Bluetooth sensor device
- Apple Developer account (for device testing)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/LYWSD02-Clock-Sync.git
   cd LYWSD02-Clock-Sync
   ```

2. **Open in Xcode:**
   ```bash
   open "LYWSD02 Clock Sync.xcodeproj"
   ```

3. **Select target:**
   - iOS: `LYWSD02 Clock Sync (iOS)`
   - macOS: `LYWSD02 Clock Sync (macOS)`

4. **Build and run:**
   - Press `⌘R` or click the Play button
   - Grant Bluetooth permissions when prompted

### Permissions Required

The app requires Bluetooth permissions. Add to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth to connect to LYWSD02 sensors</string>
```

---

## 📖 Usage

### First Launch

1. **Enable Bluetooth** on your iOS device or Mac
2. **Turn on** your LYWSD02 sensor (ensure it has battery)
3. **Launch the app** - it will automatically start scanning
4. **Wait for discovery** - your device should appear within 5-10 seconds
5. **Auto-connect** - the app will automatically connect to the first discovered device

### Syncing Time

The app **automatically syncs time** upon connection. To manually sync:

1. Tap the **clock icon** or device time display
2. Adjust time if needed in the popover
3. Tap **"Sync Time"** to update the device

### Viewing History

1. Scroll down to the **History** section
2. Tap **"Get History"** to fetch historical data
3. Use the **segmented control** to filter by time range (Day/Week/Month/All)
4. Interact with **charts** to see detailed readings

### Reconnection

If the device disconnects:
- The app will **automatically attempt reconnection** up to 3 times
- Reconnection delays: 1s → 2s → 4s (exponential backoff)
- Manual reconnection: Close and reopen the app

---

## 🔧 Configuration

### Constants

Customize behavior in `LYWSD02Constants.swift`:

```swift
enum LYWSD02Constants {
    // Auto-sync delay after connection
    static let autoSyncDelay: TimeInterval = 0.2
    
    // Connection timeout
    static let connectionTimeout: TimeInterval = 10.0
    
    // Maximum reconnection attempts
    static let maxReconnectionAttempts = 3
    
    // Temperature range validation (Celsius)
    static let temperatureRange: ClosedRange<Double> = -40...80
}
```

### Logging

Control log verbosity:

```swift
// In AppDelegate or similar
Logger.subsystem = "com.lywsd02.clocksync"
// Levels: debug, info, warning, error
```

---

## 🛠️ Development

### Project Structure

```
LYWSD02-Clock-Sync/
├── Shared/                      # Cross-platform code
│   ├── BluetoothClient.swift   # BLE central manager
│   ├── BLEDeviceModel.swift    # Device state & operations
│   ├── LYWSD02.swift           # Device UUIDs & constants
│   ├── LYWSD02Constants.swift  # App-wide constants
│   ├── BLEError.swift          # Error definitions
│   ├── BinUtils.swift          # Binary data utilities
│   ├── Time.swift              # Time encoding
│   └── Views/
│       ├── ContentView.swift   # Main view
│       ├── DeviceView.swift    # Device detail view
│       └── StyleKit.swift      # UI styling
├── macOS/
│   └── macOS.entitlements      # macOS capabilities
└── LYWSD02 Clock Sync.xcodeproj/
```

### Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `BluetoothClient.swift` | Manages BLE scanning, connections, and device lifecycle | ~165 |
| `BLEDeviceModel.swift` | Handles per-device data sync, characteristics, and state | ~380 |
| `BinUtils.swift` | Python struct-like binary pack/unpack for BLE data | ~450 |
| `DeviceView.swift` | SwiftUI device detail interface with live updates | ~400 |

### Building

```bash
# iOS
xcodebuild -scheme "LYWSD02 Clock Sync (iOS)" -destination 'platform=iOS Simulator,name=iPhone 15'

# macOS
xcodebuild -scheme "LYWSD02 Clock Sync (macOS)" -destination 'platform=macOS'
```

### Code Style

The project follows standard Swift conventions:
- **Naming:** camelCase for variables/functions, PascalCase for types
- **Access Control:** Explicit `private`, `public` annotations
- **Concurrency:** Use `@MainActor` for UI-touching code
- **Formatting:** 4-space indentation, 120 character line limit

---

## 🧪 Testing

### Current Status
⚠️ **No automated tests currently implemented**

### Planned Testing Strategy

#### Unit Tests
- [ ] BinUtils pack/unpack operations
- [ ] Time encoding/decoding
- [ ] Data validation logic
- [ ] Error handling paths

#### Integration Tests
- [ ] BLE connection flow
- [ ] Auto-sync timing
- [ ] Reconnection logic
- [ ] History fetch pagination

#### UI Tests
- [ ] Device discovery flow
- [ ] Time sync interaction
- [ ] Chart rendering

Run tests:
```bash
xcodebuild test -scheme "LYWSD02 Clock Sync (iOS)" -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## 🐛 Known Issues

| Issue | Severity | Workaround |
|-------|----------|------------|
| History fetch can be slow on large datasets | Low | Wait for completion indicator |
| No background sync | Low | Keep app in foreground |

---

## 🗺️ Roadmap

### Version 1.1 (Next)
- [ ] Unit test coverage (>70%)
- [ ] Background mode support
- [ ] Multiple device support
- [ ] Export history to CSV

### Version 1.2
- [ ] Custom alerts (temperature thresholds)
- [ ] Widgets (iOS/macOS)
- [ ] Siri shortcuts

### Version 2.0
- [ ] Cloud sync
- [ ] Multi-language support
- [ ] Advanced analytics
- [ ] Apple Watch companion

---

## 📚 Documentation

### For Users
- [Quick Start Guide](./QUICK_START.md) *(coming soon)*

### For Developers
- **[API Documentation](./API_DOCUMENTATION.md)** - Public API reference
- **[Architecture Guide](./ARCHITECTURE.md)** - System design details
- **[Contributing Guide](./CONTRIBUTING.md)** - How to contribute
- **[Changelog](./CHANGELOG.md)** - Version history

### External Resources
- [LYWSD02 Python Library](https://github.com/h4/lywsd02) - Original reverse engineering
- [Bluetooth LE GATT Specifications](https://www.bluetooth.com/specifications/gatt/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [CoreBluetooth Documentation](https://developer.apple.com/documentation/corebluetooth)

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** your changes (`git commit -m 'Add some AmazingFeature'`)
4. **Push** to the branch (`git push origin feature/AmazingFeature`)
5. **Open** a Pull Request

### Contribution Guidelines
- Follow existing code style
- Add tests for new features
- Update documentation
- Ensure all tests pass
- Keep PRs focused and atomic

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](./LICENSE) file for details.

```
MIT License

Copyright (c) 2021-2025 Rick Kerkhof and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

---

## 🙏 Acknowledgments

- **[Rick Kerkhof](https://github.com/rkerkhof)** — Original creator of [rkerkhof/LYWSD02-Clock-Sync](https://github.com/rkerkhof/LYWSD02-Clock-Sync), on which this fork is based
- **[h4/lywsd02](https://github.com/h4/lywsd02)** - Python library that reverse-engineered the LYWSD02 Bluetooth protocol
- **[Nicolas Seriot / BinUtils](https://github.com/nst/BinUtils)** - Python `struct`-like binary packing utility used in `BinUtils.swift` (MIT License)
- **Xiaomi** - For creating the LYWSD02 sensor
- **Community contributors** - For bug reports and improvements

---

## 📞 Support

### Getting Help

- 📖 Check the [documentation](./ARCHITECTURE.md)
- 🐛 Report bugs via [GitHub Issues](https://github.com/yourusername/LYWSD02-Clock-Sync/issues)
- 💬 Ask questions in [Discussions](https://github.com/yourusername/LYWSD02-Clock-Sync/discussions)

### Reporting Bugs

When reporting bugs, please include:
- iOS/macOS version
- Device model (iPhone, Mac, etc.)
- LYWSD02 firmware version (if known)
- Steps to reproduce
- Expected vs actual behavior
- Screenshots/logs if applicable

---

## 🔐 Security

### Reporting Security Issues

**DO NOT** create public GitHub issues for security vulnerabilities.

Instead, open a private [GitHub Security Advisory](https://github.com/yourusername/LYWSD02-Clock-Sync/security/advisories/new) in this repository.

### Security Best Practices

- The app does not transmit data to external servers
- All Bluetooth communication is local
- No personal data is collected
- App runs in Apple's sandbox
- Regular security audits recommended

---

## 📊 Project Statistics

| Metric | Value |
|--------|-------|
| **Total Lines of Code** | ~1,800 |
| **Swift Files** | 12 |
| **Supported Platforms** | iOS 16+, macOS 13+ |
| **Dependencies** | 0 (system frameworks only) |
| **First Release** | November 2021 |
| **Latest Update** | November 2025 |

---

## 🌟 Star History

If you find this project useful, please consider giving it a ⭐!

[![Star History Chart](https://api.star-history.com/svg?repos=yourusername/LYWSD02-Clock-Sync&type=Date)](https://star-history.com/#yourusername/LYWSD02-Clock-Sync&Date)

---

**Made with ❤️ for the LYWSD02 community**


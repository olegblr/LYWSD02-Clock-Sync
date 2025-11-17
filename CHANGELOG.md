# Changelog

All notable changes to LYWSD02 Clock Sync will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Connection timeout implementation
- Background mode support
- Multiple device support
- Export history to CSV
- Widget support (iOS/macOS)
- Cloud sync capabilities
- Localization (i18n)

---

## [1.0.0] - 2025-11-17

### Added - Major Documentation & Code Review Release
- 📚 **Comprehensive Documentation Suite**
  - Complete README.md with features, usage, and screenshots
  - Detailed API_DOCUMENTATION.md with all public APIs
  - ARCHITECTURE.md explaining system design
  - CONTRIBUTING.md with development guidelines
  - CODE_REVIEW_REPORT.md - external audit findings
  - LICENSE (MIT)

- 🔍 **Code Quality Improvements**
  - Added `LYWSD02Constants.swift` for centralized configuration
  - Improved error handling with `BLEError` enum
  - Enhanced logging throughout the application
  - Better input validation in critical paths

- ✨ **Features**
  - Auto-reconnection with exponential backoff (1s, 2s, 4s)
  - Peripheral caching for O(1) lookup performance
  - Auto time sync on device connection (200ms delay)
  - History fetching with progress indication
  - Battery, temperature, and humidity monitoring
  - Interactive Charts (iOS 16+, macOS 13+)

- 🛡️ **Security**
  - Input validation for sensor data ranges
  - Timezone offset validation
  - Data bounds checking improvements
  - Error recovery mechanisms

### Changed
- Migrated to Swift 5.9+ concurrency model (@MainActor)
- Improved SwiftUI views with better composition
- Enhanced Bluetooth delegate handling
- Optimized characteristic discovery flow

### Fixed
- Race conditions in device discovery
- Memory leaks in Task closures
- Duplicate device entries in discovery list
- Auto-sync timing issues

### Security
- Added validation for temperature range (-40°C to 80°C)
- Added validation for humidity range (0% to 100%)
- Added validation for timezone offset (-12 to +14 hours)
- Improved error handling to prevent crashes on malformed data

---

## [0.9.0] - 2021-11-06

### Added - Beta Release
- Initial Bluetooth Low Energy implementation
- Device discovery and connection
- Time synchronization feature
- Battery level monitoring
- Temperature and humidity readings
- Basic history support
- iOS and macOS targets

### Implementation
- SwiftUI-based user interface
- CoreBluetooth framework integration
- Binary data packing/unpacking (Python struct-like)
- LYWSD02 protocol reverse-engineering implementation

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| **1.0.0** | 2025-11-17 | Documentation release + improvements |
| **0.9.0** | 2021-11-06 | Initial beta release |

---

## Migration Guides

### Migrating to 1.0.0

#### For Users
No breaking changes. The app will work as before with enhanced stability.

#### For Developers

**New Error Handling:**
```swift
// Old (0.9.0)
func syncTime(target: Date) {
    // No error handling
}

// New (1.0.0)
func syncTime(target: Date) throws {
    guard hasTimeSupport else {
        throw BLEError.characteristicNotFound
    }
    // ... validation and error handling
}
```

**New Constants:**
```swift
// Old (0.9.0)
let timeout = 10.0
let delay = 0.2

// New (1.0.0)
import LYWSD02Constants

let timeout = LYWSD02Constants.connectionTimeout
let delay = LYWSD02Constants.autoSyncDelay
```

**Actor Isolation:**
```swift
// All ViewModels now isolated to @MainActor
@MainActor
class BLEClient: ObservableObject {
    // ...
}
```

---

## Deprecated Features

### Version 0.9.0
- None

### Version 1.0.0
- None yet (first stable release)

---

## Breaking Changes

### Version 1.0.0
- ⚠️ Minimum iOS version: 16.0 (was 14.0)
- ⚠️ Minimum macOS version: 13.0 (was 11.0)
- ⚠️ Swift 5.9+ required (uses @MainActor)

**Rationale:** Modern concurrency features and SwiftUI improvements

---

## Known Issues

### Version 1.0.0
- [ ] No connection timeout implementation ([#issue])
- [ ] History fetch can be slow for large datasets
- [ ] No background mode support
- [ ] Limited error messages in UI

See [CODE_REVIEW_REPORT.md](./CODE_REVIEW_REPORT.md) for complete issue list.

---

## Contributors

### Version 1.0.0
- Rick Kerkhof - Original author
- External Auditor - Code review and documentation
- Community contributors

### Version 0.9.0
- Rick Kerkhof - Initial implementation

---

## Acknowledgments

Special thanks to:
- [h4/lywsd02](https://github.com/h4/lywsd02) - Python library for protocol reverse-engineering
- Apple Developer Forums community
- Beta testers

---

## Links

- [Repository](https://github.com/yourusername/LYWSD02-Clock-Sync)
- [Issue Tracker](https://github.com/yourusername/LYWSD02-Clock-Sync/issues)
- [Discussions](https://github.com/yourusername/LYWSD02-Clock-Sync/discussions)
- [Documentation](./README.md)

---

**Note:** All dates in YYYY-MM-DD format.

[Unreleased]: https://github.com/yourusername/LYWSD02-Clock-Sync/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yourusername/LYWSD02-Clock-Sync/releases/tag/v1.0.0
[0.9.0]: https://github.com/yourusername/LYWSD02-Clock-Sync/releases/tag/v0.9.0

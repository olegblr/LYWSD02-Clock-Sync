# 🚀 Quick Start Guide
## LYWSD02 Clock Sync

**Get up and running in 5 minutes!**

---

## 📱 Installation

### iOS

1. **Download Xcode** (if not installed)
   ```bash
   # Install from Mac App Store or:
   xcode-select --install
   ```

2. **Clone Repository**
   ```bash
   git clone https://github.com/yourusername/LYWSD02-Clock-Sync.git
   cd LYWSD02-Clock-Sync
   ```

3. **Open Project**
   ```bash
   open "LYWSD02 Clock Sync.xcodeproj"
   ```

4. **Select iOS Target**
   - In Xcode, select `LYWSD02 Clock Sync (iOS)` scheme
   - Choose your device or simulator

5. **Run** (⌘R)
   - Grant Bluetooth permissions when prompted

### macOS

Same steps, but select `LYWSD02 Clock Sync (macOS)` scheme

---

## 🔧 First Use

### Step 1: Prepare Device
- ✅ Ensure LYWSD02 has battery
- ✅ Device should be within 10m range
- ✅ Remove protective film if new

### Step 2: Launch App
- App automatically starts scanning
- Wait 5-10 seconds for device discovery
- Device appears in list (e.g., "LYWSD02 ABC123")

### Step 3: Connect
- App auto-connects to first discovered device
- Connection takes 2-3 seconds
- Time automatically syncs on connection

### Step 4: View Data
You'll see:
- 🕐 **Device time** (large display)
- 🌡️ **Temperature** (in Celsius)
- 💧 **Humidity** (percentage)
- 🔋 **Battery** (percentage)

---

## ⏰ Syncing Time

### Automatic Sync
- Happens automatically on connection
- Delay: 200ms after successful connection
- Uses your phone/Mac current time

### Manual Sync
1. Tap the **clock display** or device time
2. (Optional) Adjust time in popover
3. Tap **"Sync Time"** button
4. Confirmation appears when complete

---

## 📊 Viewing History

1. **Scroll down** to History section
2. Tap **"Get History"** button
3. Wait for data download (5-10 seconds)
4. Use **segmented control** to filter:
   - Day
   - Week
   - Month
   - All

### Reading Charts
- **Blue line** = Minimum temperature
- **Red line** = Maximum temperature
- Tap data points for exact values

---

## 🔄 Reconnection

If device disconnects:
- App auto-reconnects (up to 3 attempts)
- Delays: 1s → 2s → 4s
- Manual reconnect: Close & reopen app

---

## 🐛 Troubleshooting

### Device Not Found
**Problem:** No devices appear after 30s

**Solutions:**
- ✅ Check device has battery
- ✅ Move closer to device (< 5m)
- ✅ Restart device (remove/reinsert battery)
- ✅ Check Bluetooth is enabled in Settings
- ✅ Tap "Retry Scan" button

---

### Connection Failed
**Problem:** "Connection timeout" or similar error

**Solutions:**
- ✅ Restart app
- ✅ Restart Bluetooth (Settings → Bluetooth → Off/On)
- ✅ Restart device
- ✅ Check device isn't connected to another app

---

### No Data Showing
**Problem:** Connected but no temperature/humidity

**Solutions:**
- ✅ Wait 5-10 seconds for initial data
- ✅ Tap sync button (if available)
- ✅ Disconnect and reconnect
- ✅ Check device firmware is up to date

---

### Time Won't Sync
**Problem:** Sync button doesn't work

**Solutions:**
- ✅ Check device supports time sync (see capabilities)
- ✅ Ensure device is connected
- ✅ Try manual sync (tap clock → sync)
- ✅ Check timezone settings on phone/Mac

---

### History Empty
**Problem:** "Get History" returns no data

**Solutions:**
- ✅ Device may not have recorded data yet
- ✅ Wait a few hours for device to collect data
- ✅ Try fetching again
- ✅ Check device has been on (not in storage)

---

## 💡 Tips & Tricks

### Battery Life
- Device battery lasts 6-12 months
- Low battery (<20%) may affect Bluetooth range
- Replace with CR2032 battery

### Best Practices
- ✅ Keep app open for continuous updates
- ✅ Sync time periodically (once per month)
- ✅ Download history weekly for records
- ✅ Monitor battery level

### Optimal Placement
- **Indoor use** recommended
- Avoid direct sunlight
- Away from heat sources
- 1.5m above ground for best accuracy

### Data Updates
- Temperature/Humidity: **Real-time** (when connected)
- Battery: Updates on **sync**
- Time: Check via **manual sync**
- History: **On-demand** fetch

---

## 📱 UI Overview

### Main Screen (ContentView)
```
┌───────────────────────────────┐
│  Scanning for device…         │
│  [Progress Indicator]         │
│                               │
│  Searching…                   │
│  [ Retry Scan ]               │
└───────────────────────────────┘
```

### Device Screen (DeviceView)
```
┌───────────────────────────────┐
│  ⏰ 14:32:15                  │
│  💻 14:32:16 | ✓ Synced      │
│  🕐 Last sync: 14:30          │
├───────────────────────────────┤
│  🔋 Battery    🌡️ Temp  💧 Hum│
│     85%         22.5°C    65% │
├───────────────────────────────┤
│  Capabilities:                │
│  ✓ Time ✓ Battery ✓ Sensors  │
├───────────────────────────────┤
│  📊 History                   │
│  [Day|Week|Month|All]         │
│  [Temperature Chart]          │
│  [Humidity Chart]             │
└───────────────────────────────┘
```

---

## ⚙️ Settings & Configuration

### Permissions
Required permissions:
- ✅ **Bluetooth** - For device communication
- ✅ **Local Network** (iOS 14+) - For BLE

Grant in: **Settings → LYWSD02 Clock Sync → Bluetooth**

### App Preferences
Currently no in-app settings. Configuration via code:

Edit `LYWSD02Constants.swift`:
```swift
enum LYWSD02Constants {
    static let autoSyncDelay: TimeInterval = 0.2  // Auto-sync delay
    static let connectionTimeout: TimeInterval = 10.0  // Connection timeout
    static let maxReconnectionAttempts = 3  // Reconnect attempts
}
```

---

## 📚 Learn More

- **Full Documentation:** [README.md](./README.md)
- **API Reference:** [API_DOCUMENTATION.md](./API_DOCUMENTATION.md)
- **Architecture:** [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Contributing:** [CONTRIBUTING.md](./CONTRIBUTING.md)

---

## 🆘 Getting Help

### Common Questions

**Q: Does it work offline?**  
A: Yes! No internet needed. Bluetooth only.

**Q: Can I connect multiple devices?**  
A: Not yet. Currently one device at a time.

**Q: Does it run in background?**  
A: No. App must be in foreground for updates.

**Q: Is my data sent anywhere?**  
A: No. Everything stays on your device.

**Q: What's the range?**  
A: Typically 5-10m indoors, up to 30m outdoors.

### Still Need Help?

- 🐛 Report bugs: [GitHub Issues](https://github.com/yourusername/LYWSD02-Clock-Sync/issues)
- 💬 Ask questions: [GitHub Discussions](https://github.com/yourusername/LYWSD02-Clock-Sync/discussions)
- 📧 Email: support@example.com

---

## 🎉 You're All Set!

Enjoy using LYWSD02 Clock Sync!

**Next Steps:**
- ⭐ Star the repository if you find it useful
- 📢 Share with friends who have LYWSD02 devices
- 🤝 Contribute improvements (see [CONTRIBUTING.md](./CONTRIBUTING.md))

---

**Last Updated:** November 17, 2025  
**App Version:** 1.0.0

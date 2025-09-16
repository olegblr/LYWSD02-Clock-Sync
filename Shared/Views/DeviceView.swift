//  DeviceView.swift
//  LYWSD02 Clock Sync (macOS)
//
//  Created by Rick Kerkhof on 05/11/2021.
//

import CoreBluetooth
import SwiftUI
import Combine
#if canImport(Charts)
import Charts
#endif

struct DeviceView: View {
    @EnvironmentObject var bleClient: BLEClient
    @ObservedObject var peripheral: BLEDeviceModel
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isPopoverPresented = false
    @State private var targetDate = Date()
    @State private var localTime = Date()
    @State private var historyRange: HistoryRange = .day
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: true) {
                VStack(spacing: 28) {
                    headerCard
                    readingsAndCapabilities(width: geo.size.width)
                    if peripheral.hasHistorySupport { historySection }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, idealHorizontalPadding(for: geo.size.width))
                .frame(maxWidth: 1400)
                .centeredInScroll()
            }
            .background(appBackground.ignoresSafeArea())
        }
        .navigationTitle(peripheral.name)
        .toolbar { ToolbarItem(placement: .automatic) { connectionStatus } }
        .onAppear { bleClient.connect(to: peripheral); autoLoadHistoryIfNeeded(); localTime = Date() }
        .onDisappear { bleClient.disconnect(peripheral) }
        .onReceive(timer) { _ in peripheral.sync(); localTime = Date() }
        .popover(isPresented: $isPopoverPresented) { timeAdjustPopover }
    }
}

// MARK: - Header
private extension DeviceView {
    var headerCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let time = peripheral.currentTime {
                    Text(time, style: .time)
                        .font(.system(size: 72, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .onTapGesture { isPopoverPresented = true }
                        .accessibilityLabel("Device time")
                } else {
                    ProgressView().scaleEffect(1.2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            HStack(spacing: 16) {
                Label { Text(localTime, style: .time) } icon: { Image(systemName: "desktopcomputer") }
                    .font(.callout.monospacedDigit())
                if let dev = peripheral.currentTime { timeDriftView(device: dev) }
                if let autoSyncAt = peripheral.lastAutoTimeSyncAt { autoSyncBadge(autoSyncAt) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .glassBackground()
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: peripheral.currentTime)
        .accessibilityElement(children: .contain)
    }
    
    func timeDriftView(device: Date) -> some View {
        let driftSeconds = Int(device.timeIntervalSince(localTime))
        let formatted = driftString(seconds: driftSeconds)
        return HStack(spacing: 4) {
            Image(systemName: abs(driftSeconds) < 2 ? "checkmark.circle" : "exclamationmark.triangle")
            Text(formatted)
        }
        .foregroundColor(abs(driftSeconds) < 2 ? .secondary : .orange)
        .font(.caption.monospacedDigit())
        .accessibilityLabel("Time drift \(formatted)")
    }
    
    func autoSyncBadge(_ date: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.checkmark")
            Text(date, style: .time)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Last automatic sync at \(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))")
    }
    
    func driftString(seconds: Int) -> String {
        let s = abs(seconds)
        if s < 2 { return "Synced" }
        let sign = seconds > 0 ? "+" : "-"
        return "Drift: \(sign)\(s)s"
    }
}

// MARK: - Readings & Capabilities
private extension DeviceView {
    @ViewBuilder
    func readingsAndCapabilities(width: CGFloat) -> some View {
        let multiColumn = width > 1000
        Group {
            if multiColumn {
                HStack(alignment: .top, spacing: 28) {
                    readingsCard.flexPriority()
                    capabilitiesCard.frame(maxWidth: 320)
                }
            } else {
                VStack(spacing: 28) {
                    readingsCard
                    capabilitiesCard
                }
            }
        }
    }
    
    var readingsCard: some View {
        VStack(spacing: 20) {
            HStack(spacing: 18) {
                metricTile(title: "Battery", value: batteryValue, systemImage: "battery.100", tint: .green)
                metricTile(title: "Temp", value: temperatureValue, systemImage: "thermometer.medium", tint: .blue)
                metricTile(title: "Humidity", value: humidityValue, systemImage: "drop", tint: .teal)
            }
            .frame(maxWidth: .infinity)
            liveSensorFooter
        }
        .padding(24)
        .glassBackground()
    }
    
    var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capabilities")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 4)
            capabilityChip("Time", ok: peripheral.hasTimeSupport, symbol: "clock")
            capabilityChip("Battery", ok: peripheral.hasBatterySupport, symbol: "battery.100")
            capabilityChip("Temperature", ok: peripheral.hasTemperatureSupport, symbol: "thermometer.medium")
            capabilityChip("Humidity", ok: peripheral.hasHumiditySupport, symbol: "drop")
            capabilityChip("History", ok: peripheral.hasHistorySupport, symbol: "clock.arrow.circlepath")
        }
        .padding(20)
        .glassBackground()
        .accessibilityElement(children: .contain)
    }
    
    var liveSensorFooter: some View {
        HStack(spacing: 12) {
            if peripheral.currentTemperature != nil || peripheral.currentHumidity != nil {
                Circle().fill(gradientAccent).frame(width: 8, height: 8).shadow(radius: 3)
                Text("Live updating")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().scaleEffect(0.6)
                Text("Waiting for sensor data...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { peripheral.fetchHistory() } label: { Label("Get history", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .font(.caption)
                .opacity(peripheral.hasHistorySupport ? 1 : 0)
                .disabled(!peripheral.hasHistorySupport || peripheral.isFetchingHistory)
        }
        .padding(.top, 8)
    }
    
    func capabilityChip(_ title: String, ok: Bool, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? symbol : "questionmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ok ? Color.accentColor : .secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.15)))
    }
    
    func metricTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(tint.gradient)
                .frame(height: 30)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.15)))
    }
}

// MARK: - History
private extension DeviceView {
    var historySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("History")
                    .font(.title3.weight(.semibold))
                Spacer()
                if peripheral.isFetchingHistory { ProgressView().controlSize(.small) }
            }
            .padding(.bottom, 4)
            
            if peripheral.history.isEmpty {
                VStack(spacing: 14) {
                    Text("No history loaded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        peripheral.fetchHistory()
                    } label: { Label("Get history", systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .controlSize(.small)
                        .disabled(peripheral.isFetchingHistory)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Picker("Range", selection: $historyRange) {
                    ForEach(HistoryRange.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)
                let records = filteredHistory(peripheral.history)
                if records.isEmpty {
                    Text("No data in selected range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    charts(records: records)
                }
                footerStats
            }
        }
        .padding(24)
        .glassBackground()
        .animation(.easeInOut(duration: 0.25), value: peripheral.history.count)
    }
    
    @ViewBuilder
    func charts(records: [BLEDeviceModel.HistoryRecord]) -> some View {
        #if canImport(Charts)
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Temperature (°C)").font(.subheadline.weight(.semibold))
                Chart(records.sorted { $0.timestamp < $1.timestamp }) { rec in
                    LineMark(x: .value("Time", rec.timestamp), y: .value("Min", rec.minTemperature)).foregroundStyle(Color.blue.opacity(0.7))
                    LineMark(x: .value("Time", rec.timestamp), y: .value("Max", rec.maxTemperature)).foregroundStyle(Color.red.opacity(0.8))
                }
                .frame(height: 160)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Humidity (%)").font(.subheadline.weight(.semibold))
                Chart(records.sorted { $0.timestamp < $1.timestamp }) { rec in
                    LineMark(x: .value("Time", rec.timestamp), y: .value("Min", rec.minHumidity)).foregroundStyle(Color.teal.opacity(0.7))
                    LineMark(x: .value("Time", rec.timestamp), y: .value("Max", rec.maxHumidity)).foregroundStyle(Color.green.opacity(0.8))
                }
                .frame(height: 160)
            }
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            ForEach(records.sorted { $0.timestamp < $1.timestamp }) { rec in
                HStack(spacing: 12) {
                    Text(rec.timestamp, style: .time).monospacedDigit().frame(width: 70, alignment: .leading)
                    Text(String(format: "%.1f–%.1f°C", rec.minTemperature, rec.maxTemperature))
                    Spacer()
                    Text("\(rec.minHumidity)–\(rec.maxHumidity)%")
                        .foregroundStyle(.teal)
                }
                .font(.caption2)
            }
        }
        #endif
    }
    
    var footerStats: some View {
        HStack(spacing: 16) {
            if let current = peripheral.currentHistoryRecords { Text("Records loaded: \(peripheral.history.count)/\(current)").font(.caption2).foregroundStyle(.secondary) }
            else { Text("Records: \(peripheral.history.count)").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Button { peripheral.fetchHistory() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(peripheral.isFetchingHistory)
        }
        .padding(.top, 6)
    }
}

// MARK: - Helpers / Computed
private extension DeviceView {
    var batteryValue: String { peripheral.batteryPercentage.map { "\($0)%" } ?? "—" }
    var temperatureValue: String { peripheral.currentTemperature.map { String(format: "%.1f°C", $0) } ?? "—" }
    var humidityValue: String { peripheral.currentHumidity.map { "\($0)%" } ?? "—" }
    
    func autoLoadHistoryIfNeeded() { if peripheral.hasHistorySupport && peripheral.history.isEmpty && !peripheral.isFetchingHistory { peripheral.fetchHistory() } }
    
    func idealHorizontalPadding(for width: CGFloat) -> CGFloat { width > 1200 ? 80 : width > 800 ? 48 : 24 }
    
    var appBackground: some View {
        LinearGradient(colors: backgroundGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05))
    }
    
    var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color(red:0.10, green:0.12, blue:0.16), Color(red:0.05, green:0.06, blue:0.08)]
        } else {
            return [Color(red:0.94, green:0.96, blue:1.0), Color(red:0.88, green:0.92, blue:1.0)]
        }
    }
    
    var gradientAccent: LinearGradient { LinearGradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing) }
    
    var connectionStatus: some View {
        let isConnected = peripheral.peripheral.state == .connected
        return HStack(spacing: 6) {
            Circle().fill(isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : "Disconnected").font(.caption2).foregroundColor(.secondary)
        }
        .padding(6)
        .background(.thinMaterial, in: Capsule())
    }
    
    var timeAdjustPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust Time").font(.headline)
            DatePicker("", selection: $targetDate)
                .labelsHidden()
                .datePickerStyle(.graphical)
            HStack {
                Button { peripheral.syncTime(target: targetDate) } label: { Label("Set", systemImage: "clock.badge.checkmark") }
                    .buttonStyle(.borderedProminent)
                Button { peripheral.syncTime(target: Date()); targetDate = Date() } label: { Label("Now", systemImage: "clock.arrow.2.circlepath") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}

// MARK: - Range
private enum HistoryRange: CaseIterable { case day, threeDays, week, all; var label: String { switch self { case .day: return "24h"; case .threeDays: return "3d"; case .week: return "7d"; case .all: return "All" } } }

private extension DeviceView {
    func filteredHistory(_ history: [BLEDeviceModel.HistoryRecord]) -> [BLEDeviceModel.HistoryRecord] {
        guard let maxDate = history.map(\.timestamp).max() else { return [] }
        let cutoff: Date
        switch historyRange {
        case .day: cutoff = maxDate.addingTimeInterval(-24*3600)
        case .threeDays: cutoff = maxDate.addingTimeInterval(-3*24*3600)
        case .week: cutoff = maxDate.addingTimeInterval(-7*24*3600)
        case .all: return history
        }
        return history.filter { $0.timestamp >= cutoff }
    }
}

// MARK: - View Utilities
private extension View {
    func glassBackground(cornerRadius: CGFloat = 36) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 8)
    }
    func flexPriority() -> some View { self.layoutPriority(1) }
    func centeredInScroll() -> some View { self.frame(maxWidth: .infinity) }
}

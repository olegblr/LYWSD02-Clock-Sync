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
    
    @State var isPopoverPresented = false
    @State var targetDate = Date()
    @State private var localTime = Date() // Add local time state
    
    var columns: [GridItem] = [
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .leading),
    ]
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            if let time = peripheral.currentTime {
                Text(time, style: .time)
                    .font(.system(size: 64)) // Doubled from .largeTitle (32 points)
                    .padding()
                    .onTapGesture {
                        isPopoverPresented = true
                    }
                
                // Local laptop time display
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                    Text("Local time:")
                    Text(localTime, style: .time)
                }
                .font(.system(size: 18))
                .padding(.bottom, 8)
            }
            
            LazyVGrid(columns: columns) {
                if peripheral.hasBatterySupport {
                    // TODO: show appropriate icon for state
                    Image(systemName: "battery.100").frame(width: 30)
                    if let percent = peripheral.batteryPercentage {
                        Text(String(percent) + "%")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
                
                if peripheral.hasTemperatureSupport {
                    Image(systemName: "thermometer").frame(width: 30)
                    if let percent = peripheral.currentTemperature {
                        Text(String(percent) + " °C")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
                
                if peripheral.hasHumiditySupport {
                    Image(systemName: "drop").frame(width: 30)
                    if let percent = peripheral.currentHumidity {
                        Text(String(percent) + "%")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
            }
            
            GroupBox(label: Text("Discovered capabilities").font(.system(size: 28))) { // Adjusted font size
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: peripheral.hasTimeSupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read & write time").font(.system(size: 24)) // Adjusted font size
                    }
            
                    HStack {
                        Image(systemName: peripheral.hasBatterySupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read battery status").font(.system(size: 24)) // Adjusted font size
                    }
                
                    HStack {
                        Image(systemName: peripheral.hasTemperatureSupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read temperature").font(.system(size: 24)) // Adjusted font size
                    }
                
                    HStack {
                        Image(systemName: peripheral.hasHumiditySupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read humidity").font(.system(size: 24)) // Adjusted font size
                    }
                }.padding()
            }.padding()
            if let autoSyncAt = peripheral.lastAutoTimeSyncAt { // NEW status line
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.checkmark")
                    Text("Time auto-synced at ") + Text(autoSyncAt, style: .time)
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
            // History Section
            if peripheral.hasHistorySupport {
                GroupBox(label: Text("History").font(.system(size: 24))) {
                    VStack(alignment: .leading, spacing: 12) {
                        if peripheral.isFetchingHistory {
                            HStack {
                                ProgressView()
                                Text("Fetching history...")
                            }
                        } else if peripheral.history.isEmpty {
                            Button {
                                peripheral.fetchHistory()
                            } label: {
                                Label("Load History", systemImage: "arrow.down.circle")
                            }
                        } else {
                            #if canImport(Charts)
                            Chart(peripheral.history.sorted { $0.timestamp < $1.timestamp }) { rec in
                                LineMark(
                                    x: .value("Time", rec.timestamp),
                                    y: .value("Min °C", rec.minTemperature)
                                ).foregroundStyle(.blue)
                                LineMark(
                                    x: .value("Time", rec.timestamp),
                                    y: .value("Max °C", rec.maxTemperature)
                                ).foregroundStyle(.red)
                                // Humidity as area / bar alternative
                                AreaMark(
                                    x: .value("Time", rec.timestamp),
                                    y: .value("Humidity %", rec.maxHumidity)
                                ).foregroundStyle(.green.opacity(0.15))
                            }
                            .frame(height: 220)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5))
                            }
                            .chartYAxis {
                                AxisMarks()
                            }
                            #else
                            // Fallback simple list if Charts not available
                            VStack(alignment: .leading) {
                                ForEach(peripheral.history.sorted { $0.timestamp < $1.timestamp }) { rec in
                                    HStack {
                                        Text(rec.timestamp, style: .time).monospacedDigit()
                                        Spacer()
                                        Text(String(format: "%.1f–%.1f °C", rec.minTemperature, rec.maxTemperature))
                                        Text("H: \(rec.minHumidity)–\(rec.maxHumidity)%")
                                    }.font(.caption)
                                }
                            }.frame(maxHeight: 220)
                            #endif
                            HStack(spacing: 16) {
                                if let total = peripheral.totalHistoryRecords, let current = peripheral.currentHistoryRecords {
                                    Text("Records: \(peripheral.history.count)/\(current) (total: \(total))")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button { peripheral.fetchHistory() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                                    .controlSize(.small)
                            }
                        }
                    }.padding(.top, 4)
                }.padding(.top)
            }
        }
        .onAppear {
            bleClient.connect(to: peripheral)
        }.onDisappear {
            bleClient.disconnect(peripheral)
        }.popover(isPresented: $isPopoverPresented) {
            VStack {
                HStack {
                    DatePicker("", selection: $targetDate)
                        .labelsHidden()
                
                    Button {
                        peripheral.syncTime(target: targetDate)
                    } label: {
                        Image(systemName: "clock.badge.checkmark")
                        Text("Set this time").font(.system(size: 24)) // Adjusted font size
                    }
                }.padding()
                Button {
                    peripheral.syncTime(target: Date())
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                    Text("Sync with device").font(.system(size: 24)) // Adjusted font size
                }
            }.padding()
        }
        .navigationTitle(peripheral.name) // Removed .font modifier from navigationTitle
        .onReceive(timer) { _ in
            peripheral.sync()
            localTime = Date() // update local time every tick
        }
        .onAppear {
            // Auto-load history on first appearance if supported and empty
            if peripheral.hasHistorySupport && peripheral.history.isEmpty && !peripheral.isFetchingHistory {
                peripheral.fetchHistory()
            }
        }
    }
}

// struct DeviceView_Previews: PreviewProvider {
//    static var previews: some View {
//        DeviceView(peripheral: BLEDeviceModel())
//    }
// }

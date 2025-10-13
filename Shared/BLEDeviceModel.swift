//
//  BLEDevicePeripheral.swift
//  LYWSD02 Clock Sync (macOS)
//
//  Created by Rick Kerkhof on 06/11/2021.
//

import Foundation
import CoreBluetooth
import os.log

@MainActor
final class BLEDeviceModel: NSObject, ObservableObject, CBPeripheralDelegate {
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
    // One-time auto time sync guard per connection
    private var autoTimeSynced = false
    // Record when an automatic time sync happened
    @Published private(set) var lastAutoTimeSyncAt: Date? = nil
    // History support
    struct HistoryRecord: Identifiable {
        let id: Int // index from device
        let timestamp: Date
        let minTemperature: Double
        let minHumidity: Int
        let maxTemperature: Double
        let maxHumidity: Int
    }
    @Published private(set) var history: [HistoryRecord] = []
    @Published private(set) var totalHistoryRecords: Int? = nil
    @Published private(set) var currentHistoryRecords: Int? = nil
    @Published private(set) var isFetchingHistory = false
    @Published private(set) var hasHistorySupport = false
    private var historyNotificationActive = false
    
    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "Device")
    
    // MARK: Wrappers for CBPeripheral fields.
    var identifier: String { peripheral.identifier.uuidString }
    var peripheral: CBPeripheral { self._peripheral }
    
    required init(_ peripheral: CBPeripheral) {
        self._peripheral = peripheral
        self.name = peripheral.name ?? "Unknown name"
        super.init()
        peripheral.delegate = self
    }
    
    func sync() {
        // Keep last known values instead of clearing them
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }) else {
            logger.warning("Data service not found for sync")
            return
        }
        
        if hasTimeSupport {
            if let timeCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.cbuuid }) {
                peripheral.readValue(for: timeCharacteristic)
            }
        }
        
        if hasBatterySupport {
            if let batteryCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Battery.cbuuid }) {
                peripheral.readValue(for: batteryCharacteristic)
            }
        }
    }
    
    func syncTime(target: Date) {
        guard hasTimeSupport else {
            logger.warning("Attempted to sync time without time support")
            return
        }
        
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }) else {
            logger.error("Data service not found")
            return
        }
        
        guard let timeCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.cbuuid }) else {
            logger.error("Time characteristic not found")
            return
        }
        
        let timezone = TimeZone.current
        let time = Time(timestamp: Int(target.timeIntervalSince1970), timezoneOffset: timezone.secondsFromGMT() / 3600)
        
        peripheral.writeValue(time.data(), for: timeCharacteristic, type: .withResponse)
        logger.info("Writing time to device")
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Task { @MainActor in
                logger.error("Failed to write value: \(error.localizedDescription)")
            }
            return
        }
        
        Task { @MainActor in
            self.sync()
        }
    }
    
    nonisolated func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        Task { @MainActor in
            self.name = peripheral.name ?? "Unknown name"
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Task { @MainActor in
                logger.error("Error discovering services: \(error.localizedDescription)")
            }
            return
        }
        
        guard let services = peripheral.services else {
            Task { @MainActor in
                logger.warning("No services found")
            }
            return
        }
        
        for service in services {
            if service.uuid == LYWSD02UUID.Service.Data.cbuuid {
                Task { @MainActor in
                    logger.info("Found data service, discovering characteristics")
                }
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func fetchHistory() {
        guard hasHistorySupport else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }) else { return }
        guard let historyChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.History.cbuuid }),
              let recordIndexChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.RecordIndex.cbuuid }),
              let numRecordsChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.NumRecords.cbuuid }) else { return }
        
        peripheral.readValue(for: numRecordsChar)
        
        if !historyNotificationActive {
            peripheral.setNotifyValue(true, for: historyChar)
            historyNotificationActive = true
        }
        
        history.removeAll()
        isFetchingHistory = true
        
        // Use withUnsafeBytes for safer data construction
        withUnsafeBytes(of: UInt32(0).littleEndian) { bytes in
            let data = Data(bytes)
            peripheral.writeValue(data, for: recordIndexChar, type: .withResponse)
        }
        logger.info("Fetching history records")
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Task { @MainActor in
                logger.error("Error discovering characteristics: \(error.localizedDescription)")
            }
            return
        }
        
        guard let characteristics = service.characteristics else {
            Task { @MainActor in
                logger.warning("No characteristics found")
            }
            return
        }
        
        Task { @MainActor in
            logger.info("Discovered \(characteristics.count) characteristics")
            
            for characteristic in characteristics {
                if characteristic.uuid == LYWSD02UUID.Characteristic.Time.cbuuid {
                    logger.info("Time support available")
                    self.hasTimeSupport = true
                    if !self.autoTimeSynced {
                        self.autoTimeSynced = true
                        let scheduledAt = Date()
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                            self.syncTime(target: scheduledAt)
                            self.lastAutoTimeSyncAt = Date()
                        }
                    }
                }
                
                if characteristic.uuid == LYWSD02UUID.Characteristic.Battery.cbuuid {
                    logger.info("Battery support available")
                    self.hasBatterySupport = true
                }
                
                if characteristic.uuid == LYWSD02UUID.Characteristic.SensorData.cbuuid {
                    logger.info("Sensor data support available")
                    peripheral.setNotifyValue(true, for: characteristic)
                    self.hasTemperatureSupport = true
                    self.hasHumiditySupport = true
                }
                
                if characteristic.uuid == LYWSD02UUID.Characteristic.History.cbuuid {
                    self.hasHistorySupport = true
                }
                if characteristic.uuid == LYWSD02UUID.Characteristic.NumRecords.cbuuid {
                    self.hasHistorySupport = true
                }
                if characteristic.uuid == LYWSD02UUID.Characteristic.RecordIndex.cbuuid {
                    self.hasHistorySupport = true
                }
            }
            
            self.sync()
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Task { @MainActor in
                logger.error("Error updating value: \(error.localizedDescription)")
            }
            return
        }
        
        guard let data = characteristic.value else {
            Task { @MainActor in
                logger.warning("No data received for characteristic \(characteristic.uuid)")
            }
            return
        }
        
        Task { @MainActor in
            await self.handleCharacteristicUpdate(characteristic: characteristic, data: data)
        }
    }
    
    private func handleCharacteristicUpdate(characteristic: CBCharacteristic, data: Data) async {
        switch characteristic.uuid {
        case LYWSD02UUID.Characteristic.Time.cbuuid:
            do {
                let unpacked = try unpack("<Ib", data)
                guard let timestamp = unpacked[0] as? Int else {
                    logger.error("Invalid time data type")
                    return
                }
                self.currentTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
                logger.debug("Updated time: \(self.currentTime?.description ?? "nil")")
            } catch {
                logger.error("Error unpacking time data: \(error.localizedDescription)")
            }
            
        case LYWSD02UUID.Characteristic.Battery.cbuuid:
            if let firstByte = data.first, firstByte <= 100 {
                self.batteryPercentage = Int(firstByte)
                logger.debug("Battery: \(firstByte)%")
            } else {
                logger.warning("Invalid battery value: \(data.first ?? 0)")
            }
            
        case LYWSD02UUID.Characteristic.SensorData.cbuuid:
            do {
                let unpacked = try unpack("<hB", data)
                guard let tempRaw = unpacked[0] as? Int,
                      let humidity = unpacked[1] as? Int else {
                    logger.error("Invalid sensor data types")
                    return
                }
                let temperature = Double(tempRaw) / 100.0
                // Validate reasonable ranges
                if (-40...80).contains(temperature) && (0...100).contains(humidity) {
                    self.currentTemperature = temperature
                    self.currentHumidity = humidity
                    logger.debug("Sensor: \(temperature)°C, \(humidity)%")
                } else {
                    logger.warning("Sensor values out of range: \(temperature)°C, \(humidity)%")
                }
            } catch {
                logger.error("Error unpacking sensor data: \(error.localizedDescription)")
            }
            
        case LYWSD02UUID.Characteristic.NumRecords.cbuuid:
            if data.count == 8 {
                let total = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
                let current = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
                self.totalHistoryRecords = Int(total)
                self.currentHistoryRecords = Int(current)
                logger.info("History records: \(current)/\(total)")
            }
            
        case LYWSD02UUID.Characteristic.History.cbuuid:
            if data.count == 14 {
                do {
                    let unpacked = try unpack("<IIhBhB", data)
                    guard let idx = unpacked[0] as? Int,
                          let ts = unpacked[1] as? Int,
                          let maxTempRaw = unpacked[2] as? Int,
                          let maxHum = unpacked[3] as? Int,
                          let minTempRaw = unpacked[4] as? Int,
                          let minHum = unpacked[5] as? Int else {
                        logger.error("Invalid history data types")
                        return
                    }
                    
                    let rec = HistoryRecord(
                        id: idx,
                        timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                        minTemperature: Double(minTempRaw) / 100.0,
                        minHumidity: minHum,
                        maxTemperature: Double(maxTempRaw) / 100.0,
                        maxHumidity: maxHum
                    )
                    self.history.append(rec)
                    
                    if let expected = self.currentHistoryRecords, self.history.count >= expected {
                        self.isFetchingHistory = false
                        logger.info("History fetch complete: \(self.history.count) records")
                    }
                } catch {
                    logger.error("Error unpacking history data: \(error.localizedDescription)")
                }
            }
            
        default:
            logger.debug("Unknown characteristic updated: \(characteristic.uuid)")
        }
    }
}

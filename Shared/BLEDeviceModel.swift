//
//  BLEDevicePeripheral.swift
//  LYWSD02 Clock Sync (macOS)
//
//  Created by Rick Kerkhof on 06/11/2021.
//

import Foundation
import CoreBluetooth
import os.log

/// All `CBPeripheralDelegate` callbacks arrive on the main thread because the
/// owning `CBCentralManager` was created with `queue: nil`. We bridge non-`Sendable`
/// CoreBluetooth values across the actor boundary using `UncheckedSendableBox`
/// and then enter `MainActor` via `assumeIsolated`.
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
    @Published private(set) var connectionState: CBPeripheralState = .disconnected

    private var _peripheral: CBPeripheral

    private var autoTimeSynced = false
    private var autoSyncTask: Task<Void, Never>?

    @Published private(set) var lastAutoTimeSyncAt: Date? = nil

    struct HistoryRecord: Identifiable, Hashable {
        let id: Int
        let timestamp: Date
        let minTemperature: Double
        let minHumidity: Int
        let maxTemperature: Double
        let maxHumidity: Int
    }
    @Published private(set) var history: [HistoryRecord] = []
    private var historyIDs: Set<Int> = []
    @Published private(set) var totalHistoryRecords: Int? = nil
    @Published private(set) var currentHistoryRecords: Int? = nil
    @Published private(set) var isFetchingHistory = false
    @Published private(set) var hasHistorySupport = false
    private var historyNotificationActive = false

    private let logger = Logger(subsystem: "com.lywsd02.clocksync", category: "Device")

    var identifier: String { peripheral.identifier.uuidString }
    var peripheral: CBPeripheral { self._peripheral }

    required init(_ peripheral: CBPeripheral) {
        self._peripheral = peripheral
        self.name = peripheral.name ?? "Unknown name"
        self.connectionState = peripheral.state
        super.init()
        peripheral.delegate = self
    }

    // MARK: - State management (called by BLEClient)

    func updateConnectionState(_ state: CBPeripheralState) {
        self.connectionState = state
        if state == .disconnected {
            handleDisconnection()
        }
    }

    func handleDisconnection() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        autoTimeSynced = false
        historyNotificationActive = false
        isFetchingHistory = false
    }

    // MARK: - Sync

    func sync() {
        guard peripheral.state == .connected else {
            logger.debug("sync() skipped: not connected")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }) else {
            logger.warning("Data service not found for sync")
            return
        }

        if hasTimeSupport,
           let timeChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.cbuuid }) {
            peripheral.readValue(for: timeChar)
        }

        if hasBatterySupport,
           let batteryChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Battery.cbuuid }) {
            peripheral.readValue(for: batteryChar)
        }
    }

    func syncTime(target: Date) throws {
        guard hasTimeSupport else { throw BLEError.characteristicNotFound }
        guard peripheral.state == .connected else {
            throw BLEError.invalidData(reason: "Device not connected")
        }

        let now = Date()
        let validRange = now.addingTimeInterval(LYWSD02Constants.Ranges.syncTimePastSeconds)
            ... now.addingTimeInterval(LYWSD02Constants.Ranges.syncTimeFutureSeconds)
        guard validRange.contains(target) else {
            throw BLEError.invalidData(reason: "Time out of valid range")
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }),
              let timeChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.cbuuid }) else {
            throw BLEError.characteristicNotFound
        }

        let offsetHours = TimeZone.current.secondsFromGMT() / 3600
        guard LYWSD02Constants.Ranges.timezoneOffset.contains(offsetHours) else {
            throw BLEError.invalidData(reason: "Invalid timezone offset: \(offsetHours)")
        }

        let time = Time(timestamp: Int(target.timeIntervalSince1970), timezoneOffset: offsetHours)
        peripheral.writeValue(time.data(), for: timeChar, type: .withResponse)

        logger.info("Writing time to device: \(target, privacy: .public)")
    }

    private func scheduleAutoTimeSync() {
        guard !autoTimeSynced else { return }
        autoTimeSynced = true

        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(LYWSD02Constants.autoSyncDelay * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            guard self.peripheral.state == .connected else {
                self.logger.warning("Auto-sync skipped: device disconnected")
                return
            }
            do {
                try self.syncTime(target: Date())
                self.lastAutoTimeSyncAt = Date()
                self.logger.info("Auto time sync completed")
            } catch {
                self.logger.error("Auto-sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - History

    func fetchHistory() {
        guard hasHistorySupport, peripheral.state == .connected else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.cbuuid }),
              let historyChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.History.cbuuid }),
              let recordIndexChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.RecordIndex.cbuuid }),
              let numRecordsChar = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.NumRecords.cbuuid })
        else { return }

        peripheral.readValue(for: numRecordsChar)

        if !historyNotificationActive {
            peripheral.setNotifyValue(true, for: historyChar)
            historyNotificationActive = true
        }

        history.removeAll()
        historyIDs.removeAll()
        isFetchingHistory = true

        var startIndex = UInt32(0).littleEndian
        let data = withUnsafeBytes(of: &startIndex) { Data($0) }
        peripheral.writeValue(data, for: recordIndexChar, type: .withResponse)
        logger.info("Fetching history records")
    }

    // MARK: - CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let errBox = UncheckedSendableBox(error)
        MainActor.assumeIsolated {
            if let error = errBox.value {
                self.logger.error("Failed to write value: \(error.localizedDescription, privacy: .public)")
                return
            }
            self.sync()
        }
    }

    nonisolated func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        let box = UncheckedSendableBox(peripheral)
        MainActor.assumeIsolated {
            self.name = box.value.name ?? "Unknown name"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let pBox = UncheckedSendableBox(peripheral)
        let errBox = UncheckedSendableBox(error)
        MainActor.assumeIsolated {
            let p = pBox.value
            if let error = errBox.value {
                self.logger.error("Error discovering services: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let services = p.services else {
                self.logger.warning("No services found")
                return
            }
            for service in services where service.uuid == LYWSD02UUID.Service.Data.cbuuid {
                self.logger.info("Found data service, discovering characteristics")
                p.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        let pBox = UncheckedSendableBox(peripheral)
        let sBox = UncheckedSendableBox(service)
        let errBox = UncheckedSendableBox(error)
        MainActor.assumeIsolated {
            let p = pBox.value
            let s = sBox.value
            if let error = errBox.value {
                self.logger.error("Error discovering characteristics: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let characteristics = s.characteristics else {
                self.logger.warning("No characteristics found")
                return
            }

            self.logger.info("Discovered \(characteristics.count, privacy: .public) characteristics")

            for characteristic in characteristics {
                switch characteristic.uuid {
                case LYWSD02UUID.Characteristic.Time.cbuuid:
                    self.hasTimeSupport = true
                    self.scheduleAutoTimeSync()
                case LYWSD02UUID.Characteristic.Battery.cbuuid:
                    self.hasBatterySupport = true
                case LYWSD02UUID.Characteristic.SensorData.cbuuid:
                    p.setNotifyValue(true, for: characteristic)
                    self.hasTemperatureSupport = true
                    self.hasHumiditySupport = true
                case LYWSD02UUID.Characteristic.History.cbuuid,
                     LYWSD02UUID.Characteristic.NumRecords.cbuuid,
                     LYWSD02UUID.Characteristic.RecordIndex.cbuuid:
                    self.hasHistorySupport = true
                default:
                    break
                }
            }
            self.sync()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let cBox = UncheckedSendableBox(characteristic)
        let errBox = UncheckedSendableBox(error)
        MainActor.assumeIsolated {
            let c = cBox.value
            if let error = errBox.value {
                self.logger.error("Error updating value: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let data = c.value else {
                self.logger.warning("No data received for characteristic")
                return
            }
            self.handleCharacteristicUpdate(uuid: c.uuid, data: data)
        }
    }

    private func handleCharacteristicUpdate(uuid: CBUUID, data: Data) {
        switch uuid {
        case LYWSD02UUID.Characteristic.Time.cbuuid:
            parseTime(data: data)
        case LYWSD02UUID.Characteristic.Battery.cbuuid:
            parseBattery(data: data)
        case LYWSD02UUID.Characteristic.SensorData.cbuuid:
            parseSensor(data: data)
        case LYWSD02UUID.Characteristic.NumRecords.cbuuid:
            parseNumRecords(data: data)
        case LYWSD02UUID.Characteristic.History.cbuuid:
            parseHistoryRecord(data: data)
        default:
            logger.debug("Unknown characteristic updated")
        }
    }

    // MARK: - Parsers

    private func parseTime(data: Data) {
        let format: String
        switch data.count {
        case LYWSD02Constants.timeDataSize: format = "<Ib"
        case LYWSD02Constants.timeDataSizeShort: format = "<I"
        default:
            logger.warning("Unexpected time data length: \(data.count, privacy: .public)")
            return
        }
        do {
            let unpacked = try unpack(format, data)
            guard let timestamp = unpacked.first as? Int else {
                logger.error("Invalid time data type")
                return
            }
            self.currentTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } catch {
            logger.error("Error unpacking time data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseBattery(data: Data) {
        guard let firstByte = data.first else { return }
        let value = Int(firstByte)
        guard LYWSD02Constants.Ranges.battery.contains(value) else {
            logger.warning("Invalid battery value: \(value, privacy: .public)")
            return
        }
        self.batteryPercentage = value
    }

    private func parseSensor(data: Data) {
        guard data.count >= LYWSD02Constants.sensorDataSize else { return }
        do {
            let unpacked = try unpack("<hB", data)
            guard let tempRaw = unpacked[0] as? Int,
                  let humidity = unpacked[1] as? Int else {
                logger.error("Invalid sensor data types")
                return
            }
            let temperature = Double(tempRaw) / LYWSD02Constants.temperatureScale
            guard LYWSD02Constants.Ranges.temperature.contains(temperature),
                  LYWSD02Constants.Ranges.humidity.contains(humidity) else {
                logger.warning("Sensor values out of range: \(temperature, privacy: .public)°C, \(humidity, privacy: .public)%")
                return
            }
            self.currentTemperature = temperature
            self.currentHumidity = humidity
        } catch {
            logger.error("Error unpacking sensor data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseNumRecords(data: Data) {
        guard data.count == LYWSD02Constants.numRecordsDataSize else { return }
        do {
            let unpacked = try unpack("<II", data)
            guard let total = unpacked[0] as? Int,
                  let current = unpacked[1] as? Int else { return }
            self.totalHistoryRecords = total
            self.currentHistoryRecords = current
            logger.info("History records: \(current, privacy: .public)/\(total, privacy: .public)")
        } catch {
            logger.error("Error unpacking num records: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseHistoryRecord(data: Data) {
        guard data.count == LYWSD02Constants.historyRecordSize else { return }
        guard history.count < LYWSD02Constants.maxHistoryRecords else {
            if isFetchingHistory {
                isFetchingHistory = false
                logger.warning("History fetch capped at \(LYWSD02Constants.maxHistoryRecords, privacy: .public) records")
            }
            return
        }
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

            guard !historyIDs.contains(idx) else { return }
            historyIDs.insert(idx)

            let rec = HistoryRecord(
                id: idx,
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                minTemperature: Double(minTempRaw) / LYWSD02Constants.temperatureScale,
                minHumidity: minHum,
                maxTemperature: Double(maxTempRaw) / LYWSD02Constants.temperatureScale,
                maxHumidity: maxHum
            )
            history.append(rec)

            if let expected = currentHistoryRecords, history.count >= expected {
                isFetchingHistory = false
                logger.info("History fetch complete: \(self.history.count, privacy: .public) records")
            }
        } catch {
            logger.error("Error unpacking history data: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        autoSyncTask?.cancel()
    }
}

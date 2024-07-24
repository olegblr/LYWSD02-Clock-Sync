//
//  BLEDevicePeripheral.swift
//  LYWSD02 Clock Sync (macOS)
//
//  Created by Rick Kerkhof on 06/11/2021.
//

import Foundation
import CoreBluetooth

class BLEDeviceModel: NSObject, ObservableObject, CBPeripheralDelegate {
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
    
    // MARK: Wrappers for CBPeripheral fields.
    var identifier: String { peripheral.identifier.uuidString }
    
    // get-only wrapper
    var peripheral: CBPeripheral { self._peripheral }
    
    required init(_ peripheral: CBPeripheral) {
        self._peripheral = peripheral
        self.name = peripheral.name ?? "Unknown name"
        super.init()
        peripheral.delegate = self
    }
    
    func sync() {
        batteryPercentage = nil
        currentTime = nil
        
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.rawValue.cbuuid! }) else {
            return
        }
        
        if hasTimeSupport {
            if let timeCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.rawValue.cbuuid! }) {
                peripheral.readValue(for: timeCharacteristic)
            }
        }
        
        if hasBatterySupport {
            if let batteryCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Battery.rawValue.cbuuid! }) {
                peripheral.readValue(for: batteryCharacteristic)
            }
        }
    }
    
    func syncTime(target: Date) {
        if !hasTimeSupport {
            print("Syncing time without time support. Dropping.")
            return
        }
        
        guard let service = peripheral.services?.first(where: { $0.uuid == LYWSD02UUID.Service.Data.rawValue.cbuuid! }) else {
            return
        }
        
        guard let timeCharacteristic = service.characteristics?.first(where: { $0.uuid == LYWSD02UUID.Characteristic.Time.rawValue.cbuuid! }) else {
            return
        }
        
        let timezone = TimeZone.current
        let time = Time(timestamp: Int(target.timeIntervalSince1970), timezoneOffset: timezone.secondsFromGMT() / 3600) // todo make timezone configurable
        
        peripheral.writeValue(time.data(), for: timeCharacteristic, type: .withResponse)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Something went wrong while writing a value!")
            print(error.debugDescription)
            return
        }
        
        sync()
    }
    
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.name = peripheral.name ?? "Unknown name"
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("No services found")
            return
        }
        
        for service in services {
            if service.uuid == CBUUID(nsuuid: UUID(uuidString: LYWSD02UUID.Service.Data.rawValue)!) {
                print("Found service which should contain time data. Discovering characteristics...")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("Error discovering characteristics: \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("No characteristics found")
            return
        }
        
        print("Got characteristics!")
        
        for characteristic in characteristics {
            if characteristic.uuid == LYWSD02UUID.Characteristic.Time.rawValue.cbuuid! {
                print("Found time characteristic in service. Time support is available.")
                hasTimeSupport = true
            }
            
            if characteristic.uuid == LYWSD02UUID.Characteristic.Battery.rawValue.cbuuid! {
                print("Found battery characteristic in service. Battery support is available.")
                hasBatterySupport = true
            }
            
            if characteristic.uuid == LYWSD02UUID.Characteristic.SensorData.rawValue.cbuuid! {
                print("Found sensor data characteristics, subscribing.")
                peripheral.setNotifyValue(true, for: characteristic)
                hasTemperatureSupport = true
                hasHumiditySupport = true
            }
        }
        
        sync()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error updating value for characteristic: \(error!.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            print("No data received for characteristic \(characteristic.uuid)")
            return
        }
        
        switch characteristic.uuid {
        case LYWSD02UUID.Characteristic.Time.rawValue.cbuuid!:
            do {
                let unpacked = try unpack("<Ib", data)
                let date = Date(timeIntervalSince1970: TimeInterval(unpacked[0] as! Int))
                DispatchQueue.main.async {
                    self.currentTime = date
                }
            } catch {
                print("Error unpacking time data: \(error.localizedDescription)")
            }
        case LYWSD02UUID.Characteristic.Battery.rawValue.cbuuid!:
            if let firstByte = data.first {
                DispatchQueue.main.async {
                    self.batteryPercentage = Int(firstByte)
                }
            } else {
                print("Got battery characteristic update but no value...")
            }
        case LYWSD02UUID.Characteristic.SensorData.rawValue.cbuuid!:
            do {
                let unpacked = try unpack("<hB", data)
                DispatchQueue.main.async {
                    self.currentTemperature = Double(unpacked[0] as! Int) / 100
                    self.currentHumidity = unpacked[1] as? Int
                }
            } catch {
                print("Error unpacking sensor data: \(error.localizedDescription)")
            }
        default:
            print("Unknown characteristic was updated")
        }
    }
}

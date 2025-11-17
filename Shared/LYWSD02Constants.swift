//
//  LYWSD02Constants.swift
//  LYWSD02 Clock Sync
//
//  Created on 17/11/2025.
//

import Foundation

enum LYWSD02Constants {
    // MARK: - Timing
    static let autoSyncDelay: TimeInterval = 0.2
    static let connectionTimeout: TimeInterval = 10.0
    static let scanTimeout: TimeInterval = 30.0
    static let reconnectionDelays: [TimeInterval] = [1.0, 2.0, 4.0]
    
    // MARK: - Data Sizes
    static let timeDataSize = 5  // 4 bytes timestamp + 1 byte offset
    static let sensorDataSize = 3  // 2 bytes temp + 1 byte humidity
    static let batteryDataSize = 1
    static let historyRecordSize = 14
    static let numRecordsDataSize = 8
    
    // MARK: - Scaling Factors
    static let temperatureScale = 100.0
    
    // MARK: - Validation Ranges
    enum Ranges {
        static let temperature: ClosedRange<Double> = -40...80
        static let humidity: ClosedRange<Int> = 0...100
        static let battery: ClosedRange<Int> = 0...100
        static let timezoneOffset: ClosedRange<Int> = -12...14
    }
    
    // MARK: - Limits
    static let maxHistoryRecords = 500
    static let maxReconnectionAttempts = 3
    static let historyPageSize = 100
}

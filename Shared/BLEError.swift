//
//  BLEError.swift
//  LYWSD02 Clock Sync
//
//  Created on 17/11/2025.
//

import Foundation

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
    
    var errorDescription: String? {
        switch self {
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Please enable it in Settings."
        case .bluetoothUnauthorized:
            return "Bluetooth access is not authorized. Please grant permission in Settings."
        case .bluetoothUnsupported:
            return "This device doesn't support Bluetooth Low Energy."
        case .deviceNotFound:
            return "Device not found. Make sure it's turned on and nearby."
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .connectionFailed(let error):
            return "Failed to connect: \(error.localizedDescription)"
        case .characteristicNotFound:
            return "Device doesn't support required features."
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .writeFailure(let error):
            return "Failed to write data: \(error.localizedDescription)"
        case .readFailure(let error):
            return "Failed to read data: \(error.localizedDescription)"
        case .scanTimeout:
            return "Scan timeout. No devices found."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .bluetoothPoweredOff, .bluetoothUnauthorized:
            return "Open Settings and enable Bluetooth."
        case .deviceNotFound:
            return "Make sure the device is turned on, has battery, and is within range."
        case .connectionTimeout, .connectionFailed:
            return "Try moving closer to the device and retry."
        case .characteristicNotFound:
            return "This device may not be compatible with this app."
        default:
            return "Please try again or restart the app."
        }
    }
}

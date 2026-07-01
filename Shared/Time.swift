//
//  Time.swift
//  LYWSD02 Clock Sync
//
//  Created by Rick Kerkhof on 05/11/2021.
//

import Foundation

struct Time {
    var timestamp = Int(Date().timeIntervalSince1970)
    var timezoneOffset = 1

    /// Encodes the LYWSD02 time payload (`<Ib`): little-endian 4-byte unix timestamp + 1-byte tz offset.
    func data() -> Data {
        // We construct the bytes manually to avoid throwing from `pack`.
        var data = Data(capacity: 5)
        var ts = UInt32(bitPattern: Int32(truncatingIfNeeded: timestamp)).littleEndian
        withUnsafeBytes(of: &ts) { data.append(contentsOf: $0) }
        data.append(UInt8(bitPattern: Int8(truncatingIfNeeded: timezoneOffset)))
        return data
    }
}

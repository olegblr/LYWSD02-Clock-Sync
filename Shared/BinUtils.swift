//
//  BinUtils.swift
//  BinUtils
//
//  Created by Nicolas Seriot on 12/03/16.
//  Copyright © 2016 Nicolas Seriot. All rights reserved.
//
//  Adapted from the open-source BinUtils project:
//  https://github.com/nst/BinUtils (MIT License).
//  Modified for this project: added bounds checking, throwing errors,
//  and unified os.Logger logging.
//

import Foundation
import CoreFoundation
import os.log

private let binUtilsLogger = Logger(subsystem: "com.lywsd02.clocksync", category: "BinUtils")

// MARK: protocol UnpackedType

public protocol Unpackable {}

extension NSString: Unpackable {}
extension Bool: Unpackable {}
extension Int: Unpackable {}
extension Double: Unpackable {}

// MARK: protocol DataConvertible

protocol DataConvertible {}

extension DataConvertible {
    
    init?(data: Data) {
        guard data.count == MemoryLayout<Self>.size else { return nil }
        self = data.withUnsafeBytes { $0.load(as: Self.self) }
    }
    
    init?(bytes: [UInt8]) {
        let data = Data(bytes)
        self.init(data:data)
    }
    
    var data: Data {
        var value = self
        return withUnsafePointer(to: &value) { Data(bytes: $0, count: MemoryLayout<Self>.size) }
    }
}

extension Bool : DataConvertible { }

extension Int8 : DataConvertible { }
extension Int16 : DataConvertible { }
extension Int32 : DataConvertible { }
extension Int64 : DataConvertible { }

extension UInt8 : DataConvertible { }
extension UInt16 : DataConvertible { }
extension UInt32 : DataConvertible { }
extension UInt64 : DataConvertible { }

extension Float32 : DataConvertible { }
extension Float64 : DataConvertible { }

// MARK: String extension

extension String {
    /// Safe substring by integer offsets. Returns `nil` if the range is out of bounds.
    subscript (safe from: Int, to: Int) -> String? {
        guard from >= 0, to <= count, from <= to else { return nil }
        let start = index(startIndex, offsetBy: from)
        let end = index(startIndex, offsetBy: to)
        return String(self[start..<end])
    }
}

// MARK: Data extension

extension Data {
    var bytes : [UInt8] {
        return [UInt8](self)
    }
}

// MARK: functions

public func hexlify(_ data: Data) -> String {
    // similar to hexlify() in Python's binascii module
    return data.map { String(format: "%02x", $0) }.joined()
}

public func unhexlify(_ string:String) -> Data? {
    
    // similar to unhexlify() in Python's binascii module
    // https://docs.python.org/2/library/binascii.html
    
    let s = string.uppercased().replacingOccurrences(of: " ", with: "")

    // A valid hex string must have an even number of characters.
    guard s.count % 2 == 0 else {
        binUtilsLogger.error("unhexlify: odd-length hex string (\(s.count, privacy: .public) chars)")
        return nil
    }

    let nonHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF").inverted
    if let range = s.rangeOfCharacter(from: nonHexCharacterSet) {
        binUtilsLogger.error("unhexlify: found non-hex character at range \(String(describing: range), privacy: .public)")
        return nil
    }

    var data = Data(capacity: s.count / 2)

    for i in stride(from: 0, to: s.count, by: 2) {
        guard let byteString = s[safe: i, i + 2] else {
            return nil
        }
        let byte = UInt8(byteString.withCString { strtoul($0, nil, 16) })
        data.append([byte] as [UInt8], count: 1)
    }

    return data
}

func readIntegerType<T:DataConvertible>(_ type:T.Type, bytes:[UInt8], loc:inout Int) throws -> T {
    let size = MemoryLayout<T>.size
    
    // Bounds checking to prevent crash
    guard loc + size <= bytes.count else {
        throw BinUtilsError.dataOutOfBounds(expected: loc + size, actual: bytes.count)
    }
    
    let sub = Array(bytes[loc..<(loc+size)])
    loc += size
    
    guard let result = T(bytes: sub) else {
        throw BinUtilsError.invalidDataSize(expected: size, actual: sub.count)
    }
    
    return result
}

func readFloatingPointType<T:DataConvertible>(_ type:T.Type, bytes:[UInt8], loc:inout Int, isBigEndian:Bool) throws -> T {
    let size = MemoryLayout<T>.size
    
    // Bounds checking to prevent crash
    guard loc + size <= bytes.count else {
        throw BinUtilsError.dataOutOfBounds(expected: loc + size, actual: bytes.count)
    }
    
    let sub = Array(bytes[loc..<(loc+size)])
    loc += size
    let sub_ = isBigEndian ? sub.reversed() : sub
    
    guard let result = T(bytes: sub_) else {
        throw BinUtilsError.invalidDataSize(expected: size, actual: sub_.count)
    }
    
    return result
}

func isBigEndianFromMandatoryByteOrderFirstCharacter(_ format: String) throws -> Bool {
    guard let firstChar = format.first else {
        throw BinUtilsError.invalidArgument(reason: "empty format")
    }
    switch firstChar {
    case "@":
        throw BinUtilsError.invalidArgument(reason: "native size and alignment '@' is unsupported")
    case "=", "<":
        return false
    case ">", "!":
        return true
    default:
        throw BinUtilsError.invalidArgument(reason: "format '\(format)' first character must be among '=<>!'")
    }
}

// akin to struct.calcsize(fmt)
func numberOfBytesInFormat(_ format:String) -> Int {
    
    var numberOfBytes = 0
    
    var n = 0 // repeat counter
    
    var mutableFormat = format
    
    while !mutableFormat.isEmpty {
        
        let c = mutableFormat.remove(at: mutableFormat.startIndex)
        
        if let i = Int(String(c)) , 0...9 ~= i {
            if n > 0 { n *= 10 }
            n += i
            continue
        }
        
        if c == "s" {
            numberOfBytes += max(n,1)
            n = 0
            continue
        }
        
        let repeatCount = max(n,1)
        
        switch(c) {
            
        case "@", "<", "=", ">", "!", " ":
            ()
        case "c", "b", "B", "x", "?":
            numberOfBytes += 1 * repeatCount
        case "h", "H":
            numberOfBytes += 2 * repeatCount
        case "i", "l", "I", "L", "f":
            numberOfBytes += 4 * repeatCount
        case "q", "Q", "d":
            numberOfBytes += 8 * repeatCount
        case "P":
            numberOfBytes += MemoryLayout<Int>.size * repeatCount
        default:
            assertionFailure("-- unsupported format \(c)")
        }
        
        n = 0
    }
    
    return numberOfBytes
}

func formatDoesMatchDataLength(_ format:String, data:Data) -> Bool {
    let sizeAccordingToFormat = numberOfBytesInFormat(format)
    let dataLength = data.count
    if sizeAccordingToFormat != dataLength {
        binUtilsLogger.error("format \"\(format, privacy: .public)\" expects \(sizeAccordingToFormat, privacy: .public) bytes but data is \(dataLength, privacy: .public) bytes")
        return false
    }
    
    return true
}

/*
 pack() and unpack() should behave as Python's struct module https://docs.python.org/2/library/struct.html BUT:
 - native size and alignment '@' is not supported
 - as a consequence, the byte order specifier character is mandatory and must be among "=<>!"
 - native byte order '=' assumes a little-endian system (eg. Intel x86)
 - Pascal strings 'p' and native pointers 'P' are not supported
 */

public enum BinUtilsError: Error {
    case formatDoesMatchDataLength(format:String, dataSize:Int)
    case unsupportedFormat(character:Character)
    case dataOutOfBounds(expected:Int, actual:Int)
    case invalidDataSize(expected:Int, actual:Int)
    case invalidArgument(reason: String)
}

public func pack(_ format: String, _ objects: [Any], _ stringEncoding: String.Encoding = .windowsCP1252) throws -> Data {

    var objectsQueue = objects
    var mutableFormat = format
    var mutableData = Data()
    var isBigEndian = false

    guard let firstCharacter = mutableFormat.first else {
        throw BinUtilsError.invalidArgument(reason: "empty format")
    }
    mutableFormat.removeFirst()

    switch firstCharacter {
    case "<", "=":
        isBigEndian = false
    case ">", "!":
        isBigEndian = true
    case "@":
        throw BinUtilsError.invalidArgument(reason: "native size and alignment '@' is unsupported")
    default:
        throw BinUtilsError.invalidArgument(reason: "unsupported format character '\(firstCharacter)'")
    }

    func castInt(_ value: Any) throws -> Int {
        if let v = value as? Int { return v }
        if let v = value as? Int32 { return Int(v) }
        if let v = value as? UInt32 { return Int(v) }
        if let v = value as? Int64 { return Int(v) }
        throw BinUtilsError.invalidArgument(reason: "expected Int, got \(type(of: value))")
    }

    func castDouble(_ value: Any) throws -> Double {
        if let v = value as? Double { return v }
        if let v = value as? Float { return Double(v) }
        if let v = value as? Int { return Double(v) }
        throw BinUtilsError.invalidArgument(reason: "expected Double, got \(type(of: value))")
    }

    var n = 0 // repeat counter

    while !mutableFormat.isEmpty {

        let c = mutableFormat.remove(at: mutableFormat.startIndex)

        if let i = Int(String(c)), 0...9 ~= i {
            if n > 0 { n *= 10 }
            n += i
            continue
        }

        if c == "s" {
            guard !objectsQueue.isEmpty else {
                throw BinUtilsError.invalidArgument(reason: "missing argument for format 's'")
            }
            let o = objectsQueue.remove(at: 0)
            guard let stringValue = o as? String else {
                throw BinUtilsError.invalidArgument(reason: "expected String, got \(type(of: o))")
            }
            guard let stringData = stringValue.data(using: .utf8) else {
                throw BinUtilsError.invalidArgument(reason: "cannot encode string as UTF-8")
            }
            var bytes = stringData.bytes
            let expectedSize = max(1, n)
            while bytes.count < expectedSize { bytes.append(0x00) }
            if bytes.count > expectedSize { bytes = Array(bytes[0..<expectedSize]) }
            if isBigEndian { bytes = bytes.reversed() }
            mutableData.append(bytes, count: bytes.count)
            n = 0
            continue
        }

        for _ in 0..<max(n, 1) {
            var bytes: [UInt8] = []
            var o: Any = 0
            if c != "x" {
                guard !objectsQueue.isEmpty else {
                    throw BinUtilsError.invalidArgument(reason: "missing argument for format '\(c)'")
                }
                o = objectsQueue.removeFirst()
            }

            switch c {
            case "?":
                guard let b = o as? Bool else {
                    throw BinUtilsError.invalidArgument(reason: "expected Bool, got \(type(of: o))")
                }
                bytes = b ? [0x01] : [0x00]
            case "c":
                guard let s = (o as? String) ?? (o as? NSString) as String? else {
                    throw BinUtilsError.invalidArgument(reason: "expected String for 'c', got \(type(of: o))")
                }
                let charAsString = String(s.prefix(1))
                guard let data = charAsString.data(using: stringEncoding) else {
                    throw BinUtilsError.invalidArgument(reason: "cannot encode '\(charAsString)' using \(stringEncoding)")
                }
                bytes = data.bytes
            case "b":
                bytes = Int8(truncatingIfNeeded: try castInt(o)).data.bytes
            case "h":
                bytes = Int16(truncatingIfNeeded: try castInt(o)).data.bytes
            case "i", "l":
                bytes = Int32(truncatingIfNeeded: try castInt(o)).data.bytes
            case "q":
                bytes = Int64(try castInt(o)).data.bytes
            case "Q":
                bytes = UInt64(try castInt(o)).data.bytes
            case "B":
                bytes = UInt8(truncatingIfNeeded: try castInt(o)).data.bytes
            case "H":
                bytes = UInt16(truncatingIfNeeded: try castInt(o)).data.bytes
            case "I", "L":
                bytes = UInt32(truncatingIfNeeded: try castInt(o)).data.bytes
            case "f":
                bytes = Float32(try castDouble(o)).data.bytes
            case "d":
                bytes = Float64(try castDouble(o)).data.bytes
            case "x":
                bytes = [0x00]
            default:
                throw BinUtilsError.unsupportedFormat(character: c)
            }

            if isBigEndian { bytes = bytes.reversed() }
            mutableData.append(Data(bytes))
        }

        n = 0
    }

    return mutableData
}

public func unpack(_ format:String, _ data:Data, _ stringEncoding:String.Encoding=String.Encoding.windowsCP1252) throws -> [Unpackable] {
    
    assert(CFByteOrderGetCurrent() == 1 /* CFByteOrderLittleEndian */, "\(#file) assumes little endian, but host is big endian")
    
    let isBigEndian = try isBigEndianFromMandatoryByteOrderFirstCharacter(format)
    
    if formatDoesMatchDataLength(format, data: data) == false {
        throw BinUtilsError.formatDoesMatchDataLength(format:format, dataSize:data.count)
    }
    
    var a : [Unpackable] = []
    
    var loc = 0
    
    let bytes = data.bytes
    
    var n = 0 // repeat counter
    
    var mutableFormat = format
    
    mutableFormat.remove(at: mutableFormat.startIndex) // consume byte-order specifier
    
    while !mutableFormat.isEmpty {
        
        let c = mutableFormat.remove(at: mutableFormat.startIndex)
        
        if let i = Int(String(c)) , 0...9 ~= i {
            if n > 0 { n *= 10 }
            n += i
            continue
        }
        
        if c == "s" {
            let length = max(n,1)
            
            // Bounds checking to prevent crash
            guard loc + length <= bytes.count else {
                throw BinUtilsError.dataOutOfBounds(expected: loc + length, actual: bytes.count)
            }
            
            let sub = Array(bytes[loc..<loc+length])
            
            guard let s = NSString(bytes: sub, length: length, encoding: stringEncoding.rawValue) else {
                throw BinUtilsError.invalidArgument(reason: "could not decode string")
            }
            
            a.append(s)
            
            loc += length
            
            n = 0
            
            continue
        }
        
        for _ in 0..<max(n,1) {
            
            var o : Unpackable?
            
            switch(c) {
                
            case "c":
                // Bounds checking for single character
                guard loc < bytes.count else {
                    throw BinUtilsError.dataOutOfBounds(expected: loc + 1, actual: bytes.count)
                }
                
                let optionalString = NSString(bytes: [bytes[loc]], length: 1, encoding: String.Encoding.utf8.rawValue)
                loc += 1
                guard let s = optionalString else {
                    throw BinUtilsError.invalidArgument(reason: "could not decode 'c' character")
                }
                o = s
            case "b":
                let r = try readIntegerType(Int8.self, bytes:bytes, loc:&loc)
                o = Int(r)
            case "B":
                let r = try readIntegerType(UInt8.self, bytes:bytes, loc:&loc)
                o = Int(r)
            case "?":
                let r = try readIntegerType(Bool.self, bytes:bytes, loc:&loc)
                o = r ? true : false
            case "h":
                let r = try readIntegerType(Int16.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int16(bigEndian: r) : r)
            case "H":
                let r = try readIntegerType(UInt16.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? UInt16(bigEndian: r) : r)
            case "i":
                fallthrough
            case "l":
                let r = try readIntegerType(Int32.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int32(bigEndian: r) : r)
            case "I":
                fallthrough
            case "L":
                let r = try readIntegerType(UInt32.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? UInt32(bigEndian: r) : r)
            case "q":
                let r = try readIntegerType(Int64.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int64(bigEndian: r) : r)
            case "Q":
                let r = try readIntegerType(UInt64.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? UInt64(bigEndian: r) : r)
            case "f":
                let r = try readFloatingPointType(Float32.self, bytes:bytes, loc:&loc, isBigEndian:isBigEndian)
                o = Double(r)
            case "d":
                let r = try readFloatingPointType(Float64.self, bytes:bytes, loc:&loc, isBigEndian:isBigEndian)
                o = Double(r)
            case "x":
                // Bounds checking for padding byte
                guard loc < bytes.count else {
                    throw BinUtilsError.dataOutOfBounds(expected: loc + 1, actual: bytes.count)
                }
                loc += 1
            case " ":
                ()
            default:
                throw BinUtilsError.unsupportedFormat(character:c)
            }
            
            if let o = o { a.append(o) }
        }
        
        n = 0
    }
    
    return a
}

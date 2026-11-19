// SPDX-License-Identifier: GPL-2.0-or-later
import CSMC
import Foundation
import IOKit

public enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case smcResult(UInt8)
    case badKey(String)
    case sizeMismatch(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let r): return "IOServiceOpen failed: \(String(format: "0x%08x", r))"
        case .callFailed(let r):
            let hint = r == kIOReturnNotPrivileged ? " (not privileged: run as root)" : ""
            return "IOConnectCallStructMethod failed: \(String(format: "0x%08x", r))\(hint)"
        case .smcResult(let r): return "SMC returned error code \(r) (key missing?)"
        case .badKey(let k): return "SMC key must be 4 ASCII characters: \(k)"
        case .sizeMismatch(let e, let g): return "Key expects \(e) bytes, got \(g)"
        }
    }
}

/// Minimal AppleSMC client. Reads work as any user; writes need root.
public final class SMC {
    private var conn: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfo] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.openFailed(r) }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    public static func fourCC(_ key: String) throws -> UInt32 {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { throw SMCError.badKey(key) }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let r = IOConnectCallStructMethod(conn, UInt32(SMC_KERNEL_INDEX),
                                          &input, MemoryLayout<SMCParamStruct>.stride,
                                          &output, &outSize)
        guard r == kIOReturnSuccess else { throw SMCError.callFailed(r) }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }

    private func keyInfo(_ key: UInt32) throws -> SMCKeyInfo {
        if let cached = keyInfoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(SMC_CMD_READ_KEYINFO)
        let info = try call(&input).keyInfo
        keyInfoCache[key] = info
        return info
    }

    public func read(_ key: String) throws -> [UInt8] {
        let k = try SMC.fourCC(key)
        let info = try keyInfo(k)
        var input = SMCParamStruct()
        input.key = k
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(SMC_CMD_READ_BYTES)
        var out = try call(&input)
        let size = Int(min(info.dataSize, 32))
        return withUnsafeBytes(of: &out.bytes) { Array($0.prefix(size)) }
    }

    public func write(_ key: String, _ value: [UInt8]) throws {
        let k = try SMC.fourCC(key)
        let info = try keyInfo(k)
        guard Int(info.dataSize) == value.count else {
            throw SMCError.sizeMismatch(expected: Int(info.dataSize), got: value.count)
        }
        var input = SMCParamStruct()
        input.key = k
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(SMC_CMD_WRITE_BYTES)
        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for (i, b) in value.enumerated() { buf[i] = b }
        }
        _ = try call(&input)
    }
}

/// MagSafe LED control key and its known values.
public enum MagSafeLED {
    public static let key = "ACLC"
    public static let system: UInt8 = 0x00 // firmware decides
    public static let off: UInt8 = 0x01
    public static let green: UInt8 = 0x03
    public static let orange: UInt8 = 0x04
}

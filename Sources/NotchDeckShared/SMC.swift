import Foundation
import IOKit

// inputs {}, does {minimal user-space AppleSMC reader: fan RPMs and temperature keys — READ ONLY (writes require the future privileged helper, see ARCHITECTURE)}, returns {namespace}
public enum SMC {
    private struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let readCommand: UInt8 = 5
    private static let writeCommand: UInt8 = 6
    private static let keyInfoCommand: UInt8 = 9

    private static var connection: io_connect_t = {
        var conn: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return 0 }
        IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        return conn
    }()

    // inputs {four-char key}, does {reads and decodes a numeric SMC value (flt / fpe2 / ui8-32)}, returns {value or nil}
    public static func readValue(_ key: String) -> Double? {
        guard connection != 0, key.count == 4 else { return nil }
        let keyCode = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = keyCode
        input.data8 = keyInfoCommand
        guard call(&input, &output) == kIOReturnSuccess, output.result == 0 else { return nil }

        let dataType = output.keyInfo.dataType
        let dataSize = output.keyInfo.dataSize

        var read = SMCParamStruct()
        var result = SMCParamStruct()
        read.key = keyCode
        read.keyInfo.dataSize = dataSize
        read.data8 = readCommand
        guard call(&read, &result) == kIOReturnSuccess, result.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: result.bytes) { Array($0) }
        switch fourCC(dataType) {
        case "flt ":
            guard dataSize >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
        case "fpe2":
            guard dataSize >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    // inputs {four-char key, value}, does {writes a numeric SMC value (flt / fpe2 / ui8-16) — root only; used exclusively by the privileged helper for fan keys}, returns {success}
    @discardableResult
    public static func writeValue(_ key: String, _ value: Double) -> Bool {
        guard connection != 0, key.count == 4 else { return false }
        let keyCode = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        var infoInput = SMCParamStruct()
        var infoOutput = SMCParamStruct()
        infoInput.key = keyCode
        infoInput.data8 = keyInfoCommand
        guard call(&infoInput, &infoOutput) == kIOReturnSuccess, infoOutput.result == 0 else { return false }

        var write = SMCParamStruct()
        var result = SMCParamStruct()
        write.key = keyCode
        write.keyInfo = infoOutput.keyInfo
        write.data8 = writeCommand
        let encoded: [UInt8]
        switch fourCC(infoOutput.keyInfo.dataType) {
        case "flt ":
            encoded = withUnsafeBytes(of: Float32(value).bitPattern.littleEndian) { Array($0) }
        case "fpe2":
            let raw = UInt16(max(0, min(65535, value * 4)))
            encoded = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 ":
            encoded = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let raw = UInt16(max(0, min(65535, value)))
            encoded = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            return false
        }
        withUnsafeMutableBytes(of: &write.bytes) { buffer in
            for (index, byte) in encoded.prefix(buffer.count).enumerated() {
                buffer[index] = byte
            }
        }
        guard call(&write, &result) == kIOReturnSuccess, result.result == 0 else { return false }
        return true
    }

    /// Number of fans reported by the SMC.
    public static var fanCount: Int {
        Int(readValue("FNum") ?? 0)
    }

    // inputs {key list}, does {averages the readable keys within a sane range (sensor sets differ per model)}, returns {average or nil}
    public static func averageTemperature(_ keys: [String]) -> Double? {
        let values = keys.compactMap(readValue).filter { $0 > 5 && $0 < 115 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func call(_ input: inout SMCParamStruct, _ output: inout SMCParamStruct) -> kern_return_t {
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(
            connection, 2,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize
        )
    }

    private static func fourCC(_ value: UInt32) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((value >> $0) & 0xFF))) }
        return String(chars)
    }
}

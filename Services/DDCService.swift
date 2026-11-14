import CoreGraphics
import Foundation
import IOKit

// Apple Silicon DDC/CI over the DCP AV service. The registry walk, EDID UUID matching and packet
// layout follow MonitorControl's Arm64DDC (MIT, see THIRD_PARTY_NOTICES.md).

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32
) -> IOReturn

/// Byte-level DDC/CI framing, kept pure so it can be tested without hardware.
enum DDCCodec {
    static let chipAddress: UInt8 = 0x37
    static let dataAddress: UInt8 = 0x51

    static func checksum(seed: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Packet written to sub-address 0x51: length byte, opcode payload, checksum.
    static func getRequest(_ code: UInt8) -> [UInt8] {
        packet([0x01, code])
    }

    static func setRequest(_ code: UInt8, value: UInt16) -> [UInt8] {
        packet([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func packet(_ payload: [UInt8]) -> [UInt8] {
        let body = [UInt8(0x80 | payload.count)] + payload
        // The checksum covers the destination address (0x6E) and the source sub-address (0x51).
        return body + [checksum(seed: (chipAddress << 1) ^ dataAddress, body)]
    }

    /// Parses an 11-byte "VCP feature reply" (opcode 0x02). Returns nil for a bad checksum,
    /// a monitor-reported "unsupported" result or a reply for a different feature.
    static func parseGetReply(_ reply: [UInt8], code: UInt8) -> HardwareControlValue? {
        guard reply.count >= 11,
              checksum(seed: 0x50, Array(reply[0..<10])) == reply[10],
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else { return nil }
        return HardwareControlValue(current: min(current, maximum), maximum: maximum)
    }
}

/// Identity read from an external framebuffer entry that precedes a DCPAVServiceProxy.
struct DDCServiceIdentity: Equatable {
    var edidUUID: String
    var productName: String
    var serialNumber: Int64

    /// Higher is a better match; 0 means no evidence the service drives this display.
    func matchScore(vendorID: UInt32, productID: UInt32, serialNumber displaySerial: UInt32,
                    productName displayName: String?, manufactureWeek: UInt32?, manufactureYear: UInt32?,
                    physicalWidthMM: Double, physicalHeightMM: Double) -> Int {
        let uuid = edidUUID.uppercased()
        func field(_ offset: Int, _ length: Int) -> String? {
            guard uuid.count >= offset + length else { return nil }
            let start = uuid.index(uuid.startIndex, offsetBy: offset)
            return String(uuid[start..<uuid.index(start, offsetBy: length)])
        }
        var score = 0
        let vendor = String(format: "%04X", vendorID & 0xFFFF)
        // EDID stores the product code little-endian.
        let product = String(format: "%02X%02X", productID & 0xFF, (productID >> 8) & 0xFF)
        if field(0, 4) == vendor { score += 1 }
        if field(4, 4) == product { score += 1 }
        if let week = manufactureWeek, let year = manufactureYear, year >= 1990,
           field(19, 4) == String(format: "%02X%02X", week & 0xFF, (year - 1990) & 0xFF) { score += 1 }
        if physicalWidthMM > 0, physicalHeightMM > 0,
           field(30, 4) == String(format: "%02X%02X", Int(physicalWidthMM / 10) & 0xFF, Int(physicalHeightMM / 10) & 0xFF) { score += 1 }
        if let displayName, !productName.isEmpty, displayName.caseInsensitiveCompare(productName) == .orderedSame { score += 1 }
        if serialNumber != 0, displaySerial != 0, UInt32(truncatingIfNeeded: serialNumber) == displaySerial { score += 1 }
        return score
    }

    func matchScore(for display: DisplayDevice) -> Int {
        matchScore(
            vendorID: display.vendorID, productID: display.modelID, serialNumber: display.serialNumber,
            productName: display.metadata.productName, manufactureWeek: display.metadata.manufactureWeek,
            manufactureYear: display.metadata.manufactureYear,
            physicalWidthMM: display.metadata.physicalWidthMM, physicalHeightMM: display.metadata.physicalHeightMM
        )
    }
}

/// All I2C traffic is serialized on one background queue: monitors drop interleaved requests,
/// and each transaction sleeps for tens of milliseconds.
final class DDCService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cc.ss-data.hidpibuddy.ddc", qos: .userInitiated)
    private var services: [UInt32: CFTypeRef] = [:]
    /// Last displays passed to attach, so a failed write can re-match after the registry changed.
    private var attachedDisplays: [DisplayDevice] = []

    /// Matches each external display to its AV service. Call after the display list changes.
    func attach(_ displays: [DisplayDevice]) async {
        let targets = displays.filter { !$0.isBuiltin && $0.isOnline }
        await run { self.attachLocked(targets) }
    }

    func read(_ control: HardwareControl, displayID: UInt32) async -> HardwareControlValue? {
        await run { self.readLocked(control, displayID: displayID) }
    }

    func readAll(displayID: UInt32) async -> [HardwareControl: HardwareControlValue] {
        await run {
            var values: [HardwareControl: HardwareControlValue] = [:]
            for control in HardwareControl.allCases {
                values[control] = self.readLocked(control, displayID: displayID)
            }
            return values
        }
    }

    func write(_ control: HardwareControl, value: UInt16, displayID: UInt32) async throws {
        try await runThrowing { try self.writeLocked(control, value: value, displayID: displayID) }
    }

    /// Synchronous read-only path for the CLI.
    func readAllSync(_ displays: [DisplayDevice]) -> [UInt32: [HardwareControl: HardwareControlValue]] {
        queue.sync {
            attachLocked(displays.filter { !$0.isBuiltin && $0.isOnline })
            var result: [UInt32: [HardwareControl: HardwareControlValue]] = [:]
            for id in services.keys {
                var values: [HardwareControl: HardwareControlValue] = [:]
                for control in HardwareControl.allCases { values[control] = readLocked(control, displayID: id) }
                result[id] = values
            }
            return result
        }
    }

    private func runThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Queue-confined

    private func attachLocked(_ displays: [DisplayDevice]) {
        attachedDisplays = displays
        services.removeAll()
        let candidates = Self.externalAVServices()
        var used = Set<Int>()
        // Assign the strongest matches first so two monitors never share one service.
        let pairs = displays.flatMap { display in
            candidates.indices.map { (display: display, index: $0, score: candidates[$0].identity.matchScore(for: display)) }
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        for pair in pairs where services[pair.display.id] == nil && !used.contains(pair.index) {
            services[pair.display.id] = candidates[pair.index].service
            used.insert(pair.index)
        }
    }

    private func readLocked(_ control: HardwareControl, displayID: UInt32) -> HardwareControlValue? {
        guard let service = services[displayID] else { return nil }
        var request = DDCCodec.getRequest(control.vcpCode)
        // Slow monitors need longer to prepare a reply; widen the wait on each retry.
        for replyDelay: useconds_t in [40_000, 70_000, 120_000] {
            usleep(10_000)
            guard Self.write(service, &request) == kIOReturnSuccess else { continue }
            usleep(replyDelay)
            var reply = [UInt8](repeating: 0, count: 11)
            let status = reply.withUnsafeMutableBytes {
                IOAVServiceReadI2C(service, UInt32(DDCCodec.chipAddress), UInt32(DDCCodec.dataAddress), $0.baseAddress!, 11)
            }
            if status == kIOReturnSuccess, let value = DDCCodec.parseGetReply(reply, code: control.vcpCode) {
                return value
            }
            usleep(20_000)
        }
        return nil
    }

    private func writeLocked(_ control: HardwareControl, value: UInt16, displayID: UInt32) throws {
        var status = send(control, value: value, displayID: displayID)
        if status != kIOReturnSuccess {
            // The AV service is replaced after sleep or link retraining; re-match once and retry.
            attachLocked(attachedDisplays)
            status = send(control, value: value, displayID: displayID)
        }
        guard services[displayID] != nil else {
            throw LocalizedServiceError(key: "hardware.error.unavailable")
        }
        guard status == kIOReturnSuccess else {
            throw LocalizedServiceError(key: "hardware.error.write", detail: "IOAVServiceWriteI2C: \(status)")
        }
    }

    private func send(_ control: HardwareControl, value: UInt16, displayID: UInt32) -> IOReturn {
        guard let service = services[displayID] else { return kIOReturnNotFound }
        var request = DDCCodec.setRequest(control.vcpCode, value: value)
        var status = kIOReturnError
        // Writes are unacknowledged in DDC/CI; sending twice is MonitorControl's reliability default.
        for _ in 0..<2 {
            usleep(10_000)
            status = Self.write(service, &request)
        }
        return status
    }

    private static func write(_ service: CFTypeRef, _ packet: inout [UInt8]) -> IOReturn {
        let count = UInt32(packet.count)
        return packet.withUnsafeMutableBytes {
            IOAVServiceWriteI2C(service, UInt32(DDCCodec.chipAddress), UInt32(DDCCodec.dataAddress), $0.baseAddress!, count)
        }
    }

    /// Walks the registry in order: each external framebuffer (AppleCLCD2 / IOMobileFramebufferShim)
    /// is followed by the DCPAVServiceProxy that carries its DDC channel.
    private static func externalAVServices() -> [(identity: DDCServiceIdentity, service: CFTypeRef)] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [(DDCServiceIdentity, CFTypeRef)] = []
        var pending: DDCServiceIdentity?
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { continue }
            let entryName = String(cString: name)
            if entryName.contains("AppleCLCD2") || entryName.contains("IOMobileFramebufferShim") {
                let attributes = property("DisplayAttributes", entry) as? [String: Any]
                let product = attributes?["ProductAttributes"] as? [String: Any]
                pending = DDCServiceIdentity(
                    edidUUID: property("EDID UUID", entry) as? String ?? "",
                    productName: product?["ProductName"] as? String ?? "",
                    serialNumber: (product?["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                )
            } else if entryName == "DCPAVServiceProxy" {
                defer { pending = nil }
                guard let identity = pending, !identity.edidUUID.isEmpty,
                      property("Location", entry) as? String == "External",
                      let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                results.append((identity, service))
            }
        }
        return results
    }

    private static func property(_ key: String, _ entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

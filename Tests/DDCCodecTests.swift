import Testing
@testable import PixelFit

struct DDCCodecTests {
    @Test func getRequestMatchesDDCCIFraming() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        #expect(DDCCodec.getRequest(0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setRequestEncodesBigEndianValue() {
        let packet = DDCCodec.setRequest(0x62, value: 0x0132)
        #expect(Array(packet.prefix(5)) == [0x84, 0x03, 0x62, 0x01, 0x32])
        #expect(packet.last == DDCCodec.checksum(seed: 0x6E ^ 0x51, Array(packet.dropLast())))
    }

    private func reply(code: UInt8, result: UInt8 = 0, maximum: UInt16, current: UInt16) -> [UInt8] {
        var bytes: [UInt8] = [0x6E, 0x88, 0x02, result, code, 0x00,
                              UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        bytes.append(DDCCodec.checksum(seed: 0x50, bytes))
        return bytes
    }

    @Test func parsesValidReply() {
        #expect(DDCCodec.parseGetReply(reply(code: 0x10, maximum: 100, current: 99), code: 0x10)
                == HardwareControlValue(current: 99, maximum: 100))
    }

    @Test func rejectsCorruptUnsupportedOrMismatchedReplies() {
        var corrupt = reply(code: 0x10, maximum: 100, current: 50)
        corrupt[9] ^= 0xFF
        #expect(DDCCodec.parseGetReply(corrupt, code: 0x10) == nil)
        #expect(DDCCodec.parseGetReply(reply(code: 0x10, result: 1, maximum: 100, current: 50), code: 0x10) == nil)
        #expect(DDCCodec.parseGetReply(reply(code: 0x12, maximum: 100, current: 50), code: 0x10) == nil)
        #expect(DDCCodec.parseGetReply(reply(code: 0x10, maximum: 0, current: 0), code: 0x10) == nil)
        #expect(DDCCodec.parseGetReply([0x6E, 0x88], code: 0x10) == nil)
    }

    @Test func clampsCurrentAboveMaximum() {
        #expect(DDCCodec.parseGetReply(reply(code: 0x10, maximum: 100, current: 140), code: 0x10)?.current == 100)
    }

    @Test func edidUUIDMatchesRealRegistryValues() {
        // Values observed on RV200plus (VID 0x4ACD, PID 0x2740, week 1 / 2026, 60×33 cm).
        let identity = DDCServiceIdentity(edidUUID: "4ACD4027-0000-0000-0124-0104B53C2178", productName: "RV200plus", serialNumber: 0)
        let score = identity.matchScore(vendorID: 0x4ACD, productID: 0x2740, serialNumber: 0, productName: "RV200plus",
                                        manufactureWeek: 1, manufactureYear: 2026, physicalWidthMM: 600, physicalHeightMM: 330)
        #expect(score == 5)
        let other = identity.matchScore(vendorID: 0x6474, productID: 0xD01F, serialNumber: 1666187265, productName: "Sculptor",
                                        manufactureWeek: 11, manufactureYear: 2026, physicalWidthMM: 350, physicalHeightMM: 200)
        #expect(other == 0)
    }

    @Test func fractionRoundTripsWithinMaximum() {
        let value = HardwareControlValue(current: 0, maximum: 100)
        #expect(value.with(fraction: 0.555).current == 56)
        #expect(value.with(fraction: 2).current == 100)
        #expect(value.with(fraction: -1).current == 0)
        #expect(HardwareControlValue(current: 99, maximum: 100).percentLabel == "99%")
    }
}

struct MediaKeyTests {
    @Test func decodesSystemDefinedMediaKeys() {
        // data1 = keyType << 16 | keyState << 8; 0x0A = down, 0x0B = up.
        #expect(MediaKey.decode(data1: (2 << 16) | (0x0A << 8))! == (MediaKey.brightnessUp, true))
        #expect(MediaKey.decode(data1: (3 << 16) | (0x0B << 8))! == (MediaKey.brightnessDown, false))
        #expect(MediaKey.decode(data1: (7 << 16) | (0x0A << 8))?.key == .mute)
        #expect(MediaKey.decode(data1: (16 << 16) | (0x0A << 8)) == nil) // play/pause stays with the system
    }
}

struct SoftwareDimmingTests {
    @Test func levelMapsAboveFloor() {
        #expect(DimmingService.multiplier(for: 1) == 1)
        #expect(DimmingService.multiplier(for: 0) == DimmingService.floor)
        #expect(DimmingService.multiplier(for: -3) == DimmingService.floor)
        #expect(abs(DimmingService.multiplier(for: 0.5) - 0.575) < 0.0001)
    }
}

struct BrightnessSplitTests {
    @Test func combinedSplitsAtSwitchingPoint() {
        #expect(BrightnessSplit.parts(level: 1, mode: .combined) == (1, 1))
        #expect(BrightnessSplit.parts(level: 0.75, mode: .combined) == (0.5, 1))
        #expect(BrightnessSplit.parts(level: 0.5, mode: .combined) == (0, 1))
        #expect(BrightnessSplit.parts(level: 0.25, mode: .combined) == (0, 0.5))
        #expect(BrightnessSplit.parts(level: 0, mode: .combined) == (0, 0))
    }

    @Test func otherModesTouchOnlyTheirOwnPath() {
        #expect(BrightnessSplit.parts(level: 0.3, mode: .hardware) == (0.3, 1))
        let software = BrightnessSplit.parts(level: 0.3, mode: .software)
        #expect(software.ddc == nil && software.software == 0.3)
        #expect(BrightnessSplit.parts(level: 7, mode: .hardware) == (1, 1))
    }

    @Test func levelRoundTripsThroughParts() {
        for mode in BrightnessMode.allCases {
            for step in 0...16 {
                let level = Double(step) / 16
                let parts = BrightnessSplit.parts(level: level, mode: mode)
                #expect(abs(BrightnessSplit.level(ddc: parts.ddc, software: parts.software, mode: mode) - level) < 0.0001)
            }
        }
    }
}

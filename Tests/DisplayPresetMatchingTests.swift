import Foundation
import Testing
@testable import PixelFit

@Suite("Display preset matching")
struct DisplayPresetMatchingTests {
    private let hiDPI = DisplayMode(modeID: 7, cgsModeNumber: nil, width: 1600, height: 1000,
                                    pixelWidth: 3200, pixelHeight: 2000, refreshRate: 120, isHiDPI: true, scaleDensity: 2)

    @Test func matchesBySerialAfterDisplayIDChanges() throws {
        let saved = DisplayPresetMode(display: display(id: 2, serial: 42), displayName: "Sculptor", mode: hiDPI)
        let reconnected = display(id: 5, serial: 42)
        let preset = DisplayPreset(name: "Desk", displayModes: [saved])
        guard case .ready(let targets) = preset.resolve(in: [display(id: 2, vendor: 9, serial: 1), reconnected]) else {
            Issue.record("Expected the reconnected display to match")
            return
        }
        #expect(targets.map(\.display.id) == [5])
        #expect(targets.first?.mode == hiDPI)
    }

    @Test func legacyPresetWithoutIdentityFallsBackToDisplayID() throws {
        let data = try JSONEncoder().encode(["displayID": AnyEncodable(UInt32(3)), "displayName": AnyEncodable("Old"),
                                             "mode": AnyEncodable(hiDPI)])
        let legacy = try JSONDecoder().decode(DisplayPresetMode.self, from: data)
        #expect(legacy.vendorID == nil)
        #expect(legacy.matchingDisplay(in: [display(id: 3, serial: 42)])?.id == 3)
        #expect(legacy.matchingDisplay(in: [display(id: 4, serial: 42)]) == nil)
    }

    @Test func identicalModelsWithoutSerialUseSavedIDOrRefuse() {
        let saved = DisplayPresetMode(display: display(id: 2, serial: 0), displayName: "Twin", mode: hiDPI)
        #expect(saved.matchingDisplay(in: [display(id: 8, serial: 0)])?.id == 8)
        #expect(saved.matchingDisplay(in: [display(id: 1, serial: 0), display(id: 2, serial: 0)])?.id == 2)
        #expect(saved.matchingDisplay(in: [display(id: 6, serial: 0), display(id: 7, serial: 0)]) == nil)
    }

    @Test func missingDisplayNamesItAndAppliesNothing() {
        let preset = DisplayPreset(name: "Desk", displayModes: [
            DisplayPresetMode(display: display(id: 1, serial: 1), displayName: "Main", mode: hiDPI),
            DisplayPresetMode(display: display(id: 2, serial: 2), displayName: "Side", mode: hiDPI)
        ])
        guard case .displayMissing(let name) = preset.resolve(in: [display(id: 1, serial: 1)]) else {
            Issue.record("Expected a missing display")
            return
        }
        #expect(name == "Side")
    }

    @Test func unavailableModeNamesDisplayAndMode() {
        var sixty = hiDPI
        sixty.refreshRate = 60
        let preset = DisplayPreset(name: "Desk", displayModes: [
            DisplayPresetMode(display: display(id: 1, serial: 1), displayName: "Main", mode: sixty)
        ])
        guard case .modeUnavailable(let name, let mode) = preset.resolve(in: [display(id: 1, serial: 1)]) else {
            Issue.record("Expected an unavailable mode")
            return
        }
        #expect(name == "Main")
        #expect(mode == sixty.label)
    }

    private func display(id: UInt32, vendor: UInt32 = 0x6474, serial: UInt32) -> DisplayDevice {
        DisplayDevice(id: id, name: "Test", vendorID: vendor, modelID: 0xD01F, serialNumber: serial,
                      metadata: DisplayMetadata(productName: nil, vendorID: vendor, productID: 0xD01F,
                                                serialNumber: serial, manufactureWeek: nil, manufactureYear: nil,
                                                physicalWidthMM: 0, physicalHeightMM: 0, unitNumber: 1,
                                                colorSpaceName: nil, isMain: false, isActive: true),
                      isBuiltin: false, isOnline: true, frame: CGRectCodable(.zero),
                      currentMode: hiDPI, availableModes: [hiDPI], rotation: 0)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: some Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

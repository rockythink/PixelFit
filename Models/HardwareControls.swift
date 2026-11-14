import Foundation

/// Monitor settings reachable over DDC/CI (MCCS VCP codes).
enum HardwareControl: String, CaseIterable, Codable, Identifiable {
    case brightness
    case contrast
    case volume

    var id: String { rawValue }

    var vcpCode: UInt8 {
        switch self {
        case .brightness: 0x10
        case .contrast: 0x12
        case .volume: 0x62
        }
    }

    var titleKey: String { "hardware.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .volume: "speaker.wave.2"
        }
    }
}

struct HardwareControlValue: Codable, Hashable {
    var current: UInt16
    var maximum: UInt16

    var fraction: Double {
        maximum > 0 ? Double(current) / Double(maximum) : 0
    }

    var percentLabel: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Same maximum, current set from a 0...1 fraction.
    func with(fraction: Double) -> HardwareControlValue {
        let clamped = min(max(fraction, 0), 1)
        return HardwareControlValue(current: UInt16((clamped * Double(maximum)).rounded()), maximum: maximum)
    }
}

struct DisplayHardwareState: Hashable {
    enum Phase: Hashable {
        case probing
        case ready
        /// No DDC/CI reply for any control: wrong transport, DDC disabled in the monitor OSD, or unmatched service.
        case unavailable
    }

    var phase: Phase = .probing
    var values: [HardwareControl: HardwareControlValue] = [:]

    var availableControls: [HardwareControl] {
        HardwareControl.allCases.filter { values[$0] != nil }
    }
}

struct HardwareWriteKey: Hashable {
    var displayID: UInt32
    var control: HardwareControl
}

/// How a display's brightness slider is realized.
enum BrightnessMode: String, Codable, CaseIterable, Identifiable {
    /// DDC/CI only: the monitor's own backlight.
    case hardware
    /// Upper part of the range drives DDC; below the switching point DDC stays at 0 and
    /// software dimming continues, so a display can go darker than its own minimum.
    case combined
    /// Software dimming only, for displays without DDC or that ignore DDC brightness.
    case software

    var id: String { rawValue }
    var titleKey: String { "brightness.mode.\(rawValue)" }
}

/// Pure mapping between the single user-facing brightness level and its DDC / software parts.
enum BrightnessSplit {
    static let switchingPoint = 0.5

    /// `ddc` is nil when the mode leaves the monitor untouched.
    static func parts(level: Double, mode: BrightnessMode) -> (ddc: Double?, software: Double) {
        let level = min(max(level, 0), 1)
        switch mode {
        case .hardware:
            return (level, 1)
        case .software:
            return (nil, level)
        case .combined:
            return level >= switchingPoint
                ? ((level - switchingPoint) / (1 - switchingPoint), 1)
                : (0, level / switchingPoint)
        }
    }

    static func level(ddc: Double?, software: Double, mode: BrightnessMode) -> Double {
        switch mode {
        case .hardware:
            return ddc ?? 1
        case .software:
            return software
        case .combined:
            // Software dimming below 1 only happens while DDC sits at its minimum.
            return software < 0.999 ? software * switchingPoint : switchingPoint + (ddc ?? 1) * (1 - switchingPoint)
        }
    }
}

/// Persisted per physical display. `mode == nil` means automatic: combined when the monitor answers
/// DDC brightness, software otherwise.
struct DisplayBrightnessSetting: Codable, Hashable {
    var mode: BrightnessMode?
    /// Software part of the brightness (1 = no dimming).
    var softwareLevel: Double = 1
}

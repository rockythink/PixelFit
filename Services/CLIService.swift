import CoreGraphics
import Foundation

enum CLIService {
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) {
        guard arguments.count > 1 else { return }
        let command = arguments[1]
        // Launch Services can pass Cocoa defaults when opening a GUI application.
        guard !command.hasPrefix("-NS"), !command.hasPrefix("-psn_") else { return }
        do {
            try run(command: command, arguments: Array(arguments.dropFirst(2)))
            Foundation.exit(0)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(command: String, arguments: [String]) throws {
        if ["help", "--help", "-h"].contains(command) {
            print("""
            PixelFit list
            PixelFit status
            PixelFit get [--index N] [--json]
            PixelFit diagnose [--index N|--all] [--json]
            Read-only diagnostics; diagnose also reads DDC/CI values. Use the app to change modes or monitor settings.
            """)
            return
        }
        guard ["list", "status", "get", "diagnose"].contains(command) else {
            throw MonitorControlError.unsupported("Unknown command: \(command)")
        }
        var index = 1
        var all = command == "list" || command == "status"
        var json = false
        var offset = 0
        while offset < arguments.count {
            switch arguments[offset] {
            case "--index":
                offset += 1
                guard offset < arguments.count, let value = Int(arguments[offset]), value > 0 else {
                    throw MonitorControlError.unsupported("--index requires a positive integer")
                }
                index = value
            case "--all": all = true
            case "--json": json = true
            default: throw MonitorControlError.unsupported("Unknown option: \(arguments[offset])")
            }
            offset += 1
        }
        var displays = DisplayDiscoveryService().discover(language: .system)
        let physical = PhysicalHiDPIService()
        var configurations: [DisplayOverrideKey: PhysicalHiDPIStatus] = [:]
        for position in displays.indices {
            let key = DisplayOverrideKey(display: displays[position])
            if configurations[key] == nil {
                do { configurations[key] = try physical.status(for: key) }
                catch { configurations[key] = PhysicalHiDPIStatus(phase: .conflict, problem: error.localizedDescription) }
            }
            displays[position].metadata.panelResolution = configurations[key]?.nativeResolution
        }
        let targets: [DisplayDevice]
        if all {
            targets = displays
        } else {
            guard index <= displays.count else {
                throw MonitorControlError.unsupported("Display index out of range: \(index)")
            }
            targets = [displays[index - 1]]
        }
        // DDC reads are I2C traffic to the monitor, so only diagnose performs them.
        let hardware = command == "diagnose" ? DDCService().readAllSync(targets) : [:]
        if json {
            let reports = targets.map {
                var report = DisplayReport($0, physical: configurations[DisplayOverrideKey(display: $0)] ?? PhysicalHiDPIStatus())
                if command == "diagnose", !$0.isBuiltin {
                    report.hardwareControls = Dictionary(uniqueKeysWithValues: (hardware[$0.id] ?? [:]).map { ($0.key.rawValue, $0.value) })
                }
                return report
            }
            let data = try JSONEncoder.pretty.encode(Report(displays: reports))
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        for display in targets {
            print("#\((displays.firstIndex(where: { $0.id == display.id }) ?? 0) + 1) \(display.shortName)")
            print("  id: \(display.id)")
            print("  current: \(display.currentMode?.detailLabel ?? "-")")
            print("  native: \(display.nativeMode?.detailLabel ?? "-")")
            print("  modes: \(display.availableModes.count)")
            let state = configurations[DisplayOverrideKey(display: display)] ?? PhysicalHiDPIStatus()
            let physicalReport = PhysicalConfigurationReport(display: display, status: state)
            print("  physical configuration: \(state.phase.rawValue); restorable: \(state.canRestore)")
            if let target = physicalReport.target { print("  physical HiDPI candidate: \(target.resolutionLabel); registered: \(physicalReport.registered)") }
            if let problem = state.problem { print("  configuration problem: \(problem)") }
            if command == "diagnose" {
                print("  frame: \(display.frame.cgRect)")
                if !display.isBuiltin {
                    let values = hardware[display.id] ?? [:]
                    let text = HardwareControl.allCases.compactMap { control in
                        values[control].map { "\(control.rawValue) \($0.current)/\($0.maximum)" }
                    }
                    print("  DDC/CI: \(text.isEmpty ? "no reply" : text.joined(separator: ", "))")
                }
                print("  mirrors: \(CGDisplayMirrorsDisplay(display.id))")
                print("  recommended HiDPI:")
                for mode in display.recommendedHiDPIModes { print("    \(mode.detailLabel)") }
                print("  experimental virtual resolutions:")
                for target in display.virtualHiDPITargets { print("    \(target.resolutionWithAspectLabel)") }
                print("  switchable modes:")
                for mode in display.menuSwitchModes { print("    \(mode.detailLabel)") }
            }
        }
    }

    private struct Report: Encodable {
        var displays: [DisplayReport]
    }

    private struct DisplayReport: Encodable {
        var id: UInt32
        var name: String
        var online: Bool
        var main: Bool
        var mirrorsDisplayID: UInt32
        var vendorHex: String
        var productHex: String
        var frame: CGRectCodable
        var nativeMode: ModeReport?
        var currentMode: ModeReport?
        var modeCount: Int
        var hidpiCount: Int
        var recommendedHiDPI: [ModeReport]
        var notExposedRecommended: [DisplayResolutionTarget]
        var virtualHiDPITargets: [DisplayResolutionTarget]
        var switchableModes: [ModeReport]
        var physicalConfiguration: PhysicalConfigurationReport
        /// Present for external displays in `diagnose`; empty when the monitor did not answer DDC/CI.
        var hardwareControls: [String: HardwareControlValue]?

        init(_ display: DisplayDevice, physical: PhysicalHiDPIStatus) {
            physicalConfiguration = PhysicalConfigurationReport(display: display, status: physical)
            id = display.id
            name = display.shortName
            online = display.isOnline
            main = display.metadata.isMain
            mirrorsDisplayID = CGDisplayMirrorsDisplay(display.id)
            vendorHex = display.metadata.vendorHex
            productHex = display.metadata.productHex
            frame = display.frame
            nativeMode = display.nativeMode.map(ModeReport.init)
            currentMode = display.currentMode.map(ModeReport.init)
            modeCount = display.availableModes.count
            hidpiCount = display.availableModes.filter(\.isHiDPI).count
            recommendedHiDPI = display.recommendedHiDPIModes.map(ModeReport.init)
            notExposedRecommended = display.unavailableRecommendedHiDPITargets
            virtualHiDPITargets = display.virtualHiDPITargets
            switchableModes = display.menuSwitchModes.map(ModeReport.init)
        }
    }

    private struct PhysicalConfigurationReport: Encodable {
        let phase: PhysicalHiDPIStatus.Phase
        let target: DisplayResolutionTarget?
        let nativeResolution: DisplayResolutionTarget?
        let registered: Bool
        let canRestore: Bool
        let problem: String?

        init(display: DisplayDevice, status: PhysicalHiDPIStatus) {
            phase = status.phase
            target = status.target ?? display.physicalHiDPIProbeTarget
            nativeResolution = status.nativeResolution
            canRestore = status.canRestore
            problem = status.problem
            if let target {
                registered = display.availableModes.contains {
                    $0.isHiDPI && $0.width == target.width && $0.height == target.height &&
                    $0.pixelWidth == target.width * 2 && $0.pixelHeight == target.height * 2
                }
            } else { registered = false }
        }
    }

    private struct ModeReport: Encodable {
        var modeID: Int32
        var cgsModeNumber: Int32?
        var width: Int
        var height: Int
        var pixelWidth: Int
        var pixelHeight: Int
        var refreshRate: Double
        var isHiDPI: Bool
        var source: DisplayModeSource
        var label: String

        init(_ mode: DisplayMode) {
            modeID = mode.modeID
            cgsModeNumber = mode.cgsModeNumber
            width = mode.width
            height = mode.height
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
            refreshRate = mode.refreshRate
            isHiDPI = mode.isHiDPI
            source = mode.source
            label = mode.detailLabel
        }
    }
}

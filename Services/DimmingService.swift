import AppKit
import CoreGraphics
import OSLog

private let dimmingLog = Logger(subsystem: "cc.ss-data.hidpibuddy", category: "dimming")

/// Software brightness for any display. Gamma scaling is the default; a black shade window is the
/// fallback when gamma cannot be used (no gamma table, or another app keeps rewriting it).
/// The approach follows MonitorControl (MIT, see THIRD_PARTY_NOTICES.md).
@MainActor
final class DimmingService {
    enum Backend: Equatable { case gamma, shade }

    /// Lowest multiplier, so a mistaken drag to 0 never leaves an unusable black screen.
    nonisolated static let floor = 0.15
    nonisolated static func multiplier(for level: Double) -> Double {
        floor + (1 - floor) * min(max(level, 0), 1)
    }

    /// Called when a display is moved to the shade backend because its gamma kept being overwritten.
    var onGammaInterference: ((UInt32) -> Void)?

    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var peak: CGGammaValue { max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0) }
    }

    private struct Animation {
        var from: Double
        var to: Double
        var start: TimeInterval
    }

    private var targets: [UInt32: Double] = [:]
    private var shown: [UInt32: Double] = [:]
    private var animations: [UInt32: Animation] = [:]
    private var animationTimer: Timer?
    private var originals: [UInt32: Table] = [:]
    private var resetColorSync = false
    private var shades: [UInt32: NSWindow] = [:]
    private var forcedShade: Set<UInt32> = []
    private var interference: [UInt32: Int] = [:]
    private var watchdog: Timer?
    private lazy var enforcer = makeEnforcer()

    private static let animationDuration = 0.15

    func backend(for displayID: UInt32) -> Backend {
        forcedShade.contains(displayID) || CGDisplayGammaTableCapacity(displayID) == 0 ? .shade : .gamma
    }

    /// `level` is the 0...1 software level (1 = untouched). Animated changes ease over 150 ms.
    func set(level: Double, for displayID: UInt32, animated: Bool) {
        let level = min(max(level, 0), 1)
        // Never touch a display PixelFit hasn't dimmed: no gamma capture, no ColorSync reset.
        if level >= 0.9999, targets[displayID] == nil { return }
        targets[displayID] = level
        let from = shown[displayID] ?? 1
        if animated, abs(from - level) > 0.001 {
            animations[displayID] = Animation(from: from, to: level, start: ProcessInfo.processInfo.systemUptime)
            startAnimationTimer()
        } else {
            animations[displayID] = nil
            render(level, on: displayID)
        }
        updateWatchdog()
    }

    /// Re-applies every target without animation, e.g. after macOS reset gamma on reconfiguration or wake.
    func reapplyAll() {
        for (id, level) in targets {
            animations[id] = nil
            render(level, on: id)
        }
    }

    /// Returns the display to its unmodified state and forgets it.
    func remove(_ displayID: UInt32) {
        animations[displayID] = nil
        targets[displayID] = nil
        shown[displayID] = nil
        restoreGamma(displayID)
        removeShade(displayID)
        updateWatchdog()
    }

    func restoreAll() {
        for id in Set(targets.keys).union(originals.keys).union(shades.keys) { remove(id) }
    }

    // MARK: Rendering

    private func render(_ level: Double, on displayID: UInt32) {
        shown[displayID] = level
        switch backend(for: displayID) {
        case .gamma:
            removeShade(displayID)
            applyGamma(level, on: displayID)
        case .shade:
            restoreGamma(displayID)
            applyShade(level, on: displayID)
        }
    }

    private func applyGamma(_ level: Double, on displayID: UInt32) {
        guard let original = original(for: displayID) else {
            forcedShade.insert(displayID)
            applyShade(level, on: displayID)
            return
        }
        let scale = CGGammaValue(Self.multiplier(for: level))
        _ = CGSetDisplayTransferByTable(displayID, UInt32(original.red.count),
                                        original.red.map { $0 * scale }, original.green.map { $0 * scale },
                                        original.blue.map { $0 * scale })
        nudgeWindowServer(on: displayID)
    }

    private func restoreGamma(_ displayID: UInt32) {
        guard let original = originals.removeValue(forKey: displayID) else { return }
        _ = CGSetDisplayTransferByTable(displayID, UInt32(original.red.count), original.red, original.green, original.blue)
        nudgeWindowServer(on: displayID)
    }

    private func original(for displayID: UInt32) -> Table? {
        if let table = originals[displayID] { return table }
        // A previous run that quit abnormally may have left a dimmed table; start from the profile.
        // Never re-capture later: that could record PixelFit's own dimmed table as the original.
        if !resetColorSync {
            CGDisplayRestoreColorSyncSettings()
            resetColorSync = true
        }
        let capacity = Int(CGDisplayGammaTableCapacity(displayID))
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, UInt32(capacity), &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        let table = Table(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
        originals[displayID] = table
        return table
    }

    // MARK: Watchdog

    /// Gamma set by PixelFit silently disappears when the system restores ColorSync (another app
    /// that touched gamma quits, a profile changes) or when another app writes its own table.
    /// While any display is dimmed through gamma, verify it every 1.5 s.
    private func updateWatchdog() {
        let needed = targets.contains { $0.value < 0.9999 && backend(for: $0.key) == .gamma }
        if needed, watchdog == nil {
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.verifyGamma() }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        } else if !needed {
            watchdog?.invalidate()
            watchdog = nil
        }
    }

    private func verifyGamma() {
        for (id, level) in shown where animations[id] == nil && level < 0.9999 && backend(for: id) == .gamma {
            guard let original = originals[id], let current = currentTable(id) else { continue }
            let scale = CGGammaValue(Self.multiplier(for: level))
            if Self.table(current, matches: original, scale: scale) { continue }
            if Self.table(current, matches: original, scale: 1) {
                dimmingLog.info("display \(id): gamma was reset to the profile; re-applying")
                render(level, on: id)
                continue
            }
            // A different curve: another app (f.lux and similar) is writing gamma too.
            interference[id, default: 0] += 1
            dimmingLog.info("display \(id): foreign gamma table (\(self.interference[id, default: 0]))")
            if interference[id, default: 0] >= 3 {
                // Fighting over the table would flicker; an overlay can coexist with the other app.
                forcedShade.insert(id)
                originals[id] = nil
                onGammaInterference?(id)
            }
            render(level, on: id)
        }
        updateWatchdog()
    }

    private func currentTable(_ displayID: UInt32) -> Table? {
        var red = [CGGammaValue](repeating: 0, count: 1024), green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, 1024, &red, &green, &blue, &count) == .success, count > 0 else { return nil }
        let n = Int(count)
        return Table(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    /// Compares a few samples per channel; tables of different lengths are compared by position.
    nonisolated private static func table(_ current: Table, matches original: Table, scale: CGGammaValue) -> Bool {
        for (now, base) in [(current.red, original.red), (current.green, original.green), (current.blue, original.blue)] {
            guard !now.isEmpty, !base.isEmpty else { return false }
            for position in [0.25, 0.5, 0.75, 1.0] {
                let a = now[min(now.count - 1, Int(Double(now.count - 1) * position))]
                let b = base[min(base.count - 1, Int(Double(base.count - 1) * position))] * scale
                if abs(a - b) > 0.02 { return false }
            }
        }
        return true
    }

    // MARK: Shade

    private func applyShade(_ level: Double, on displayID: UInt32) {
        // A mirrored display has no screen of its own; its content comes from the mirror master.
        let screenID = CGDisplayMirrorsDisplay(displayID) != 0 ? CGDisplayMirrorsDisplay(displayID) : displayID
        guard let screen = Self.screen(for: screenID) else {
            dimmingLog.error("display \(displayID): no screen for shade (screen \(screenID))")
            return
        }
        let alpha = 1 - Self.multiplier(for: level)
        if alpha < 0.001 {
            removeShade(displayID)
            return
        }
        let shade = shades[displayID] ?? makeShade()
        shades[displayID] = shade
        shade.setFrame(screen.frame, display: false)
        shade.alphaValue = alpha
        shade.orderFrontRegardless()
        dimmingLog.info("display \(displayID): shade alpha \(alpha, format: .fixed(precision: 3)) visible=\(shade.isVisible)")
    }

    private func removeShade(_ displayID: UInt32) {
        shades.removeValue(forKey: displayID)?.orderOut(nil)
    }

    private func makeShade() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Screenshots and screen sharing see the real content, not the dimming layer.
        window.sharingType = .none
        return window
    }

    // MARK: Gamma activity enforcer

    /// On Apple Silicon a new gamma table can wait for the next WindowServer redraw. Toggling a
    /// 1-pixel, nearly invisible window on that screen forces the redraw (MonitorControl's technique).
    private func nudgeWindowServer(on displayID: UInt32) {
        guard let screen = Self.screen(for: displayID) else { return }
        enforcer.setFrameOrigin(screen.frame.origin)
        enforcer.orderFrontRegardless()
        enforcer.alphaValue = enforcer.alphaValue < 0.015 ? 0.02 : 0.01
    }

    private func makeEnforcer() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        window.sharingType = .none
        return window
    }

    // MARK: Animation

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, animation) in animations {
            let progress = min((now - animation.start) / Self.animationDuration, 1)
            let eased = 1 - pow(1 - progress, 3)
            render(animation.from + (animation.to - animation.from) * eased, on: id)
            if progress >= 1 { animations[id] = nil }
        }
        if animations.isEmpty {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private static func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}

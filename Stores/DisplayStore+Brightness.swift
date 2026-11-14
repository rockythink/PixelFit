import AppKit
import CoreGraphics
import Foundation

/// Hardware controls (DDC/CI), the brightness engine (hardware / combined / software) and media keys.
extension DisplayStore {
    // MARK: Identity & modes

    func settingsKey(for display: DisplayDevice) -> String {
        "\(display.vendorID)-\(display.modelID)-\(display.serialNumber)"
    }

    private func display(_ id: UInt32) -> DisplayDevice? {
        displays.first { $0.id == id }
    }

    /// Built-in panels and Apple displays use the system's own brightness, not DDC or gamma.
    func usesAppleBrightness(_ displayID: UInt32) -> Bool {
        appleBrightness[displayID] != nil
    }

    /// The user's explicit choice; nil = automatic.
    func brightnessModeSetting(for displayID: UInt32) -> BrightnessMode? {
        display(displayID).flatMap { brightnessSettings[settingsKey(for: $0)]?.mode }
    }

    /// The mode actually in effect, or nil while DDC is still being probed (or for Apple displays).
    func effectiveBrightnessMode(for displayID: UInt32) -> BrightnessMode? {
        guard !usesAppleBrightness(displayID) else { return nil }
        let explicit = brightnessModeSetting(for: displayID)
        if explicit == .software { return .software }
        let state = hardware[displayID]
        if state?.values[.brightness] != nil { return explicit ?? .combined }
        // No DDC brightness answer: software dimming is the only way to change brightness.
        return state?.phase == .probing || state == nil ? nil : .software
    }

    private func softwareLevel(_ displayID: UInt32) -> Double {
        display(displayID).flatMap { brightnessSettings[settingsKey(for: $0)]?.softwareLevel } ?? 1
    }

    /// The single user-facing brightness, whatever mix of DDC and software realizes it.
    func brightnessLevel(for displayID: UInt32) -> Double? {
        if let apple = appleBrightness[displayID] { return apple }
        guard let mode = effectiveBrightnessMode(for: displayID) else { return nil }
        return BrightnessSplit.level(ddc: hardware[displayID]?.values[.brightness]?.fraction,
                                     software: softwareLevel(displayID), mode: mode)
    }

    /// Current 0...1 value of a control, as shown on sliders and the HUD.
    func controlFraction(_ control: HardwareControl, for displayID: UInt32) -> Double? {
        control == .brightness ? brightnessLevel(for: displayID) : hardware[displayID]?.values[control]?.fraction
    }

    /// Changing the mode keeps the perceived brightness and re-splits it between DDC and software.
    func setBrightnessMode(_ mode: BrightnessMode?, for displayID: UInt32) {
        guard let display = display(displayID) else { return }
        let level = brightnessLevel(for: displayID) ?? 1
        let key = settingsKey(for: display)
        var setting = brightnessSettings[key] ?? DisplayBrightnessSetting()
        setting.mode = mode
        brightnessSettings[key] = setting
        setBrightness(level, for: displayID, animated: true)
        persist()
    }

    // MARK: Applying brightness

    /// Sliders call this continuously; keys pass `animated` for a short software fade.
    func setBrightness(_ level: Double, for displayID: UInt32, animated: Bool = false) {
        let level = min(max(level, 0), 1)
        if usesAppleBrightness(displayID) {
            if AppleBrightnessService.setBrightness(level, for: displayID) { appleBrightness[displayID] = level }
            return
        }
        guard let display = display(displayID), let mode = effectiveBrightnessMode(for: displayID) else { return }
        let parts = BrightnessSplit.parts(level: level, mode: mode)
        if let ddc = parts.ddc {
            writeHardware(.brightness, fraction: ddc, for: displayID)
        }
        let key = settingsKey(for: display)
        var setting = brightnessSettings[key] ?? DisplayBrightnessSetting()
        if abs(setting.softwareLevel - parts.software) > 0.0001 {
            setting.softwareLevel = parts.software
            brightnessSettings[key] = setting
            persistSoon()
        }
        dimming.set(level: parts.software, for: displayID, animated: animated)
    }

    /// Re-applies the software part of every display. Idempotent; cheap enough for every refresh.
    func applySoftwareBrightness() {
        for display in displays where !usesAppleBrightness(display.id) {
            guard let mode = effectiveBrightnessMode(for: display.id) else { continue }
            let software = mode == .hardware ? 1 : softwareLevel(display.id)
            dimming.set(level: software, for: display.id, animated: false)
        }
    }

    /// Sliders and other callers; brightness goes through the engine, other controls straight to DDC.
    func setHardwareControl(_ control: HardwareControl, fraction: Double, for displayID: UInt32) {
        if control == .brightness {
            setBrightness(fraction, for: displayID)
        } else {
            writeHardware(control, fraction: fraction, for: displayID)
        }
    }

    // MARK: DDC

    /// Re-matches DDC services when the set of physical displays changes. Mode switches also
    /// trigger refreshDisplays and must not cause a burst of reads, so they only re-attach.
    func refreshHardwareControls() {
        refreshAppleBrightness()
        let identities = Dictionary(uniqueKeysWithValues: displays.filter { !$0.isBuiltin }.map { ($0.id, settingsKey(for: $0)) })
        if identities != hardwareIdentities {
            hardwareIdentities = identities
            probeHardwareControls()
        } else {
            scheduleDDCReattach()
        }
    }

    private func refreshAppleBrightness() {
        var values: [UInt32: Double] = [:]
        for display in displays where display.isBuiltin || display.vendorID == 0x610 {
            if let value = AppleBrightnessService.brightness(display.id) { values[display.id] = value }
        }
        if values != appleBrightness { appleBrightness = values }
    }

    /// Link retraining after a mode change can replace the AV service object; re-match quietly.
    private func scheduleDDCReattach() {
        ddcReattachTask?.cancel()
        let targets = displays.filter { !$0.isBuiltin && !usesAppleBrightness($0.id) }
        ddcReattachTask = Task { [weak self, ddc] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, self?.ddcPaused == false else { return }
            await ddc.attach(targets)
        }
    }

    /// Re-reads values the user may have changed with the monitor's own buttons. Throttled.
    func rereadHardwareControls() {
        refreshAppleBrightness()
        guard Date().timeIntervalSince(lastHardwareReread) > 5, hardwareWritesInFlight.isEmpty, !ddcPaused else { return }
        probeHardwareControls()
    }

    func probeHardwareControls() {
        lastHardwareReread = Date()
        hardwareProbeTask?.cancel()
        let targets = displays.filter { !$0.isBuiltin && !usesAppleBrightness($0.id) }
        hardware = hardware.filter { id, _ in targets.contains { $0.id == id } }
        for display in targets where hardware[display.id] == nil {
            hardware[display.id] = DisplayHardwareState()
        }
        hardwareProbeTask = Task { [weak self, ddc] in
            await ddc.attach(targets)
            for display in targets {
                let values = await ddc.readAll(displayID: display.id)
                guard !Task.isCancelled, let self else { return }
                // A slider write that started during the read wins over the stale reading.
                guard !self.hardwareWritesInFlight.contains(where: { $0.displayID == display.id }) else { continue }
                self.hardware[display.id] = DisplayHardwareState(phase: values.isEmpty ? .unavailable : .ready, values: values)
            }
            // Modes resolve once DDC answers (or doesn't); apply saved software levels now.
            self?.applySoftwareBrightness()
        }
    }

    /// Updates the UI immediately and coalesces writes, so dragging a slider sends only the latest value.
    private func writeHardware(_ control: HardwareControl, fraction: Double, for displayID: UInt32) {
        guard let value = hardware[displayID]?.values[control]?.with(fraction: fraction),
              value != hardware[displayID]?.values[control] else { return }
        hardware[displayID]?.values[control] = value
        guard !ddcPaused else { return }
        let key = HardwareWriteKey(displayID: displayID, control: control)
        queuedHardwareWrites[key] = value.current
        guard !hardwareWritesInFlight.contains(key) else { return }
        hardwareWritesInFlight.insert(key)
        Task { [weak self, ddc] in
            while let self, !self.ddcPaused, let next = self.queuedHardwareWrites.removeValue(forKey: key) {
                do {
                    try await ddc.write(control, value: next, displayID: displayID)
                } catch {
                    self.lastError = error.localizedDescription
                    self.queuedHardwareWrites[key] = nil
                    break
                }
            }
            self?.hardwareWritesInFlight.remove(key)
        }
    }

    // MARK: Sleep, wake and reconfiguration

    func installPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            // Monitors drop or garble DDC while their link is going down.
            MainActor.assumeIsolated { self?.ddcPaused = true }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeAfterWake() }
            })
        }
        dimming.onGammaInterference = { [weak self] _ in
            guard let self else { return }
            self.statusMessage = L10n.t("dimming.interference", self.language)
        }
    }

    /// macOS resets gamma on wake and the DDC link needs a moment to come back.
    private func resumeAfterWake() {
        dimming.reapplyAll()
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.ddcPaused = false
            self.dimming.reapplyAll()
            self.lastHardwareReread = .distantPast
            self.probeHardwareControls()
        }
    }

    // MARK: Media keys

    func setMediaKeysEnabled(_ enabled: Bool) {
        mediaKeysEnabled = enabled
        updateMediaKeyMonitoring()
        persist()
    }

    func requestAccessibilityTrust() {
        MediaKeyService.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts the event tap when allowed; while permission is missing, polls so that granting it
    /// in System Settings takes effect without relaunching.
    func updateMediaKeyMonitoring() {
        accessibilityTrusted = MediaKeyService.isTrusted
        trustPollTimer?.invalidate()
        trustPollTimer = nil
        guard mediaKeysEnabled else {
            mediaKeys.stop()
            return
        }
        if accessibilityTrusted {
            if !mediaKeys.isRunning {
                mediaKeys.start { [weak self] key, fine in self?.handleMediaKey(key, fineStep: fine) ?? false }
            }
        } else {
            mediaKeys.stop()
            trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, MediaKeyService.isTrusted else { return }
                    self.updateMediaKeyMonitoring()
                }
            }
        }
    }

    private static let conflictingBundleIDs = [
        "app.monitorcontrol.MonitorControl": "MonitorControl",
        "pro.betterdisplay.BetterDisplay": "BetterDisplay",
        "fyi.lunar.Lunar": "Lunar"
    ]

    func refreshConflictingApps() {
        let running = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        let found = Self.conflictingBundleIDs.filter { running.contains($0.key) }.map(\.value).sorted()
        if found != conflictingApps { conflictingApps = found }
    }

    /// Returns true when PixelFit applied the key; otherwise the system keeps handling it
    /// (built-in and Apple displays, speakers, headphones).
    private func handleMediaKey(_ key: MediaKey, fineStep: Bool) -> Bool {
        switch key {
        case .brightnessUp, .brightnessDown:
            guard let display = displayUnderPointer() else {
                mediaKeyLog.info("pass: pointer is not over a known display")
                return false
            }
            guard !usesAppleBrightness(display.id) else {
                mediaKeyLog.info("pass: \(display.name, privacy: .public) uses system brightness")
                return false
            }
            guard brightnessLevel(for: display.id) != nil else {
                mediaKeyLog.info("pass: \(display.name, privacy: .public) has no brightness control yet")
                return false
            }
            mediaKeyLog.info("brightness -> \(display.name, privacy: .public)")
            step(.brightness, on: display, up: key == .brightnessUp, fine: fineStep)
            return true
        case .volumeUp, .volumeDown, .mute:
            guard let output = AudioOutputService.defaultOutput(),
                  let display = displays.first(where: {
                      hardware[$0.id]?.values[.volume] != nil && AudioOutputService.device(output, belongsTo: $0)
                  }) else {
                mediaKeyLog.info("pass: audio output is not a DDC display")
                return false
            }
            if key == .mute {
                toggleMute(on: display)
            } else {
                step(.volume, on: display, up: key == .volumeUp, fine: fineStep)
            }
            return true
        }
    }

    private func displayUnderPointer() -> DisplayDevice? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return displays.first { $0.id == id }
    }

    /// 16 steps per range like the system keys, 64 with ⌥⇧; values snap onto that grid.
    private func step(_ control: HardwareControl, on display: DisplayDevice, up: Bool, fine: Bool) {
        guard let current = controlFraction(control, for: display.id) else { return }
        let steps = fine ? 64.0 : 16.0
        let target = min(max(((current * steps).rounded() + (up ? 1 : -1)) / steps, 0), 1)
        if control == .brightness {
            setBrightness(target, for: display.id, animated: true)
        } else {
            writeHardware(control, fraction: target, for: display.id)
            volumesBeforeMute[display.id] = nil
        }
        showHUD(control, on: display)
    }

    private func toggleMute(on display: DisplayDevice) {
        guard let current = hardware[display.id]?.values[.volume] else { return }
        if current.current > 0 {
            volumesBeforeMute[display.id] = current.fraction
            writeHardware(.volume, fraction: 0, for: display.id)
        } else {
            writeHardware(.volume, fraction: volumesBeforeMute.removeValue(forKey: display.id) ?? 0.5, for: display.id)
        }
        showHUD(.volume, on: display)
    }

    private func showHUD(_ control: HardwareControl, on display: DisplayDevice) {
        guard let fraction = controlFraction(control, for: display.id) else { return }
        let value = HardwareControlValue(current: UInt16((fraction * 100).rounded()), maximum: 100)
        controlHUD.show(control, value: value, displayName: display.shortName(language: language), displayID: display.id)
    }
}

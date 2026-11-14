import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

let mediaKeyLog = Logger(subsystem: "cc.ss-data.hidpibuddy", category: "media-keys")

enum MediaKey: Hashable {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case mute

    /// NX_KEYTYPE_* codes carried in NSSystemDefined (subtype 8) events.
    init?(nxKeyType: Int) {
        switch nxKeyType {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        case 7: self = .mute
        default: return nil
        }
    }

    /// Decodes `data1` of an NSSystemDefined media-key event. Only key-down (and its repeats) counts.
    static func decode(data1: Int) -> (key: MediaKey, isDown: Bool)? {
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0xFF00) >> 8
        guard let key = MediaKey(nxKeyType: keyType) else { return nil }
        return (key, keyState == 0x0A)
    }
}

/// Intercepts brightness / volume keys with a session event tap. Swallowing an event requires
/// Accessibility permission; without it the tap cannot be created and keys keep their system role.
@MainActor
final class MediaKeyService {
    /// Return true to consume the key (the system then shows no HUD and does not act on it).
    typealias Handler = @MainActor (_ key: MediaKey, _ fineStep: Bool) -> Bool

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: Handler?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that links to Privacy & Security > Accessibility.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        stop()
        guard Self.isTrusted else { return false }
        self.handler = handler
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        handler = nil
    }

    /// Runs on the main run loop, where the tap's source is installed.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let service = Unmanaged<MediaKeyService>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated { service.handle(type: type, event: event) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8,
              let decoded = MediaKey.decode(data1: nsEvent.data1), let handler else {
            return Unmanaged.passUnretained(event)
        }
        // macOS convention: ⌥⇧ with a brightness/volume key moves in quarter steps. Media key events
        // don't reliably carry modifier flags, so the live keyboard state counts too.
        let modifiers = nsEvent.modifierFlags.union(NSEvent.modifierFlags)
        let fine = modifiers.contains([.option, .shift])
        if decoded.isDown {
            mediaKeyLog.info("key \(String(describing: decoded.key), privacy: .public) down fine=\(fine)")
            guard handler(decoded.key, fine) else {
                consumedKeys.remove(decoded.key)
                return Unmanaged.passUnretained(event)
            }
            consumedKeys.insert(decoded.key)
            return nil
        }
        // A key-up is swallowed only when its key-down was, so the system never sees half a press.
        return consumedKeys.remove(decoded.key) != nil ? nil : Unmanaged.passUnretained(event)
    }

    private var consumedKeys: Set<MediaKey> = []
}

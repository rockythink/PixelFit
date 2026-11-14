import CoreGraphics
import Darwin

/// Native brightness for built-in panels and Apple displays (Studio Display, Pro Display XDR,
/// LG UltraFine), which do not speak DDC/CI. Uses the private DisplayServices framework, resolved
/// at runtime so a missing symbol only disables the feature.
enum AppleBrightnessService {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let canChange: CanChange? = symbol("DisplayServicesCanChangeBrightness")
    private static let get: Get? = symbol("DisplayServicesGetBrightness")
    private static let set: Set? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func isSupported(_ displayID: CGDirectDisplayID) -> Bool {
        guard let canChange, get != nil, set != nil else { return false }
        return canChange(displayID)
    }

    static func brightness(_ displayID: CGDirectDisplayID) -> Double? {
        guard isSupported(displayID), let get else { return nil }
        var value: Float = 0
        guard get(displayID, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }

    @discardableResult
    static func setBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
        guard isSupported(displayID), let set else { return false }
        return set(displayID, Float(min(max(value, 0), 1))) == 0
    }
}

import CoreFoundation
import Foundation

/// Producing these bytes only requests a mode; it does not prove macOS exposes it.
enum PhysicalHiDPIConfiguration {
    static func validate(target: DisplayResolutionTarget, native: DisplayResolutionTarget) throws {
        // Keep arithmetic bounded before multiplication, including hostile Int.max inputs.
        guard target.width > 0, target.height > 0, native.width > 0, native.height > 0,
              target.width <= 8192, target.height <= 8192,
              native.width <= 16384, native.height <= 16384,
              target.width * 2 * target.height * 2 <= 67_108_864,
              native.width * native.height <= 67_108_864,
              target.width * native.height == target.height * native.width else {
            throw LocalizedServiceError(key: "physical.error.invalidResolution")
        }
    }

    static func generate(existing: Data?, key: DisplayOverrideKey,
                         target: DisplayResolutionTarget, native: DisplayResolutionTarget) throws -> Data {
        try validate(target: target, native: native)
        guard key.vendorID > 0, key.productID > 0 else {
            throw LocalizedServiceError(key: "physical.error.missingIDs")
        }
        var dictionary: [String: Any] = [:]
        if let existing {
            let plist = try PropertyListSerialization.propertyList(from: existing, options: [], format: nil)
            guard let fields = plist as? [String: Any] else {
                throw LocalizedServiceError(key: "physical.error.arrayOverride")
            }
            dictionary = fields
        }
        for (field, expected) in [("DisplayVendorID", key.vendorID), ("DisplayProductID", key.productID)] {
            if let value = dictionary[field] {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue == Double(expected) else {
                    throw LocalizedServiceError(key: "physical.error.fieldConflict", arguments: [field])
                }
            } else {
                dictionary[field] = NSNumber(value: expected)
            }
        }
        var entries: [Data] = []
        if let value = dictionary["scale-resolutions"] {
            guard let dataEntries = value as? [Data] else {
                throw LocalizedServiceError(key: "physical.error.scaleResolutions")
            }
            entries = dataEntries
        }
        if let value = dictionary["target-default-ppmm"] {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue > 0 else {
                throw LocalizedServiceError(key: "physical.error.ppmm")
            }
        }
        let nativeBytes = pixelDimensions(width: native.width, height: native.height)
        if let existingDimensions = dictionary["DisplayPixelDimensions"] {
            guard let data = existingDimensions as? Data, data == nativeBytes else {
                throw LocalizedServiceError(key: "physical.error.panelMismatch")
            }
        } else {
            dictionary["DisplayPixelDimensions"] = nativeBytes
        }
        let targetBytes = pixelDimensions(width: target.width * 2, height: target.height * 2)
        if !entries.contains(targetBytes) { entries.append(targetBytes) }
        dictionary["scale-resolutions"] = entries
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    /// Both fields are unsigned 32-bit big-endian pixels, never logical points.
    private static func pixelDimensions(width: Int, height: Int) -> Data {
        var packed = ((UInt64(width) << 32) | UInt64(height)).bigEndian
        return withUnsafeBytes(of: &packed) { Data($0) }
    }
}

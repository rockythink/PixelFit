import CoreAudio
import Foundation

/// Reads the system default output device, so volume keys go to a monitor only while
/// macOS is actually playing through that monitor (DisplayPort / HDMI audio).
enum AudioOutputService {
    struct Device: Equatable {
        var name: String
        var isDisplayAudio: Bool
    }

    static func defaultOutput() -> Device? {
        var deviceID = AudioDeviceID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &deviceID),
              deviceID != kAudioObjectUnknown else { return nil }
        var transport = UInt32(0)
        _ = read(deviceID, kAudioDevicePropertyTransportType, into: &transport)
        var name: Unmanaged<CFString>?
        guard read(deviceID, kAudioObjectPropertyName, into: &name), let name else { return nil }
        return Device(
            name: name.takeRetainedValue() as String,
            isDisplayAudio: transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
        )
    }

    /// Display audio devices are named after the monitor's EDID product name.
    static func device(_ device: Device, belongsTo display: DisplayDevice) -> Bool {
        guard device.isDisplayAudio else { return false }
        let names = [display.metadata.productName, display.name].compactMap { $0 }.filter { !$0.isEmpty }
        return names.contains { device.name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(device.name) }
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }
}

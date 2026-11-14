import SwiftUI

/// System Settings–style row icon: a white symbol on a rounded, softly graded color tile.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.56, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icons shared by the main window, menu bar panel and Settings so the same concept looks the same.
enum RowIcon {
    static let resolution = ("rectangle.arrowtriangle.2.outward", Color.blue)
    static let refreshRate = ("gauge.with.dots.needle.67percent", Color.green)
    static let panel = ("display", Color.gray)
    static let brightnessMode = ("slider.horizontal.3", Color.teal)
    static let language = ("globe", Color.blue)
    static let login = ("power", Color.green)
    static let dock = ("dock.rectangle", Color.gray)
    static let keyboard = ("keyboard", Color.gray)

    static func control(_ control: HardwareControl) -> (String, Color) {
        switch control {
        case .brightness: ("sun.max.fill", .orange)
        case .contrast: ("circle.lefthalf.filled", .indigo)
        case .volume: ("speaker.wave.2.fill", .pink)
        }
    }
}

extension SettingsIcon {
    init(_ icon: (String, Color), size: CGFloat = 20) {
        self.init(systemName: icon.0, color: icon.1, size: size)
    }
}

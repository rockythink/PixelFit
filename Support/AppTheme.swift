import AppKit
import SwiftUI

enum AppTheme {
    // Color(nsColor: .controlAccentColor) rendered as red when used as a tint; accentColor follows the system setting.
    static let accent = Color.accentColor
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.65)
}

import AppKit
import ImageIO
import SwiftUI

/// Display arrangement drawn like System Settings: each screen shows its own desktop picture,
/// scaled to the real layout. Clicking selects a display; it never changes the arrangement.
struct DisplayArrangementView: View {
    let displays: [DisplayDevice]
    @Binding var selectedDisplayID: UInt32?
    let language: AppLanguage
    var height: CGFloat = 74

    var body: some View {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame.cgRect) }
        GeometryReader { geometry in
            if !bounds.isNull, bounds.width > 0, bounds.height > 0 {
                // Leave room for the selection ring and a small gap between screens.
                let scale = min((geometry.size.width - 16) / bounds.width, (geometry.size.height - 16) / bounds.height)
                let offsetX = (geometry.size.width - bounds.width * scale) / 2
                let offsetY = (geometry.size.height - bounds.height * scale) / 2
                ForEach(displays) { display in
                    let selected = display.id == selectedDisplayID
                    Button {
                        selectedDisplayID = display.id
                    } label: {
                        ScreenThumbnail(display: display, selected: selected, language: language)
                            .frame(width: max(display.frame.width * scale - 6, 10), height: max(display.frame.height * scale - 6, 10))
                    }
                    .buttonStyle(.plain)
                    .position(x: offsetX + (display.frame.x - bounds.minX + display.frame.width / 2) * scale,
                              y: offsetY + (display.frame.y - bounds.minY + display.frame.height / 2) * scale)
                    .accessibilityLabel(display.shortName(language: language) + (display.metadata.isMain ? " · " + L10n.t("display.main", language) : ""))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(display.shortName(language: language))
                }
            }
        }
        .frame(height: height)
    }
}

private struct ScreenThumbnail: View {
    let display: DisplayDevice
    let selected: Bool
    let language: AppLanguage
    @State private var wallpaper: NSImage?
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            if let wallpaper {
                Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(red: 0.20, green: 0.27, blue: 0.62), Color(red: 0.42, green: 0.25, blue: 0.58)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay(alignment: .top) {
            // The menu bar marks the main display, as in System Settings.
            if display.metadata.isMain {
                Rectangle().fill(.white.opacity(0.55)).frame(height: 3)
            }
        }
        .overlay(alignment: .bottom) {
            Text(display.shortName(language: language))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .padding(5)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        .padding(2.5)
        .overlay(RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.5) : .clear), lineWidth: 2.5))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: selected)
        .task(id: display.id) { wallpaper = await WallpaperCache.shared.image(for: display.id) }
    }
}

/// Small, downsampled desktop pictures; wallpapers can be 6K HEIC files.
@MainActor
final class WallpaperCache {
    static let shared = WallpaperCache()
    private var images: [URL: NSImage] = [:]

    func image(for displayID: UInt32) async -> NSImage? {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cached = images[url] { return cached }
        let image = await Task.detached(priority: .utility) { Self.thumbnail(url, maxPixel: 480) }.value
        if let image { images[url] = image }
        return image
    }

    nonisolated private static func thumbnail(_ url: URL, maxPixel: Int) -> NSImage? {
        // Folders (rotating pictures) and dynamic wallpaper bundles fall back to the gradient.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

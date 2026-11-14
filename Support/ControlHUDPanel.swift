import AppKit
import SwiftUI

/// Brightness / volume feedback shown on the monitor that changed, in place of the system HUD
/// that macOS cannot show for DDC-controlled displays.
@MainActor
final class ControlHUDPanel {
    private var panel: NSPanel?
    private let model = ControlHUDModel()
    private var hideTask: Task<Void, Never>?

    func show(_ control: HardwareControl, value: HardwareControlValue, displayName: String, displayID: UInt32) {
        model.control = control
        model.displayName = displayName
        model.isMuted = control == .volume && value.current == 0
        withAnimation(.snappy(duration: 0.18)) {
            model.fraction = value.fraction
            model.isVisible = true
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, on: displayID)
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.model.isVisible = false }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: ControlHUDView(model: model))
        hosting.safeAreaRegions = []
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: ControlHUDView.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Top-right under the menu bar, where macOS places its own control HUDs.
    private func position(_ panel: NSPanel, on displayID: UInt32) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = ControlHUDView.panelSize
        panel.setFrame(NSRect(x: frame.maxX - size.width - 8, y: frame.maxY - size.height - 4,
                              width: size.width, height: size.height), display: false)
    }
}

@Observable
@MainActor
private final class ControlHUDModel {
    var control: HardwareControl = .brightness
    var displayName = ""
    var fraction = 0.0
    var isMuted = false
    var isVisible = false
}

private struct ControlHUDView: View {
    static let panelSize = NSSize(width: 316, height: 92)
    let model: ControlHUDModel

    private var symbol: String {
        switch model.control {
        case .brightness: model.fraction < 0.34 ? "sun.min.fill" : "sun.max.fill"
        case .contrast: "circle.lefthalf.filled"
        case .volume:
            model.isMuted ? "speaker.slash.fill"
                : model.fraction < 0.34 ? "speaker.wave.1.fill"
                : model.fraction < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t(model.control.titleKey))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.12))
                        Capsule().fill(.primary)
                            .frame(width: max(6, proxy.size.width * model.fraction))
                    }
                }
                .frame(height: 6)
                Text(verbatim: "\(Int((model.fraction * 100).rounded()))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .opacity(model.isVisible ? 1 : 0)
        .offset(y: model.isVisible ? 0 : -6)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .accessibilityElement(children: .combine)
    }
}

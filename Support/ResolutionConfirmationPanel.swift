import AppKit
import SwiftUI

/// Floating keep/restore prompt on the display being changed. The menu bar window closes when
/// screens reconfigure and the main window may be elsewhere, so the countdown needs its own window.
@MainActor
final class ResolutionConfirmationPanel {
    private var panel: NSPanel?
    private var displayIDs: [UInt32] = []
    private var screenParametersObserver: NSObjectProtocol?

    /// `displayIDs` are tried in order; a mirrored display has no NSScreen of its own.
    func show(store: DisplayStore, on displayIDs: [UInt32]) {
        self.displayIDs = displayIDs
        let panel = panel ?? makePanel(store: store)
        self.panel = panel
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // The target screen's frame changes after the mode switch lands.
        screenParametersObserver = screenParametersObserver ?? NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.position(panel)
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        displayIDs = []
    }

    private func makePanel(store: DisplayStore) -> NSPanel {
        let hosting = NSHostingView(rootView: ResolutionConfirmationView(store: store))
        // The titlebar is transparent and buttonless; don't reserve or size for its safe area.
        hosting.safeAreaRegions = []
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                 styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        panel.contentView = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            panel.standardWindowButton($0)?.isHidden = true
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screens = NSScreen.screens
        let screen = displayIDs.lazy.compactMap { id in
            screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        }.first ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        if let size = panel.contentView?.fittingSize { panel.setContentSize(size) }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.maxY - size.height - frame.height * 0.18))
    }
}

/// A titled panel without standard buttons still has to accept key focus for Return / Esc.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

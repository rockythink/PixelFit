import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DisplayStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 300
    @State private var physicalConfigurationRequestID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(L10n.t("app.name", store.language)).font(.system(size: 14, weight: .semibold))
                Spacer()
                PresetApplyMenu(store: store)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .controlSize(.small)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.virtualSession != nil {
                        ResolutionChangeControls(store: store)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if store.displays.isEmpty {
                        Text(L10n.t("empty.noDisplay", store.language)).foregroundStyle(.secondary)
                    }
                    ForEach(store.displays.indices, id: \.self) { index in
                        displayPanel(store.displays[index], number: index + 1)
                    }

                    if !store.conflictingApps.isEmpty {
                        Label(String(format: L10n.t("conflict.running", store.language), store.conflictingApps.joined(separator: ", ")),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, maximumContentHeight))
            Divider()
            HStack(spacing: 10) {
                Button(L10n.t("menu.openMain", store.language)) {
                    AppWindowController.showMainWindow { openWindow(id: "main") }
                }
                Button {
                    // Without a Dock icon the app isn't active, so Settings would open behind other windows.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                    .help(L10n.t("menu.settings", store.language))
                    .accessibilityLabel(L10n.t("menu.settings", store.language))
                Button { store.openSystemDisplaySettings() } label: { Image(systemName: "display") }
                    .help(L10n.t("hidpi.openSettings", store.language))
                    .accessibilityLabel(L10n.t("hidpi.openSettings", store.language))
                if let status = store.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(status)
                }
                Spacer(minLength: 0)
                Button(L10n.t("menu.quit", store.language)) { NSApplication.shared.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .physicalHiDPIConfirmation(store: store, requestID: $physicalConfigurationRequestID)
        // Values may have changed through the monitor's own buttons since the last read.
        .onAppear { store.rereadHardwareControls() }
    }

    private var maximumContentHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return min(500, max(120, (screen?.visibleFrame.height ?? 640) - 110))
    }

    private func displayPanel(_ display: DisplayDevice, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display",
                             color: display.isBuiltin ? .gray : .blue, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(display.shortName(language: store.language))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            .help(display.shortName(language: store.language))
                        if display.metadata.isMain {
                            Text(L10n.t("display.main", store.language))
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(.tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    if let mode = display.currentMode {
                        Text(verbatim: "\(mode.refreshRateLabel)\(mode.isHiDPI ? " · HiDPI" : "")")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                HiDPIResolutionMenu(store: store, display: display, fillsWidth: false, borderless: true)
                    .fixedSize()
                    .help(L10n.t("ui.hiDPIResolution", store.language))
            }
            HardwareControlSliders(store: store, display: display, controls: [.brightness, .volume], style: .capsule)
            if display.currentHiDPIRefreshModes.count > 1 {
                HStack {
                    Text(L10n.t("ui.refreshRate", store.language)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    RefreshRatePicker(store: store, display: display)
                        .controlSize(.small)
                }
            }
            PhysicalHiDPIControls(store: store, display: display) {
                physicalConfigurationRequestID = store.physicalConfigurationRequest?.id
            }
            // Only the experiment lives here; full details and the restore action are in the main window.
            if !display.virtualHiDPITargets.isEmpty || store.virtualSession?.displayID == display.id {
                ExperimentalHiDPIControls(store: store, display: display)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A light fill over the panel's own material, like Control Center modules.
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

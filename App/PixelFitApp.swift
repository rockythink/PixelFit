import SwiftUI
import AppKit

@main
struct PixelFitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DisplayStore

    init() {
        CLIService.runIfNeeded()
        Self.activateExistingInstanceIfNeeded()
        _store = State(initialValue: DisplayStore())
    }

    private static func activateExistingInstanceIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = NSRunningApplication.current.processIdentifier
        let firstInstance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .min { left, right in
                let leftLaunch = left.launchDate ?? .distantFuture
                let rightLaunch = right.launchDate ?? .distantFuture
                return leftLaunch == rightLaunch
                    ? left.processIdentifier < right.processIdentifier
                    : leftLaunch < rightLaunch
            }
        guard let firstInstance, firstInstance.processIdentifier != currentPID else { return }
        firstInstance.activate(options: [])
        Foundation.exit(0)
    }

    var body: some Scene {
        WindowGroup(L10n.t("app.name", store.language), id: "main") {
            ContentView(store: store)
                .frame(minWidth: 840, minHeight: 640)
                .background(MainWindowTagger())
        }
        .defaultSize(width: 980, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu(L10n.t("menu.displays", store.language)) {
                Button(L10n.t("menu.refresh", store.language)) {
                    store.refreshDisplays()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Menu(L10n.t("menu.applyPreset", store.language)) {
                    ForEach(Array(store.presets.prefix(9).enumerated()), id: \.element.id) { index, preset in
                        Button(preset.name) { store.applyPreset(preset) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
                    }
                }
                .disabled(store.presets.isEmpty || !store.canBeginNativeChange || store.virtualSession != nil)

                Divider()

                Button(L10n.t("hidpi.openSettings", store.language)) {
                    store.openSystemDisplaySettings()
                }
            }
        }

        MenuBarExtra {
            MenuBarControlView(store: store)
        } label: {
            // The title+systemImage initializer exposes the symbol's description ("Mac") to VoiceOver.
            Image(systemName: "display")
                .accessibilityLabel(L10n.t("app.name", store.language))
        }
        .menuBarExtraStyle(.window)
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView(store: store)
        }

        #if DEBUG
        // Development only: the menu bar panel in an ordinary window, so it can be captured
        // for visual review. Opened at launch when PIXELFIT_PREVIEW_MENU=1.
        Window("Menu Bar Preview", id: "menu-preview") {
            MenuBarControlView(store: store)
                .background(.regularMaterial)
        }
        .windowResizability(.contentSize)
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayStore.applyActivationPolicy(showsDockIcon: PersistenceService().load().showsDockIcon)
        NSApp.activate(ignoringOtherApps: true)
    }
}

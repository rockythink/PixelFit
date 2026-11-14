import ServiceManagement
import SwiftUI

/// App preferences for the ⌘, Settings window. Display controls stay in the main window.
struct AppSettingsView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        Form {
            Section(L10n.t("settings.general", store.language)) {
                Picker(selection: Binding(
                    get: { store.language },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                } label: {
                    Label { Text(L10n.t("settings.appLanguage", store.language)) } icon: { SettingsIcon(RowIcon.language) }
                }
                Toggle(isOn: Binding(
                    get: { store.launchesAtLogin },
                    set: { store.setLaunchesAtLogin($0) }
                )) {
                    Label { Text(L10n.t("settings.launchAtLogin", store.language)) } icon: { SettingsIcon(RowIcon.login) }
                }
                if store.loginItemRequiresApproval {
                    HStack {
                        Text(L10n.t("settings.loginApproval", store.language))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L10n.t("settings.openLoginItems", store.language)) {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .controlSize(.small)
                    }
                }
                if let error = store.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: Binding(
                    get: { store.showsDockIcon },
                    set: { store.setShowsDockIcon($0) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("settings.showDockIcon", store.language))
                            Text(L10n.t("settings.dockNote", store.language)).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { SettingsIcon(RowIcon.dock) }
                }
            }
            Section(L10n.t("settings.keyboard", store.language)) {
                Toggle(isOn: Binding(
                    get: { store.mediaKeysEnabled },
                    set: { store.setMediaKeysEnabled($0) }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("settings.mediaKeys", store.language))
                            Text(L10n.t("settings.mediaKeysNote", store.language)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: { SettingsIcon(RowIcon.keyboard) }
                }
                if !store.conflictingApps.isEmpty {
                    Label(String(format: L10n.t("conflict.running", store.language), store.conflictingApps.joined(separator: ", ")),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if store.mediaKeysEnabled && !store.accessibilityTrusted {
                    HStack {
                        Text(L10n.t("settings.accessibilityNeeded", store.language))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L10n.t("settings.grantAccessibility", store.language)) {
                            store.requestAccessibilityTrust()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.t("settings.windowTitle", store.language))
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        // The user may have changed login items in System Settings meanwhile.
        .onAppear {
            store.refreshLoginItemStatus()
            store.updateMediaKeyMonitoring()
        }
    }
}

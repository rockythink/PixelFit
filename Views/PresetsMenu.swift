import SwiftUI

/// Presets apply to every display at once, so they live in the toolbar rather than in a display's detail.
struct PresetsMenu: View {
    @Bindable var store: DisplayStore
    @State private var isNaming = false
    @State private var presetName = ""

    private var unavailable: Bool {
        store.displays.isEmpty || !store.canBeginNativeChange || store.virtualSession != nil
    }

    var body: some View {
        Menu {
            if store.presets.isEmpty {
                Text(L10n.t("preset.empty", store.language))
            }
            ForEach(store.presets) { preset in
                Button(preset.name) { store.applyPreset(preset) }
                    .disabled(unavailable || preset.displayModes.isEmpty)
            }
            Divider()
            Button(L10n.t("preset.saveAs", store.language)) { isNaming = true }
                .disabled(unavailable)
            if !store.presets.isEmpty {
                Menu(L10n.t("preset.deleteMenu", store.language)) {
                    ForEach(store.presets) { preset in
                        Button(preset.name, role: .destructive) { store.deletePreset(preset) }
                    }
                }
                .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil)
            }
        } label: {
            Label(L10n.t("preset.title", store.language), systemImage: "bookmark")
        }
        .help(L10n.t("preset.title", store.language))
        // Toolbar menus otherwise announce the symbol name ("bookmark").
        .accessibilityLabel(L10n.t("preset.title", store.language))
        .alert(L10n.t("preset.saveTitle", store.language), isPresented: $isNaming) {
            TextField(L10n.t("preset.name", store.language), text: $presetName)
            Button(L10n.t("preset.save", store.language), action: save)
            Button(L10n.t("action.cancel", store.language), role: .cancel) { presetName = "" }
        } message: {
            Text(L10n.t("preset.note", store.language))
        }
    }

    private func save() {
        store.savePreset(named: presetName)
        presetName = ""
    }
}

/// Apply-only list for the menu bar window; saving and deleting stay in the main window.
struct PresetApplyMenu: View {
    @Bindable var store: DisplayStore

    var body: some View {
        if !store.presets.isEmpty {
            Menu(L10n.t("preset.title", store.language)) {
                ForEach(store.presets) { preset in
                    Button(preset.name) { store.applyPreset(preset) }
                        .disabled(preset.displayModes.isEmpty)
                }
            }
            .disabled(store.displays.isEmpty || !store.canBeginNativeChange || store.virtualSession != nil)
        }
    }
}

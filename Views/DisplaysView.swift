import SwiftUI

struct DisplaysView: View {
    @Bindable var store: DisplayStore
    @State private var physicalConfigurationRequestID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedDisplayID) {
                Section(L10n.t("nav.displays", store.language)) {
                    ForEach(store.displays) { display in
                        DisplayRow(display: display, language: store.language)
                            .tag(display.id)
                            .contextMenu {
                                Button(L10n.t("hidpi.openSettings", store.language)) { store.openSystemDisplaySettings() }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            if let display = store.selectedDisplay {
                DisplayDetailView(store: store, display: display) {
                    physicalConfigurationRequestID = store.physicalConfigurationRequest?.id
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(L10n.t("empty.noDisplay", store.language), systemImage: "display.trianglebadge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(store.selectedDisplay?.shortName(language: store.language) ?? L10n.t("app.name", store.language))
        .navigationSubtitle(store.selectedDisplay?.currentMode.map { "\($0.resolutionLabel) · \($0.refreshRateLabel)" } ?? "")
        // Screens refresh on their own (didChangeScreenParameters); ⌘R stays in the Displays menu.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PresetsMenu(store: store)
                    .labelStyle(.titleAndIcon)
            }
        }
        .physicalHiDPIConfirmation(store: store, requestID: $physicalConfigurationRequestID)
    }
}

private struct DisplayRow: View {
    let display: DisplayDevice
    let language: AppLanguage

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.shortName(language: language)).lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        } icon: {
            SettingsIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display",
                         color: display.isBuiltin ? .gray : .blue, size: 24)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if display.metadata.isMain { parts.append(L10n.t("display.main", language)) }
        if let mode = display.currentMode { parts.append("\(mode.resolutionLabel) · \(mode.refreshRateLabel)") }
        return parts.joined(separator: " · ")
    }
}

struct DisplayDetailView: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice
    let onRequestPhysicalConfiguration: () -> Void
    @State private var showAdvanced = false
    private var cachedNativeMode: DisplayMode? { store.hiDPIChoices[display.id]?.nativeMode }
    private var cachedSystemModes: [DisplayMode] { store.hiDPIChoices[display.id]?.systemModes ?? [] }

    private var showsRefreshPicker: Bool { display.currentHiDPIRefreshModes.count > 1 }
    private var isChanging: Bool {
        store.isPreparingVirtualHiDPI || store.pendingModeChange != nil || store.pendingVirtualSeconds != nil ||
        store.virtualSession?.displayID == display.id
    }

    private var currentModeSummary: String {
        guard let mode = display.currentMode else { return "—" }
        guard mode.isHiDPI else {
            return "\(mode.resolutionLabel) · \(mode.refreshRateLabel) · \(L10n.t("ui.notHiDPI", store.language))"
        }
        // The refresh rate picker already shows the rate when there is a choice.
        return showsRefreshPicker ? "HiDPI · \(mode.aspectRatioLabel)" : "\(mode.refreshRateLabel) · HiDPI · \(mode.aspectRatioLabel)"
    }

    private var panelSummary: String {
        var parts: [String] = []
        if let native = cachedNativeMode {
            parts.append("\(native.pixelWidth) × \(native.pixelHeight)")
            parts.append(native.aspectRatioLabel)
        }
        if display.metadata.diagonalInches != nil { parts.append(display.metadata.diagonalText(language: store.language)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Form {
            if store.displays.count > 1 {
                Section {
                    DisplayArrangementView(displays: store.displays, selectedDisplayID: $store.selectedDisplayID,
                                           language: store.language, height: 116)
                        .padding(.vertical, 8)
                }
            }
            Section(L10n.t("section.resolution", store.language)) {
                LabeledContent {
                    // The menu label is the current HiDPI size, so it isn't repeated elsewhere.
                    HiDPIResolutionMenu(store: store, display: display, fillsWidth: false)
                        .fixedSize()
                        .help(L10n.t("ui.confirmationNote", store.language))
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("ui.hiDPIResolution", store.language))
                            Text(currentModeSummary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    } icon: { SettingsIcon(RowIcon.resolution) }
                }
                if showsRefreshPicker {
                    LabeledContent {
                        RefreshRatePicker(store: store, display: display)
                    } label: {
                        Label { Text(L10n.t("ui.refreshRate", store.language)) } icon: { SettingsIcon(RowIcon.refreshRate) }
                    }
                }
                if !panelSummary.isEmpty {
                    LabeledContent {
                        Text(verbatim: panelSummary).monospacedDigit()
                    } label: {
                        Label { Text(L10n.t("display.panel", store.language)) } icon: { SettingsIcon(RowIcon.panel) }
                    }
                }
                PhysicalHiDPIControls(store: store, display: display, onRequest: onRequestPhysicalConfiguration)
            }
            if isChanging {
                Section { ResolutionChangeControls(store: store) }
            }
            if !display.isBuiltin || store.usesAppleBrightness(display.id) {
                Section {
                    HardwareControlSliders(store: store, display: display, style: .form)
                } header: {
                    Text(L10n.t("hardware.title", store.language))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !store.conflictingApps.isEmpty {
                            Label(String(format: L10n.t("conflict.running", store.language), store.conflictingApps.joined(separator: ", ")),
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if !store.usesAppleBrightness(display.id), store.effectiveBrightnessMode(for: display.id) != .software {
                            Text(L10n.t("hardware.footer", store.language)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = store.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                DisclosureGroup(L10n.t("ui.advanced", store.language), isExpanded: $showAdvanced) {
                    advanced
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhysicalHiDPIConfigurationDetails(store: store, display: display, onRequest: onRequestPhysicalConfiguration)
            ExperimentalHiDPIControls(store: store, display: display)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                detailRow("display.product", display.metadata.productName ?? display.shortName(language: store.language))
                detailRow("display.class", display.displayClass.label(language: store.language))
                detailRow("display.defaultResolution", cachedNativeMode?.resolutionWithAspectLabel ?? "—")
                detailRow("display.physicalSize", "\(display.metadata.physicalSizeText) · \(display.metadata.diagonalText(language: store.language))")
                detailRow("display.estimatedPPI", display.metadata.estimatedPPI(nativeMode: cachedNativeMode))
                detailRow("display.colorProfile", display.metadata.colorSpaceText(language: store.language))
                detailRow("display.role", L10n.t(display.metadata.isMain ? "display.main" : "display.active", store.language))
                detailRow("display.modes", "\(display.availableModes.count)")
                detailRow("display.identifiers", "\(display.metadata.vendorHex) / \(display.metadata.productHex) / \(display.metadata.serialText)")
                detailRow("display.manufactured", display.metadata.manufactureText)
            }
            .font(.caption).textSelection(.enabled)
            HStack {
                Menu(L10n.t("ui.moreModes", store.language)) {
                    ForEach(cachedSystemModes) { mode in
                        Button(mode.label) { store.applyDisplayMode(mode, for: display.id) }
                            .disabled(display.currentMode?.matchesEffectiveMode(mode) == true)
                    }
                }
                .fixedSize()
                .disabled(store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil || isChanging)
                Button(L10n.t("hidpi.openSettings", store.language)) { store.openSystemDisplaySettings() }
            }
            .controlSize(.small)
        }
        .padding(.top, 8)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(L10n.t(key, store.language)).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HiDPIResolutionMenu: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice
    /// Stretch the label to the available width; off for form rows, where the menu hugs its content.
    var fillsWidth = true
    /// Borderless text menu for dense headers (menu bar panel).
    var borderless = false

    private var disabled: Bool {
        store.isChangingPhysicalConfiguration || store.physicalConfigurationRequest != nil || store.isPreparingVirtualHiDPI ||
            store.pendingModeChange != nil || store.pendingVirtualSeconds != nil || store.hiDPIChoices[display.id]?.all.isEmpty != false
    }

    var body: some View {
        Group {
            if borderless {
                menu.menuStyle(.borderlessButton)
            } else {
                menu.buttonStyle(.bordered)
            }
        }
        .accessibilityLabel(L10n.t("ui.hiDPIResolution", store.language))
        .disabled(disabled)
    }

    private var menu: some View {
        Menu {
            if let choices = store.hiDPIChoices[display.id] {
                if !choices.recommended.isEmpty {
                    Section(L10n.t("hidpi.recommended", store.language)) {
                        ForEach(choices.recommended) { target in option(target, choices: choices) }
                    }
                }
                let others = choices.all.filter { !choices.recommended.contains($0) }
                if !others.isEmpty {
                    Section(L10n.t("ui.otherSizes", store.language)) {
                        ForEach(others) { target in option(target, choices: choices) }
                    }
                }
            }
        } label: {
            Text(display.isCurrentHiDPI ? (display.currentMode?.resolutionLabel ?? "—") : L10n.t("ui.chooseResolution", store.language))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .monospacedDigit()
        }
    }

    private func option(_ target: DisplayResolutionTarget, choices: HiDPIResolutionChoices) -> some View {
        let isCurrent = display.isCurrentHiDPI && display.currentMode?.width == target.width && display.currentMode?.height == target.height
        // Same mode the store will apply, so the hint describes what the user actually gets.
        let sharpness = choices.systemModes
            .first { $0.isHiDPI && $0.width == target.width && $0.height == target.height }?
            .sharpnessLabel(nativeMode: choices.nativeMode, language: store.language)
        let title = sharpness.map { "\(target.resolutionLabel)  ·  \($0)" } ?? target.resolutionLabel
        return Button { store.applyHiDPIResolution(target, for: display.id) } label: {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(isCurrent)
    }
}

struct ResolutionChangeControls: View {
    @Bindable var store: DisplayStore

    var body: some View {
        if store.isPreparingVirtualHiDPI {
            ProgressView(L10n.t("ui.changing", store.language)).controlSize(.small)
        } else if let seconds = store.pendingModeChange?.remainingSeconds ?? store.pendingVirtualSeconds {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(L10n.t("ui.keepQuestion", store.language)) · \(seconds)s")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
                if store.pendingVirtualSeconds != nil {
                    Text(L10n.t("ui.scalingRisk", store.language))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(L10n.t("ui.keep", store.language)) {
                        if store.pendingModeChange != nil { store.confirmDisplayModeChange() } else { store.confirmVirtualHiDPI() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(L10n.t("ui.restore", store.language)) {
                        if store.pendingModeChange != nil { store.rollbackDisplayModeChange() } else { store.stopVirtualHiDPI() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if store.virtualSession != nil {
            Button(L10n.t("ui.restore", store.language)) { store.stopVirtualHiDPI() }
                .buttonStyle(.bordered)
        }
    }
}

/// Offered only when the current HiDPI size runs at more than one rate; switching goes through
/// the same 15-second confirmation as any other mode change.
struct RefreshRatePicker: View {
    @Bindable var store: DisplayStore
    let display: DisplayDevice

    var body: some View {
        let modes = display.currentHiDPIRefreshModes
        if modes.count > 1, let current = display.currentMode {
            Picker(L10n.t("ui.refreshRate", store.language), selection: Binding(
                get: { Int(current.refreshRate.rounded()) },
                set: { rate in
                    if let mode = modes.first(where: { Int($0.refreshRate.rounded()) == rate }) {
                        store.applyDisplayMode(mode, for: display.id)
                    }
                }
            )) {
                ForEach(modes) { mode in
                    Text(mode.refreshRateLabel).tag(Int(mode.refreshRate.rounded()))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!store.canBeginNativeChange || store.virtualSession?.displayID == display.id)
        }
    }
}

import SwiftUI

/// Brightness (DDC, software or system) and DDC contrast / volume for one display.
/// Controls without a value source are hidden rather than shown disabled.
struct HardwareControlSliders: View {
    enum Style {
        /// Control Center–style capsules for the menu bar panel.
        case capsule
        /// Native labeled rows for a grouped Form.
        case form
    }

    @Bindable var store: DisplayStore
    let display: DisplayDevice
    var controls: [HardwareControl] = HardwareControl.allCases
    var style: Style = .form

    private var visibleControls: [HardwareControl] {
        controls.filter { store.controlFraction($0, for: display.id) != nil }
    }

    /// Mode choice applies to external displays PixelFit drives itself, once DDC has been probed.
    private var showsModePicker: Bool {
        !store.usesAppleBrightness(display.id) && store.hardware[display.id] != nil &&
            store.hardware[display.id]?.phase != .probing
    }

    var body: some View {
        if style == .capsule {
            VStack(alignment: .leading, spacing: 6) {
                status
                ForEach(visibleControls) { capsule($0) }
            }
        } else {
            status
            ForEach(visibleControls) { row($0) }
            if showsModePicker { modePicker }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch store.hardware[display.id]?.phase {
        case .probing?:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L10n.t("hardware.probing", store.language))
            }
            .font(.caption).foregroundStyle(.secondary)
        case .unavailable?:
            Label(L10n.t("hardware.unavailableSoftware", store.language), systemImage: "cable.connector.slash")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    // MARK: Mode

    private var ddcBrightnessAvailable: Bool { store.hardware[display.id]?.values[.brightness] != nil }

    private var modePicker: some View {
        let effective = store.effectiveBrightnessMode(for: display.id) ?? .software
        return Picker(selection: Binding(
            get: { store.brightnessModeSetting(for: display.id) },
            set: { store.setBrightnessMode($0, for: display.id) }
        )) {
            Text(String(format: L10n.t("brightness.mode.auto", store.language),
                        L10n.t((ddcBrightnessAvailable ? BrightnessMode.combined : .software).titleKey, store.language)))
                .tag(BrightnessMode?.none)
            Divider()
            ForEach(BrightnessMode.allCases) { mode in
                Text(L10n.t(mode.titleKey, store.language))
                    .tag(BrightnessMode?.some(mode))
                    .selectionDisabled(mode != .software && !ddcBrightnessAvailable)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("brightness.mode.title", store.language))
                    Text(L10n.t("brightness.mode.note.\(effective.rawValue)", store.language))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: { SettingsIcon(RowIcon.brightnessMode) }
        }
    }

    // MARK: Rows

    private func binding(_ control: HardwareControl) -> Binding<Double> {
        Binding(
            get: { store.controlFraction(control, for: display.id) ?? 0 },
            set: { store.setHardwareControl(control, fraction: $0, for: display.id) }
        )
    }

    private func capsule(_ control: HardwareControl) -> some View {
        CapsuleSlider(
            value: store.controlFraction(control, for: display.id) ?? 0,
            systemImage: control.systemImage,
            label: L10n.t(control.titleKey, store.language)
        ) { store.setHardwareControl(control, fraction: $0, for: display.id) }
    }

    private func row(_ control: HardwareControl) -> some View {
        let title = L10n.t(control.titleKey, store.language)
        let percent = store.controlFraction(control, for: display.id).map { "\(Int(($0 * 100).rounded()))%" }
        return LabeledContent {
            HStack(spacing: 10) {
                Slider(value: binding(control), in: 0...1)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue(percent ?? "")
                Text(verbatim: percent ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(maxWidth: 320)
        } label: {
            Label { Text(title) } icon: { SettingsIcon(RowIcon.control(control)) }
        }
    }
}

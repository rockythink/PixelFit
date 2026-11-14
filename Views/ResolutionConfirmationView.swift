import SwiftUI

struct ResolutionConfirmationView: View {
    @Bindable var store: DisplayStore

    private var seconds: Int { store.pendingModeChange?.remainingSeconds ?? store.pendingVirtualSeconds ?? 0 }

    private var change: (displayName: String?, description: String)? {
        if let pending = store.pendingModeChange {
            return (displayName(pending.displayID),
                    "\(modeText(pending.previousMode)) → \(modeText(pending.targetMode))")
        }
        if let session = store.virtualSession {
            return (displayName(session.displayID),
                    "\(modeText(session.originalMode)) → \(session.target.resolutionLabel) · \(Int(session.refreshRate.rounded()))Hz")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("ui.keepQuestion", store.language))
                .font(.headline)
            if let change {
                VStack(alignment: .leading, spacing: 3) {
                    if let name = change.displayName {
                        Text(name).font(.callout.weight(.medium))
                    }
                    Text(change.description)
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(String(format: L10n.t("ui.revertCountdown", store.language), seconds))
                .font(.callout).monospacedDigit()
                .foregroundStyle(.orange)
            if store.pendingVirtualSeconds != nil {
                Text(L10n.t("ui.scalingRisk", store.language))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L10n.t("ui.restore", store.language)) {
                    if store.pendingModeChange != nil { store.rollbackDisplayModeChange() } else { store.stopVirtualHiDPI() }
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.t("ui.keep", store.language)) {
                    if store.pendingModeChange != nil { store.confirmDisplayModeChange() } else { store.confirmVirtualHiDPI() }
                }
                .keyboardShortcut(.defaultAction)
                // Stay visibly primary even before the panel becomes key.
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }

    private func displayName(_ id: UInt32) -> String? {
        store.displays.first { $0.id == id }?.shortName(language: store.language)
    }

    private func modeText(_ mode: DisplayMode) -> String {
        "\(mode.resolutionLabel) · \(mode.refreshRateLabel)"
    }
}

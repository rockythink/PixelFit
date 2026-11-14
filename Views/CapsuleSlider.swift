import SwiftUI

/// Control Center–style slider: a thick capsule whose fill is the value, with the symbol inside.
/// Click anywhere to jump, drag to scrub; VoiceOver and keyboard adjust in 1/16 steps.
struct CapsuleSlider: View {
    let value: Double
    let systemImage: String
    let label: String
    var height: CGFloat = 22
    let onChange: (Double) -> Void

    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fillWidth = max(height, width * value)
            ZStack(alignment: .leading) {
                // Neutral track and white fill, as in Control Center; the accent color stays for selection.
                Capsule()
                    .fill(.primary.opacity(isHovered ? 0.14 : 0.10))
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
                Capsule()
                    .fill(.white)
                    .frame(width: fillWidth)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
                    .frame(width: height, height: height)
                    .padding(.leading, 2)
                Text(verbatim: "\(Int((value * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    // Dark on the white fill once it reaches the label, otherwise secondary on the track.
                    .foregroundStyle(value > 0.86 ? AnyShapeStyle(.black.opacity(0.55)) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 9)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max(drag.location.x / width, 0), 1))
            })
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 16
            switch direction {
            case .increment: onChange(min(value + step, 1))
            case .decrement: onChange(max(value - step, 0))
            @unknown default: break
            }
        }
    }
}

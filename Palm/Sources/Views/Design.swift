import SwiftUI
import UIKit

/// Palm's whole visual system. Two rules govern it:
///
/// 1. Nothing a finger touches is smaller than 48pt. Not one control.
/// 2. There is exactly one place controls live — the rail — and it moves to
///    whichever edge your thumb is already near.
enum P {
    // Ground is a cool near-black with a blue bias, so the warm amber accent
    // reads as light rather than as a second colour.
    static let ground  = Color(red: 0.055, green: 0.063, blue: 0.078)
    static let surface = Color(red: 0.090, green: 0.102, blue: 0.125)
    static let raised  = Color(red: 0.125, green: 0.141, blue: 0.173)
    static let line    = Color(red: 0.180, green: 0.200, blue: 0.239)

    static let ink   = Color(red: 0.925, green: 0.937, blue: 0.957)
    static let dim   = Color(red: 0.596, green: 0.627, blue: 0.682)
    static let faint = Color(red: 0.380, green: 0.412, blue: 0.467)

    static let amber = Color(red: 0.949, green: 0.651, blue: 0.353)
    static let teal  = Color(red: 0.341, green: 0.824, blue: 0.753)
    static let rose  = Color(red: 1.000, green: 0.369, blue: 0.467)

    /// One hue per track, spaced so neighbours never read as the same colour
    /// in peripheral vision while you are looking at the grid.
    static let trackColors: [Color] = [
        Color(red: 0.98, green: 0.55, blue: 0.35),
        Color(red: 0.99, green: 0.76, blue: 0.36),
        Color(red: 0.80, green: 0.88, blue: 0.45),
        Color(red: 0.42, green: 0.84, blue: 0.62),
        Color(red: 0.36, green: 0.80, blue: 0.86),
        Color(red: 0.47, green: 0.66, blue: 0.98),
        Color(red: 0.70, green: 0.58, blue: 0.98),
        Color(red: 0.97, green: 0.52, blue: 0.72),
    ]

    static func trackColor(_ index: Int) -> Color {
        trackColors[((index % trackColors.count) + trackColors.count) % trackColors.count]
    }

    /// The floor for every interactive element.
    static let touch: CGFloat = 48
    static let radius: CGFloat = 14
    static let gap: CGFloat = 10

    static func title(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func numeral(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

enum Haptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }
    static func firm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// A control surface. One shape, one border, one press response — so every
/// tappable thing in Palm feels like the same object under the finger.
struct Pad<Content: View>: View {
    var isOn = false
    var tint: Color = P.amber
    var minSize: CGFloat = P.touch
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var pressed = false

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            content()
                .frame(minWidth: minSize, minHeight: minSize)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                        .fill(isOn ? tint.opacity(0.22) : P.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                        .strokeBorder(isOn ? tint.opacity(0.85) : P.line, lineWidth: isOn ? 1.5 : 1)
                )
                .foregroundStyle(isOn ? tint : P.ink)
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A horizontal or vertical drag value, used for tempo, volume and pan. Drag
/// anywhere on the whole control — there is no thin slider track to hit.
struct DragValue: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String
    var tint: Color = P.amber

    @State private var startValue: Double?

    var body: some View {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(P.label(10)).tracking(1.2)
                .foregroundStyle(P.faint)
            Text(format(value))
                .font(P.numeral(20))
                .foregroundStyle(P.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: P.touch + 8)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.raised))
        .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous).strokeBorder(P.line))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startValue == nil { startValue = value; Haptic.select() }
                    let span = range.upperBound - range.lowerBound
                    // 220pt of travel covers the full range, in either axis —
                    // so the same gesture works in portrait and landscape.
                    let delta = Double(g.translation.width - g.translation.height) / 220 * span
                    value = min(range.upperBound, max(range.lowerBound, (startValue ?? value) + delta))
                }
                .onEnded { _ in startValue = nil; Haptic.tap() }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let stepSize = (range.upperBound - range.lowerBound) / 40
            value = min(range.upperBound, max(range.lowerBound,
                        value + (direction == .increment ? stepSize : -stepSize)))
        }
    }
}

import SwiftUI

/// The background. Not a colour and not a picture — three enormous soft lights
/// drifting behind everything, tinted by whatever is currently playing. When a
/// new sigil is summoned the whole room changes colour over three seconds, and
/// that colour change is the loudest thing the app ever does.
struct Veil: View {
    @ObservedObject var world: World
    var bands: SIMD3<Float>
    var dna: SigilDNA?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let t = world.drift
            let base = dna ?? SigilDNA(seed: 0x5EED)

            ZStack {
                Color.black

                lamp(color: base.color(0.0, brightness: 0.85),
                     at: CGPoint(x: w * (0.5 + 0.34 * sin(t * 0.041)),
                                 y: h * (0.34 + 0.20 * cos(t * 0.033))),
                     radius: max(w, h) * 0.75,
                     opacity: 0.30 + 0.22 * Double(bands.y))

                lamp(color: base.color(0.6, brightness: 0.8),
                     at: CGPoint(x: w * (0.5 + 0.40 * cos(t * 0.027 + 1.2)),
                                 y: h * (0.70 + 0.18 * sin(t * 0.036 + 0.4))),
                     radius: max(w, h) * 0.62,
                     opacity: 0.26 + 0.20 * Double(bands.x))

                lamp(color: base.color(1.3, brightness: 0.9),
                     at: CGPoint(x: w * (0.5 + 0.46 * sin(t * 0.019 + 2.6)),
                                 y: h * (0.5 + 0.40 * cos(t * 0.023 + 2.1))),
                     radius: max(w, h) * 0.5,
                     opacity: 0.18 + 0.26 * Double(bands.z))

                // Vignette: pulls the eye to the centre and hides the corners
                // where the lamps run out of gradient.
                RadialGradient(colors: [.clear, .black.opacity(0.72)],
                               center: .center,
                               startRadius: min(w, h) * 0.28,
                               endRadius: max(w, h) * 0.78)
                .blendMode(.multiply)
            }
            .animation(.easeInOut(duration: 3.0), value: dna?.seed)
        }
        .allowsHitTesting(false)
    }

    private func lamp(color: Color, at point: CGPoint, radius: CGFloat, opacity: Double) -> some View {
        RadialGradient(colors: [color.opacity(opacity), color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: radius)
        .frame(width: radius * 2, height: radius * 2)
        .position(point)
        .blendMode(.plusLighter)
    }
}

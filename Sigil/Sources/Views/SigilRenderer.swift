import SwiftUI

/// Draws a sigil. The *same* routine draws the tiny glyph drifting in the field
/// and the full mandala at the centre of the world — only `bloom` changes.
/// That is why summoning feels like one continuous gesture instead of a screen
/// transition: nothing is replaced, something just opens.
enum SigilRenderer {

    static func draw(_ context: inout GraphicsContext,
                     dna: SigilDNA,
                     center: CGPoint,
                     radius: CGFloat,
                     time: Double,
                     bands: SIMD3<Float>,
                     bloom: Double,
                     alpha: Double = 1.0) {

        let low = Double(bands.x)
        let mid = Double(bands.y)
        let high = Double(bands.z)

        let spin = time * 0.09 * dna.orbitSpeed
        let breathe = 1 + 0.045 * sin(time * 0.9) + 0.06 * low

        var ctx = context
        ctx.blendMode = .plusLighter

        // ── Rings ────────────────────────────────────────────────────────────
        for ring in 0..<dna.rings {
            let t = Double(ring) / Double(max(1, dna.rings - 1))
            let rr = radius * (0.34 + 0.62 * t) * breathe
            let dir: Double = ring % 2 == 0 ? 1 : -1
            let rot = spin * (1 + t * 1.7) * dir + dna.twist * t

            let segments = 24 + ring * 9
            var path = Path()
            for s in 0..<segments {
                // Dashes, drawn as arcs, so they can be individually lit.
                let a0 = rot + Double(s) / Double(segments) * .pi * 2
                let a1 = a0 + (.pi * 2 / Double(segments)) * (0.34 + 0.4 * mid)
                path.addArc(center: center, radius: rr,
                            startAngle: .radians(a0), endAngle: .radians(a1),
                            clockwise: false)
            }
            let lineWidth = max(0.5, radius * (0.006 + 0.012 * bloom))
            ctx.stroke(path,
                       with: .color(dna.color(t, brightness: 0.55 + 0.35 * mid).opacity(alpha * (0.35 + 0.45 * bloom))),
                       lineWidth: lineWidth)
        }

        // ── Petals ───────────────────────────────────────────────────────────
        let petals = dna.petals
        for p in 0..<petals {
            let t = Double(p) / Double(petals)
            let angle = spin * 0.6 + t * .pi * 2

            // Each petal has its own slow life, so the figure never pulses in
            // lockstep — that lockstep is what makes most visualisers feel cheap.
            let life = 0.55 + 0.45 * sin(time * (0.7 + Double(p % 5) * 0.13) + Double(p))
            let reach = radius * (0.5 + 0.5 * dna.spikiness) * (0.72 + 0.28 * life) * breathe
            let width = radius * (0.06 + 0.16 * (1 - dna.spikiness)) * (0.7 + 0.5 * mid)

            let tip = CGPoint(x: center.x + cos(angle) * reach,
                              y: center.y + sin(angle) * reach)
            let c1 = CGPoint(x: center.x + cos(angle + 0.5) * reach * 0.45,
                             y: center.y + sin(angle + 0.5) * reach * 0.45)
            let c2 = CGPoint(x: center.x + cos(angle - 0.5) * reach * 0.45,
                             y: center.y + sin(angle - 0.5) * reach * 0.45)

            var petal = Path()
            petal.move(to: center)
            petal.addQuadCurve(to: tip, control: c1)
            petal.addQuadCurve(to: center, control: c2)

            let colour = dna.color(t, brightness: 0.5 + 0.5 * life)
            ctx.fill(petal, with: .color(colour.opacity(alpha * (0.055 + 0.10 * bloom))))
            ctx.stroke(petal,
                       with: .color(colour.opacity(alpha * (0.32 + 0.4 * bloom))),
                       lineWidth: max(0.4, radius * 0.0055))

            // Tips catch the transients.
            let tipR = radius * (0.012 + 0.05 * high * bloom) * (0.6 + 0.8 * life)
            if tipR > 0.4 {
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - tipR, y: tip.y - tipR,
                                                width: tipR * 2, height: tipR * 2)),
                         with: .color(colour.opacity(alpha * 0.9)))
            }
        }

        // ── Core ─────────────────────────────────────────────────────────────
        let coreR = radius * (0.10 + 0.06 * low) * breathe
        let core = Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR,
                                          width: coreR * 2, height: coreR * 2))
        ctx.fill(core, with: .radialGradient(
            Gradient(colors: [
                Color.white.opacity(alpha * (0.85 + 0.15 * low)),
                dna.color(0.5, brightness: 1).opacity(alpha * 0.55),
                dna.color(0.9, brightness: 0.6).opacity(0)
            ]),
            center: center, startRadius: 0, endRadius: coreR * (2.6 + 1.6 * bloom)))
    }

    /// The halo behind a sigil. Drawn separately and blurred so the whole field
    /// can share one blur pass instead of one per glyph.
    static func halo(_ context: inout GraphicsContext,
                     dna: SigilDNA,
                     center: CGPoint,
                     radius: CGFloat,
                     bands: SIMD3<Float>,
                     alpha: Double) {
        let r = radius * (1.5 + 0.8 * Double(bands.x))
        var ctx = context
        ctx.blendMode = .plusLighter
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(colors: [dna.color(0.3, brightness: 0.9).opacity(alpha * 0.30),
                                      dna.color(0.7, brightness: 0.7).opacity(0)]),
                    center: center, startRadius: 0, endRadius: r))
    }
}

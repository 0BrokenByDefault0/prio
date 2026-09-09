import SwiftUI

/// Continuous state for the world. Deliberately a plain reference type with no
/// publishing: it is stepped once per frame inside the TimelineView and read
/// straight by the Canvas, so nothing here can ever trigger a layout pass.
///
/// Sigil has no screens and no navigation stack. It has one scene and a set of
/// numbers that are always travelling toward where they should be. Everything
/// the user does moves a target, never a value.
@MainActor
final class World: ObservableObject {

    // Field
    var rotation: Double = 0
    var spin: Double = 0.035          // idle drift, radians/second
    var spinVelocity: Double = 0

    // Summoning
    var bloom: Double = 0             // 0 = field of glyphs, 1 = full mandala
    var bloomTarget: Double = 0

    // Which glyph is being pulled toward the centre
    var focused: Track?
    var focusIndex: Int = 0

    // Scrub ring
    var scrubbing = false
    var scrubFraction: Double = 0
    var scrubGlow: Double = 0

    // Ambient
    var drift: Double = 0
    var lastTick: Double = 0

    func step(now: Double) {
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(1.0 / 20.0, now - lastTick)
        lastTick = now

        // Inertial spin with a long, quiet decay.
        rotation += (spin + spinVelocity) * dt
        spinVelocity *= pow(0.06, dt)

        // Critically-ish damped approach. `rate` is per-second, so the feel is
        // identical at 60Hz and 120Hz.
        bloom += (bloomTarget - bloom) * (1 - pow(0.0015, dt))
        scrubGlow += ((scrubbing ? 1.0 : 0.0) - scrubGlow) * (1 - pow(0.004, dt))
        drift += dt
    }
}

import Foundation

// MARK: - Pure-function music
//
// A Sigil track has no audio file. It is a *function of the beat index*, seeded
// by the sigil's DNA. That has a lovely consequence: seeking is exact and free.
// Drag the ring to bar 97 and bar 97 sounds the way it always has, because it
// was never recorded — it is recomputed.

@inline(__always) private func midiToHz(_ note: Double) -> Double {
    440.0 * pow(2.0, (note - 69.0) / 12.0)
}

@inline(__always) private func softClip(_ x: Float) -> Float {
    // Cheap odd-symmetric saturation. Keeps peaks polite without a limiter's pump.
    let v = max(-1.6, min(1.6, x))
    return v - (v * v * v) / 6.75
}

/// One decaying partial-pair. Plucks are the bright grain on top of the pad.
private struct Pluck {
    var phase: Double = 0
    var phase2: Double = 0
    var inc: Double = 0
    var inc2: Double = 0
    var amp: Float = 0
    var decay: Float = 0.9997
    var pan: Float = 0.5
    var alive: Bool = false

    mutating func trigger(hz: Double, sampleRate: Double, level: Float, decaySeconds: Double, pan: Float) {
        phase = 0
        phase2 = 0
        inc = hz / sampleRate
        inc2 = (hz * 2.0104) / sampleRate   // a hair sharp: gives the shimmer beat
        amp = level
        decay = Float(pow(0.001, 1.0 / (decaySeconds * sampleRate)))
        self.pan = pan
        alive = true
    }

    mutating func next() -> Float {
        guard alive else { return 0 }
        phase += inc; if phase >= 1 { phase -= 1 }
        phase2 += inc2; if phase2 >= 1 { phase2 -= 1 }
        let s = Float(sin(phase * 2 * .pi)) + 0.34 * Float(sin(phase2 * 2 * .pi))
        let out = s * amp
        amp *= decay
        if amp < 0.0002 { alive = false; amp = 0 }
        return out
    }
}

/// A detuned oscillator in the pad stack.
private struct PadOsc {
    var phase: Double = 0
    var inc: Double = 0
    var target: Double = 0
    var pan: Float = 0.5

    mutating func next(glide: Double) -> Float {
        inc += (target - inc) * glide
        phase += inc
        if phase >= 1 { phase -= 1 }
        // Band-limited-ish triangle: warmer than a saw, cheaper than wavetables.
        let t = phase < 0.5 ? phase * 4 - 1 : 3 - phase * 4
        return Float(t)
    }
}

/// A single voice of the engine: one sigil, singing.
struct SigilVoice {
    private let dna: SigilDNA
    private let sampleRate: Double
    private let samplesPerStep: Double

    private var pads: [PadOsc] = []
    private var plucks = [Pluck](repeating: Pluck(), count: 14)
    private var pluckCursor = 0

    private var subPhase: Double = 0
    private var lpL: Float = 0
    private var lpR: Float = 0
    private var lfoPhase: Double = 0

    /// Absolute playhead, in samples from the start of the piece.
    private(set) var cursor: Double = 0
    private var lastStep: Int = -1

    /// Band energies for the renderer: low, mid, high, each smoothed 0..~1.
    private(set) var bands: SIMD3<Float> = .zero

    init(dna: SigilDNA, sampleRate: Double) {
        self.dna = dna
        self.sampleRate = sampleRate
        // A "step" is a sixteenth note.
        self.samplesPerStep = sampleRate * dna.secondsPerBeat / 4.0

        var r = Rng(seed: dna.seed ^ 0x9E3779B97F4A7C15)
        for i in 0..<dna.padVoices {
            var osc = PadOsc()
            osc.pan = Float(r.range(0.12, 0.88))
            osc.phase = r.unit()
            _ = i
            pads.append(osc)
        }
        retuneChord()
    }

    var positionSeconds: Double { cursor / sampleRate }

    mutating func seek(toSeconds seconds: Double) {
        cursor = max(0, seconds) * sampleRate
        lastStep = Int(floor(cursor / samplesPerStep)) - 1
        retuneChord()
    }

    /// Chords move every 8 bars (128 steps). Which chord is, again, a pure
    /// function of where you are — so the harmony is stable across seeks.
    private mutating func retuneChord() {
        let section = Int(floor(cursor / (samplesPerStep * 128)))
        var r = Rng(seed: dna.seed &+ UInt64(bitPattern: Int64(section)) &* 0x2545F4914F6CDD1D)
        let base = r.int(-2, 4)
        for i in pads.indices {
            let step = base + [0, 2, 4, 6, 7, 9][i % 6]
            let octave = (i % 3 == 2) ? 12.0 : 0.0
            let detune = (Double(i) - Double(pads.count - 1) / 2) * 0.06 * dna.shimmer
            let note = dna.root + 12 + Double(dna.scale.semitone(step: step)) + octave + detune
            pads[i].target = midiToHz(note) / sampleRate
        }
    }

    private mutating func triggerStep(_ step: Int) {
        if step % 128 == 0 { retuneChord() }

        var r = Rng(seed: dna.seed ^ (UInt64(bitPattern: Int64(step)) &* 0xD6E8FEB86659FD93))

        // Downbeats are always spoken; the rest is chance weighted by density.
        let onBeat = step % 4 == 0
        let chance = dna.pluckDensity * (onBeat ? 2.2 : 0.7)
        guard r.unit() < chance else { return }

        let section = step / 128
        var sr = Rng(seed: dna.seed &+ UInt64(bitPattern: Int64(section)) &* 0x2545F4914F6CDD1D)
        let base = sr.int(-2, 4)

        let step7 = base + r.int(0, 11)
        let octave = Double(r.pick([12, 24, 24, 36]))
        let note = dna.root + Double(dna.scale.semitone(step: step7)) + octave
        let level = Float(r.range(0.10, 0.26)) * (onBeat ? 1.25 : 0.85)
        let decay = r.range(1.4, 4.6)

        plucks[pluckCursor].trigger(hz: midiToHz(note),
                                    sampleRate: sampleRate,
                                    level: level,
                                    decaySeconds: decay,
                                    pan: Float(r.range(0.08, 0.92)))
        pluckCursor = (pluckCursor + 1) % plucks.count
    }

    /// Render one stereo frame.
    mutating func next() -> (Float, Float) {
        let step = Int(floor(cursor / samplesPerStep))
        if step != lastStep {
            // Catch up rather than skip, so a hitch never eats a note.
            if lastStep >= 0 && step - lastStep <= 8 {
                for s in (lastStep + 1)...step { triggerStep(s) }
            } else {
                triggerStep(step)
            }
            lastStep = step
        }

        lfoPhase += 0.07 / sampleRate
        if lfoPhase >= 1 { lfoPhase -= 1 }
        let lfo = Float(sin(lfoPhase * 2 * .pi))

        // Pad
        var padL: Float = 0, padR: Float = 0
        let glide = 6.0 / sampleRate
        for i in pads.indices {
            let s = pads[i].next(glide: glide) * 0.16
            padL += s * (1 - pads[i].pan)
            padR += s * pads[i].pan
        }

        // Sub
        let subHz = midiToHz(dna.root - 12)
        subPhase += subHz / sampleRate
        if subPhase >= 1 { subPhase -= 1 }
        let sub = Float(sin(subPhase * 2 * .pi)) * Float(dna.subWeight) * 0.22

        // Plucks
        var plL: Float = 0, plR: Float = 0
        for i in plucks.indices where plucks[i].alive {
            let s = plucks[i].next()
            plL += s * (1 - plucks[i].pan)
            plR += s * plucks[i].pan
        }

        var l = padL + sub * 0.5 + plL
        var r = padR + sub * 0.5 + plR

        // Gently breathing lowpass — the pad opens and closes like slow weather.
        let cutoff = 0.10 + 0.05 * Float(dna.shimmer) + 0.035 * lfo
        lpL += (l - lpL) * cutoff
        lpR += (r - lpR) * cutoff
        // Keep a little of the dry signal so plucks stay bright.
        l = lpL * 0.78 + l * 0.22
        r = lpR * 0.78 + r * 0.22

        cursor += 1

        let outL = softClip(l * 0.9)
        let outR = softClip(r * 0.9)

        // Meter, cheaply: sub for low, pad for mid, pluck for high.
        let low = abs(sub)
        let mid = abs(padL + padR) * 0.5
        let high = abs(plL + plR) * 0.5
        let smoothing: Float = 0.0009
        bands.x += (min(1, low * 3.2) - bands.x) * smoothing
        bands.y += (min(1, mid * 3.6) - bands.y) * smoothing
        bands.z += (min(1, high * 3.0) - bands.z) * (smoothing * 4)

        return (outL, outR)
    }
}

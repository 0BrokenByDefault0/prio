import Foundation

/// Every track makes sound the moment you open the app, with no plugin loaded
/// and no sample assets shipped. These are the fallback voices: three drum
/// synths and a polyphonic tone generator. Load an AUv3 into a track and this
/// steps aside.
enum VoiceKind: Int, Codable, CaseIterable {
    case kick, snare, hat, tone

    var label: String {
        switch self {
        case .kick:  return "Kick synth"
        case .snare: return "Snare synth"
        case .hat:   return "Hat synth"
        case .tone:  return "Tone synth"
        }
    }

    /// Sensible default for a freshly created track, by position.
    static func `default`(forTrack index: Int) -> VoiceKind {
        switch index {
        case 0: return .kick
        case 1: return .snare
        case 2: return .hat
        case 7: return .snare
        default: return .tone
        }
    }
}

private struct Env {
    var value: Float = 0
    var target: Float = 0
    var rate: Float = 0.001
    var releasing = false

    mutating func next() -> Float {
        value += (target - value) * rate
        if value < 0.00005 { value = 0 }
        return value
    }
}

private struct ToneVoice {
    var note: UInt8 = 0
    var phase: Float = 0
    var inc: Float = 0
    var amp: Float = 0
    var env: Float = 0
    var decay: Float = 0.9999
    var releasing = false
    var active = false
}

/// A single track's built-in synthesiser. Owned by the audio thread.
final class BuiltInInstrument: @unchecked Sendable {
    private let sampleRate: Float
    var kind: VoiceKind = .tone

    // Drum state
    private var drumPhase: Float = 0
    private var drumPitch: Float = 0
    private var drumPitchEnv: Float = 0
    private var drumAmp: Float = 0
    private var drumDecay: Float = 0.9995
    private var noiseAmp: Float = 0
    private var noiseDecay: Float = 0.999
    private var noiseLP: Float = 0
    private var noiseHP: Float = 0
    private var rngState: UInt32 = 0x12345678

    // Tone state
    private var voices = [ToneVoice](repeating: ToneVoice(), count: 10)

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
    }

    @inline(__always) private func noise() -> Float {
        rngState ^= rngState << 13
        rngState ^= rngState >> 17
        rngState ^= rngState << 5
        return Float(Int32(bitPattern: rngState)) / Float(Int32.max)
    }

    @inline(__always) private func hz(_ note: UInt8) -> Float {
        440 * powf(2, (Float(note) - 69) / 12)
    }

    func noteOn(_ note: UInt8, velocity: UInt8) {
        let v = Float(velocity) / 127
        switch kind {
        case .kick:
            drumPhase = 0
            drumPitch = hz(note) * 2.4
            drumPitchEnv = 1
            drumAmp = v
            drumDecay = powf(0.001, 1 / (0.42 * sampleRate))
            noiseAmp = v * 0.25
            noiseDecay = powf(0.001, 1 / (0.012 * sampleRate))
        case .snare:
            drumPhase = 0
            drumPitch = hz(note) * 1.6
            drumPitchEnv = 0.35
            drumAmp = v * 0.7
            drumDecay = powf(0.001, 1 / (0.14 * sampleRate))
            noiseAmp = v
            noiseDecay = powf(0.001, 1 / (0.18 * sampleRate))
        case .hat:
            drumAmp = 0
            noiseAmp = v * 0.6
            noiseDecay = powf(0.001, 1 / (0.055 * sampleRate))
        case .tone:
            var slot = voices.firstIndex { !$0.active }
            if slot == nil {
                // Steal the quietest voice rather than the oldest: stealing by
                // age audibly clips held chords.
                slot = voices.indices.min { voices[$0].env < voices[$1].env }
            }
            guard let i = slot else { return }
            voices[i] = ToneVoice(note: note,
                                  phase: 0,
                                  inc: hz(note) / sampleRate,
                                  amp: v * 0.22,
                                  env: 0,
                                  decay: powf(0.001, 1 / (2.2 * sampleRate)),
                                  releasing: false,
                                  active: true)
        }
    }

    func noteOff(_ note: UInt8) {
        guard kind == .tone else { return }
        for i in voices.indices where voices[i].active && voices[i].note == note {
            voices[i].releasing = true
            voices[i].decay = powf(0.001, 1 / (0.28 * sampleRate))
        }
    }

    func allNotesOff() {
        for i in voices.indices { voices[i].active = false }
        drumAmp = 0
        noiseAmp = 0
    }

    @inline(__always) func render() -> Float {
        var out: Float = 0

        if kind == .tone {
            for i in voices.indices where voices[i].active {
                voices[i].phase += voices[i].inc
                if voices[i].phase >= 1 { voices[i].phase -= 1 }
                let p = voices[i].phase
                // Two stacked partials — warm without a wavetable.
                let s = sinf(p * 2 * .pi) + 0.28 * sinf(p * 4 * .pi)
                // Attack is a one-pole rise so notes never click.
                voices[i].env += (1 - voices[i].env) * 0.0016
                out += s * voices[i].amp * voices[i].env
                voices[i].amp *= voices[i].decay
                if voices[i].amp < 0.00008 { voices[i].active = false }
            }
        } else {
            if drumAmp > 0.00008 {
                drumPitchEnv *= 0.9993
                let f = drumPitch * (0.30 + 0.70 * drumPitchEnv)
                drumPhase += f / sampleRate
                if drumPhase >= 1 { drumPhase -= 1 }
                out += sinf(drumPhase * 2 * .pi) * drumAmp
                drumAmp *= drumDecay
            }
            if noiseAmp > 0.00008 {
                let n = noise()
                noiseLP += (n - noiseLP) * (kind == .hat ? 0.82 : 0.35)
                noiseHP = kind == .hat ? (n - noiseLP) : noiseLP
                out += noiseHP * noiseAmp * (kind == .hat ? 0.5 : 0.6)
                noiseAmp *= noiseDecay
            }
        }

        // Polite ceiling. A DAW that clips on the first bar feels broken even
        // when it is correct.
        return max(-1.2, min(1.2, out)) * 0.9
    }
}

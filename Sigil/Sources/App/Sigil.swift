import SwiftUI

// MARK: - Deterministic randomness
//
// Every visual and musical property in Sigil is derived from a single 64-bit
// seed. The same seed always produces the same sigil and the same song, which
// is what makes a track feel like a *place* you can return to.

struct Rng {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
        _ = next()
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }

    /// Uniform in 0..<1
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    mutating func int(_ lo: Int, _ hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }

    mutating func pick<T>(_ xs: [T]) -> T {
        xs[int(0, xs.count - 1)]
    }
}

func hash64(_ string: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x100000001b3
    }
    return h
}

// MARK: - Scales

enum Scale: String, CaseIterable {
    case aeolian, dorian, lydian, phrygian, pentatonic, hirajoshi

    var degrees: [Int] {
        switch self {
        case .aeolian:    return [0, 2, 3, 5, 7, 8, 10]
        case .dorian:     return [0, 2, 3, 5, 7, 9, 10]
        case .lydian:     return [0, 2, 4, 6, 7, 9, 11]
        case .phrygian:   return [0, 1, 3, 5, 7, 8, 10]
        case .pentatonic: return [0, 3, 5, 7, 10]
        case .hirajoshi:  return [0, 2, 3, 7, 8]
        }
    }

    /// Semitone offset for a scale step, wrapping into octaves.
    func semitone(step: Int) -> Int {
        let d = degrees
        let octave = Int(floor(Double(step) / Double(d.count)))
        var index = step % d.count
        if index < 0 { index += d.count }
        return d[index] + 12 * octave
    }
}

// MARK: - Sigil DNA
//
// The full genome of a track: how it looks, and how it sounds. One struct,
// derived purely from the seed, read by both the renderer and the synth so the
// picture and the music can never drift apart.

struct SigilDNA {
    var seed: UInt64

    // Musical
    var bpm: Double
    var root: Double          // MIDI note of the tonic
    var scale: Scale
    var pluckDensity: Double  // 0..1 chance of a note per sixteenth
    var padVoices: Int
    var subWeight: Double
    var shimmer: Double       // detune / air
    var space: Double         // reverb amount

    // Visual
    var petals: Int
    var rings: Int
    var hue: Double           // 0..1
    var hueSpread: Double
    var twist: Double
    var spikiness: Double
    var orbitRadius: Double   // 0..1 position in the field
    var orbitPhase: Double
    var orbitSpeed: Double

    init(seed: UInt64) {
        self.seed = seed
        var r = Rng(seed: seed)

        bpm = (r.range(56, 92) / 2).rounded() * 2
        root = Double(r.int(33, 45))
        scale = r.pick(Scale.allCases)
        pluckDensity = r.range(0.18, 0.62)
        padVoices = r.int(3, 6)
        subWeight = r.range(0.35, 1.0)
        shimmer = r.range(0.15, 1.0)
        space = r.range(0.45, 0.95)

        petals = r.int(5, 13)
        rings = r.int(3, 6)
        hue = r.unit()
        hueSpread = r.range(0.04, 0.28)
        twist = r.range(-1.4, 1.4)
        spikiness = r.range(0.1, 0.9)
        orbitRadius = r.range(0.22, 1.0)
        orbitPhase = r.range(0, .pi * 2)
        orbitSpeed = r.range(0.4, 1.0) * (r.unit() < 0.5 ? -1 : 1)
    }

    var secondsPerBeat: Double { 60.0 / bpm }

    func color(_ t: Double, brightness: Double = 1.0) -> Color {
        let h = (hue + hueSpread * t).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: h < 0 ? h + 1 : h,
                     saturation: 0.62,
                     brightness: min(1.0, brightness))
    }
}

// MARK: - Track

struct Track: Identifiable, Hashable {
    let id: UUID
    var title: String
    var dna: SigilDNA

    static func == (a: Track, b: Track) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.dna = SigilDNA(seed: hash64(title))
    }
}

// MARK: - The names
//
// Sigil ships with no music files. Each name below is an incantation: it hashes
// into a seed, the seed grows a sigil, and the sigil sings itself.

enum Grimoire {
    static let names: [String] = [
        "Salt Cathedral",
        "Nine Hours of Blue",
        "The Long Room",
        "Moth Weather",
        "Glass Orchard",
        "Slow Lightning",
        "Harbour of Bells",
        "A Field That Remembers",
        "Copper Rain",
        "Tide Without a Moon",
        "The Quiet Machine",
        "Northern Ember",
        "Paper Lantern Drift",
        "Hollow Star",
        "Snowfall in the Archive",
        "Everything Returns Slowly",
        "Velvet Antenna",
        "The Hour of Dust"
    ]

    static func library() -> [Track] { names.map(Track.init(title:)) }
}

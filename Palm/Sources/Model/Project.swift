import Foundation

/// A plugin slot's saved identity. We store the component description rather
/// than a live reference so a project can be reopened after the host restarts.
struct PluginRef: Codable, Equatable, Hashable {
    var manufacturer: UInt32
    var type: UInt32
    var subtype: UInt32
    var name: String

    /// Opaque state blob from `AUAudioUnit.fullState`, archived.
    var state: Data?

    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                     UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return String(bytes: bytes, encoding: .isoLatin1) ?? "????"
    }
}

/// One step of the grid. `velocity == 0` means empty — cheaper than optionals
/// across 8 tracks × 64 steps, and it makes velocity editing a continuous act
/// rather than a create/delete decision.
struct Step: Codable, Equatable {
    var velocity: UInt8 = 0
    var note: UInt8 = 60
    var length: UInt8 = 1      // in steps

    var isOn: Bool { velocity > 0 }
    static let empty = Step()
}

struct Track: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int
    var steps: [Step]
    var volume: Float = 0.8
    var pan: Float = 0
    var isMuted = false
    var isSoloed = false
    var instrument: PluginRef?
    var effects: [PluginRef] = []
    /// Root note the pads are written around; the grid edits offsets from it.
    var rootNote: UInt8 = 60
    var midiChannel: UInt8 = 0

    init(name: String, colorIndex: Int, stepCount: Int = Project.stepCount) {
        self.name = name
        self.colorIndex = colorIndex
        self.steps = Array(repeating: .empty, count: stepCount)
    }
}

struct Project: Codable, Equatable {
    static let stepCount = 64          // 4 bars of sixteenths
    static let stepsPerBar = 16

    var name: String = "Untitled"
    var tempo: Double = 96
    var swing: Double = 0              // 0…0.6, applied to off-eighths
    var tracks: [Track]
    var loopBars: Int = 2
    var metronomeOn = false
    var masterVolume: Float = 0.85

    var loopSteps: Int { min(Project.stepCount, loopBars * Project.stepsPerBar) }

    static func starter() -> Project {
        let names = ["Kick", "Snare", "Hats", "Bass", "Keys", "Pad", "Lead", "Perc"]
        var tracks: [Track] = []
        for (i, name) in names.enumerated() {
            var t = Track(name: name, colorIndex: i)
            t.rootNote = [36, 38, 42, 40, 60, 60, 72, 48][i]
            t.midiChannel = UInt8(i)
            tracks.append(t)
        }
        // A four-on-the-floor with an offbeat hat: something plays the instant
        // you press start, so the app is never a blank grid.
        for s in stride(from: 0, to: Project.stepCount, by: 4) {
            tracks[0].steps[s] = Step(velocity: 110, note: 36, length: 1)
        }
        for s in stride(from: 4, to: Project.stepCount, by: 8) {
            tracks[1].steps[s] = Step(velocity: 96, note: 38, length: 1)
        }
        for s in stride(from: 2, to: Project.stepCount, by: 4) {
            tracks[2].steps[s] = Step(velocity: 70, note: 42, length: 1)
        }
        let bassline: [(Int, UInt8)] = [(0, 40), (6, 40), (8, 43), (14, 45)]
        for bar in 0..<4 {
            for (offset, note) in bassline {
                tracks[3].steps[bar * 16 + offset] = Step(velocity: 100, note: note, length: 2)
            }
        }
        return Project(tracks: tracks)
    }
}

// MARK: - Persistence

enum ProjectStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("palm-project.json")
    }

    static func save(_ project: Project) {
        guard let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Project {
        guard let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(Project.self, from: data)
        else { return .starter() }
        return project
    }
}

import Foundation
import os

/// A snapshot of everything the sequencer needs, in a form it can read from its
/// own thread without touching the main actor. The UI writes it whenever the
/// project changes; the sequencer reads it every few milliseconds.
final class Pattern: @unchecked Sendable {
    struct Snapshot {
        var tracks: [Track] = []
        var tempo: Double = 96
        var swing: Double = 0
        var loopSteps: Int = 32
        var metronomeOn = false
        var anySoloed = false
    }

    private var lock = os_unfair_lock_s()
    private var snapshot = Snapshot()

    func update(from project: Project) {
        let next = Snapshot(tracks: project.tracks,
                            tempo: project.tempo,
                            swing: project.swing,
                            loopSteps: project.loopSteps,
                            metronomeOn: project.metronomeOn,
                            anySoloed: project.tracks.contains { $0.isSoloed })
        os_unfair_lock_lock(&lock)
        snapshot = next
        os_unfair_lock_unlock(&lock)
    }

    var current: Snapshot {
        os_unfair_lock_lock(&lock)
        let s = snapshot
        os_unfair_lock_unlock(&lock)
        return s
    }
}

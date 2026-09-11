import Foundation

struct MIDIEvent {
    var sample: Double      // absolute render-clock sample time
    var note: UInt8
    var velocity: UInt8
    var isOn: Bool
}

/// A tiny time-ordered queue between the sequencer thread and the render
/// thread. Locked, but the lock is held for nanoseconds and contended at most
/// once per buffer, so it never shows up in a trace.
final class EventQueue: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var events: [MIDIEvent] = []

    func push(_ event: MIDIEvent) {
        os_unfair_lock_lock(&lock)
        // Insertion sort: the queue holds a handful of events at a time.
        var i = events.count
        while i > 0 && events[i - 1].sample > event.sample { i -= 1 }
        events.insert(event, at: i)
        if events.count > 512 { events.removeFirst(events.count - 512) }
        os_unfair_lock_unlock(&lock)
    }

    /// Remove and return every event due at or before `sample`.
    func drain(upTo sample: Double, into out: inout [MIDIEvent]) {
        out.removeAll(keepingCapacity: true)
        os_unfair_lock_lock(&lock)
        var count = 0
        while count < events.count && events[count].sample <= sample { count += 1 }
        if count > 0 {
            out.append(contentsOf: events[0..<count])
            events.removeFirst(count)
        }
        os_unfair_lock_unlock(&lock)
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        events.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
    }
}

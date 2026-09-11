import AVFoundation
import os

/// One track's signal path: a source (built-in synth or an AUv3 instrument),
/// an ordered list of AUv3 effects, and a mixer that owns volume and pan.
final class TrackChain: @unchecked Sendable {
    let index: Int
    let mixer = AVAudioMixerNode()
    let events = EventQueue()
    let instrument: BuiltInInstrument

    private(set) var sourceNode: AVAudioSourceNode!
    private(set) var auInstrument: AVAudioUnit?
    private(set) var auEffects: [AVAudioUnit] = []

    /// Shared with the render block. Written by the audio thread only.
    private let clock: RenderClock
    private let monoFormat: AVAudioFormat

    init(index: Int, sampleRate: Double, clock: RenderClock, kind: VoiceKind) {
        self.index = index
        self.clock = clock
        self.instrument = BuiltInInstrument(sampleRate: sampleRate)
        self.instrument.kind = kind

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.monoFormat = format
        let queue = events
        let synth = instrument
        var scratch: [MIDIEvent] = []
        scratch.reserveCapacity(64)

        sourceNode = AVAudioSourceNode(format: format) { [clock] _, timestamp, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let start = timestamp.pointee.mSampleTime
            clock.publish(sample: start, frames: Int(frameCount))

            var cursor = 0
            let frames = Int(frameCount)
            while cursor < frames {
                // Drain to the *next* event so notes land on the right frame,
                // not merely in the right buffer.
                queue.drain(upTo: start + Double(cursor), into: &scratch)
                for e in scratch {
                    if e.isOn { synth.noteOn(e.note, velocity: e.velocity) }
                    else { synth.noteOff(e.note) }
                }
                out[cursor] = synth.render()
                cursor += 1
            }
            return noErr
        }
    }

    // MARK: - Graph

    /// Rebuild this track's connections. Called on load, on plugin change, and
    /// on engine restart — always the same code path, so there is only one
    /// version of the graph to reason about.
    func connect(in engine: AVAudioEngine, to destination: AVAudioNode, format: AVAudioFormat) {
        let head: AVAudioNode = auInstrument ?? sourceNode
        var nodes: [AVAudioNode] = [head]
        nodes.append(contentsOf: auEffects as [AVAudioNode])
        nodes.append(mixer)

        for node in nodes where node.engine == nil { engine.attach(node) }

        for i in 0..<(nodes.count - 1) {
            engine.disconnectNodeOutput(nodes[i])
        }
        for i in 0..<(nodes.count - 1) {
            // A nil format lets each AU negotiate its own channel count; the
            // mixer downstream reconciles them.
            engine.connect(nodes[i], to: nodes[i + 1],
                           format: (i == 0 && auInstrument == nil) ? monoFormat : nil)
        }
        engine.disconnectNodeOutput(mixer)
        engine.connect(mixer, to: destination, format: format)
    }

    func detachAll(from engine: AVAudioEngine) {
        for node in ([auInstrument, mixer, sourceNode].compactMap { $0 } + auEffects) where node.engine != nil {
            engine.detach(node)
        }
    }

    func setInstrument(_ unit: AVAudioUnit?, in engine: AVAudioEngine) {
        if let old = auInstrument, old.engine != nil { engine.detach(old) }
        auInstrument = unit
        allNotesOff()
    }

    func setEffects(_ units: [AVAudioUnit], in engine: AVAudioEngine) {
        for old in auEffects where old.engine != nil { engine.detach(old) }
        auEffects = units
    }

    // MARK: - Playback

    func schedule(_ event: MIDIEvent) {
        if let au = auInstrument {
            sendToAU(au, event: event)
        } else {
            events.push(event)
        }
    }

    private func sendToAU(_ unit: AVAudioUnit, event: MIDIEvent) {
        guard let block = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        let status: UInt8 = (event.isOn ? 0x90 : 0x80)
        var bytes: [UInt8] = [status, event.note, event.isOn ? event.velocity : 0]
        // Offset the event into the AU's current render cycle when we can, so
        // plugin timing matches the built-in voices instead of drifting by a buffer.
        let offset = event.sample - clock.currentSample
        let frames = AUEventSampleTime(max(0, min(4096, offset.rounded())))
        bytes.withUnsafeBufferPointer { ptr in
            block(AUEventSampleTimeImmediate + frames, 0, 3, ptr.baseAddress!)
        }
    }

    func allNotesOff() {
        events.clear()
        instrument.allNotesOff()
        if let block = auInstrument?.auAudioUnit.scheduleMIDIEventBlock {
            for channel in 0..<16 {
                var bytes: [UInt8] = [0xB0 | UInt8(channel), 123, 0]   // All Notes Off
                bytes.withUnsafeBufferPointer { ptr in
                    block(AUEventSampleTimeImmediate, 0, 3, ptr.baseAddress!)
                }
            }
        }
    }

    func apply(_ track: Track, anySoloed: Bool) {
        let audible = track.isSoloed || (!anySoloed && !track.isMuted)
        mixer.outputVolume = audible ? track.volume : 0
        mixer.pan = track.pan
    }
}

/// The render clock. One number, written by the audio thread and read by the
/// sequencer, so both agree on "now" in samples.
final class RenderClock: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var sample: Double = 0
    private var horizon: Double = 0

    func publish(sample: Double, frames: Int) {
        os_unfair_lock_lock(&lock)
        if sample > self.sample {
            self.sample = sample
            self.horizon = sample + Double(frames)
        }
        os_unfair_lock_unlock(&lock)
    }

    var currentSample: Double {
        os_unfair_lock_lock(&lock)
        let s = sample
        os_unfair_lock_unlock(&lock)
        return s
    }

    var bufferEnd: Double {
        os_unfair_lock_lock(&lock)
        let s = horizon
        os_unfair_lock_unlock(&lock)
        return s
    }
}

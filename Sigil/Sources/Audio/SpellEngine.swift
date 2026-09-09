import AVFoundation
import Combine
import QuartzCore

/// Shared state between the render thread and the UI. Small, plain, and
/// guarded by an unfair lock — no allocation, no ARC traffic in the callback.
private final class RenderBox {
    var lock = os_unfair_lock_s()
    var bands = SIMD3<Float>.zero
    var position: Double = 0
    var fade: Float = 1          // 0 = fully on the outgoing voice, 1 = incoming
}

/// The engine. One incoming voice, one outgoing voice, and a crossfade between
/// them that is *always* running — Sigil never cuts, it dissolves.
@MainActor
final class SpellEngine: ObservableObject {

    /// Every track is six minutes of weather. Nothing loops; the seed just keeps
    /// unfolding.
    static let trackLength: Double = 360

    @Published private(set) var bands: SIMD3<Float> = .zero
    @Published private(set) var position: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var current: Track?

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode?
    private var display: CADisplayLink?

    private let box = RenderBox()

    private var sampleRate: Double = 48_000

    init() {
        configureSession()
        buildGraph()
        startDisplayLink()
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        #endif
    }

    private func buildGraph() {
        sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 48_000 }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let node = AVAudioSourceNode(format: format) { [box] _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let left = abl[0].mData?.assumingMemoryBound(to: Float.self)
            let right = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : left

            // The voices live in RenderState, not in the MainActor engine, so
            // nothing here has to hop actors or allocate.
            for frame in 0..<Int(frameCount) {
                let (l, r) = RenderState.shared.next()
                left?[frame] = l
                right?[frame] = r
            }

            os_unfair_lock_lock(&box.lock)
            box.bands = RenderState.shared.bands
            box.position = RenderState.shared.position
            box.fade = RenderState.shared.fadeValue
            os_unfair_lock_unlock(&box.lock)
            return noErr
        }

        engine.attach(node)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 42
        engine.connect(node, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        source = node

        RenderState.shared.configure(sampleRate: sampleRate)

        do { try engine.start() } catch {
            print("Sigil: audio engine failed to start — \(error)")
        }
    }

    private func startDisplayLink() {
        #if os(iOS)
        let link = CADisplayLink(target: DisplayProxy { [weak self] in self?.tick() },
                                 selector: #selector(DisplayProxy.fire))
        link.add(to: .main, forMode: .common)
        display = link
        #endif
    }

    private func tick() {
        os_unfair_lock_lock(&box.lock)
        let b = box.bands
        let p = box.position
        os_unfair_lock_unlock(&box.lock)
        bands = b
        position = p
    }

    // MARK: - Transport

    /// Summon a track. If something is already burning, it becomes the outgoing
    /// voice and dissolves over `crossfade` seconds.
    func summon(_ track: Track, crossfade: Double = 2.6) {
        current = track
        isPlaying = true
        RenderState.shared.summon(dna: track.dna, crossfade: crossfade)
    }

    func togglePlay() {
        guard current != nil else { return }
        isPlaying.toggle()
        RenderState.shared.setPlaying(isPlaying)
    }

    func seek(toFraction f: Double) {
        RenderState.shared.seek(seconds: max(0, min(1, f)) * Self.trackLength)
    }

    func dismiss() {
        isPlaying = false
        current = nil
        RenderState.shared.setPlaying(false)
    }
}

/// A tiny target so CADisplayLink doesn't need an @objc MainActor class.
private final class DisplayProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

// MARK: - RenderState
//
// Owned by the audio thread. The UI never touches it directly; it posts intents
// through a lock-free-enough command slot that the render thread drains.

final class RenderState: @unchecked Sendable {
    static let shared = RenderState()

    private var sampleRate: Double = 48_000
    private var incoming: SigilVoice?
    private var outgoing: SigilVoice?

    private var fade: Float = 1
    private var fadeRate: Float = 0
    private var gain: Float = 0
    private var gainTarget: Float = 0

    private var commandLock = os_unfair_lock_s()
    private var pendingSummon: (SigilDNA, Double)?
    private var pendingSeek: Double?
    private var pendingPlaying: Bool?

    private(set) var bands: SIMD3<Float> = .zero
    var position: Double { incoming?.positionSeconds ?? 0 }
    var fadeValue: Float { fade }

    func configure(sampleRate: Double) { self.sampleRate = sampleRate }

    func summon(dna: SigilDNA, crossfade: Double) {
        os_unfair_lock_lock(&commandLock)
        pendingSummon = (dna, crossfade)
        pendingPlaying = true
        os_unfair_lock_unlock(&commandLock)
    }

    func seek(seconds: Double) {
        os_unfair_lock_lock(&commandLock)
        pendingSeek = seconds
        os_unfair_lock_unlock(&commandLock)
    }

    func setPlaying(_ playing: Bool) {
        os_unfair_lock_lock(&commandLock)
        pendingPlaying = playing
        os_unfair_lock_unlock(&commandLock)
    }

    private func drainCommands() {
        guard os_unfair_lock_trylock(&commandLock) else { return }
        if let (dna, crossfade) = pendingSummon {
            pendingSummon = nil
            if incoming != nil {
                outgoing = incoming
            }
            incoming = SigilVoice(dna: dna, sampleRate: sampleRate)
            fade = outgoing == nil ? 1 : 0
            fadeRate = Float(1.0 / max(0.2, crossfade) / sampleRate)
            gainTarget = 1
        }
        if let seconds = pendingSeek {
            pendingSeek = nil
            incoming?.seek(toSeconds: seconds)
        }
        if let playing = pendingPlaying {
            pendingPlaying = nil
            gainTarget = playing ? 1 : 0
        }
        os_unfair_lock_unlock(&commandLock)
    }

    private var frameCounter = 0

    @inline(__always) func next() -> (Float, Float) {
        // Commands are checked on a coarse grid: 128 frames is under 3ms, far
        // below the threshold of feeling, and keeps the lock out of the hot path.
        if frameCounter & 127 == 0 { drainCommands() }
        frameCounter &+= 1

        // A 12ms glide on the master gain: pause and resume become breaths.
        gain += (gainTarget - gain) * Float(1.0 / (0.012 * sampleRate))

        var l: Float = 0, r: Float = 0

        if fade < 1 {
            fade = min(1, fade + fadeRate)
            if var out = outgoing {
                let (ol, or) = out.next()
                outgoing = out
                let g = 1 - fade
                // Equal-power fade: no dip through the middle of the crossing.
                let gp = sin(g * .pi / 2)
                l += ol * gp
                r += or * gp
            }
            if fade >= 1 { outgoing = nil }
        }

        if var inc = incoming {
            let (il, ir) = inc.next()
            bands = inc.bands
            incoming = inc
            let gp = sin(fade * .pi / 2)
            l += il * gp
            r += ir * gp
        }

        return (l * gain, r * gain)
    }
}

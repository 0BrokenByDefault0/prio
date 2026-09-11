import AVFoundation
import os
import Combine
import SwiftUI

/// The whole audio system: graph, transport, sequencer and plugin slots.
///
/// The sequencer does not run on the main actor. It runs on its own queue
/// against a lock-guarded snapshot of the pattern, stamping events in
/// render-clock samples — so scrolling the grid, opening a plugin window or
/// rotating the phone cannot push the beat around.
@MainActor
final class PalmEngine: ObservableObject {

    @Published var project: Project {
        didSet {
            pattern.update(from: project)
            applyMix()
            scheduleSave()
        }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var playhead = 0
    @Published private(set) var loadedInstruments: [Int: AVAudioUnit] = [:]
    @Published private(set) var loadedEffects: [Int: [AVAudioUnit]] = [:]
    @Published private(set) var statusMessage: String?

    let registry = AUv3Registry()

    private let engine = AVAudioEngine()
    private let clock = RenderClock()
    private let pattern = Pattern()
    private let transport = Transport()
    private var chains: [TrackChain] = []
    private var metronome: TrackChain?
    private var sampleRate: Double = 48_000
    private var saveTask: Task<Void, Never>?
    private let playheadBox = PlayheadBox()

    private var timer: DispatchSourceTimer?
    private let seqQueue = DispatchQueue(label: "art.palm.sequencer", qos: .userInteractive)

    init() {
        project = ProjectStore.load()
        pattern.update(from: project)
        configureSession()
        buildGraph()
        applyMix()
        registry.scan()
        restorePlugins()
        observePlayhead()
        startTimer()
    }

    // MARK: - Session & graph

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.mixWithOthers` is what lets Palm sit alongside AUM or GarageBand
            // instead of stealing the route out from under them.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            statusMessage = "Audio session: \(error.localizedDescription)"
        }
        sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectAll() }
        }
    }

    private var stereoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private func buildGraph() {
        chains = project.tracks.indices.map { i in
            TrackChain(index: i, sampleRate: sampleRate, clock: clock,
                       kind: VoiceKind.default(forTrack: i))
        }
        let click = TrackChain(index: 99, sampleRate: sampleRate, clock: clock, kind: .hat)
        metronome = click

        for chain in chains + [click] {
            chain.connect(in: engine, to: engine.mainMixerNode, format: stereoFormat)
        }
        click.mixer.outputVolume = 0.45
        transport.configure(chains: chains, metronome: click, sampleRate: sampleRate)
        engine.mainMixerNode.outputVolume = project.masterVolume
        engine.prepare()
        start()
    }

    private func reconnectAll() {
        for chain in chains + [metronome].compactMap({ $0 }) {
            chain.connect(in: engine, to: engine.mainMixerNode, format: stereoFormat)
        }
        start()
    }

    private func start() {
        guard !engine.isRunning else { return }
        do { try engine.start() } catch {
            statusMessage = "Engine: \(error.localizedDescription)"
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            stop()
        case .ended:
            try? AVAudioSession.sharedInstance().setActive(true)
            start()
        @unknown default:
            break
        }
    }

    private func scheduleSave() {
        // Dragging a velocity writes the project sixty times a second; only the
        // last one is worth putting on disk.
        saveTask?.cancel()
        let snapshot = project
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            ProjectStore.save(snapshot)
        }
    }

    // MARK: - Mix

    private func applyMix() {
        let anySoloed = project.tracks.contains { $0.isSoloed }
        for (i, track) in project.tracks.enumerated() where i < chains.count {
            chains[i].apply(track, anySoloed: anySoloed)
        }
        engine.mainMixerNode.outputVolume = project.masterVolume
    }

    // MARK: - Transport

    var stepDuration: Double { 60.0 / project.tempo / 4.0 }

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        guard !isPlaying else { return }
        start()
        isPlaying = true
        transport.begin(atSample: clock.currentSample + sampleRate * 0.06)
    }

    func stop() {
        isPlaying = false
        transport.end()
        for chain in chains { chain.allNotesOff() }
        playhead = 0
    }

    /// Runs on `seqQueue`. The transport owns its own references to the graph
    /// behind its lock, so this handler never reaches back into the main actor.
    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: seqQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .milliseconds(1))
        let transport = self.transport
        let pattern = self.pattern
        let clock = self.clock
        let box = playheadBox
        t.setEventHandler {
            guard let step = transport.advance(pattern: pattern.current, clock: clock) else { return }
            box.publish(step)
        }
        t.resume()
        timer = t
    }

    /// The playhead crosses threads about sixteen times a second. The box
    /// coalesces it so the main actor is woken only when the number changes.
    private func observePlayhead() {
        playheadBox.onChange = { [weak self] step in
            Task { @MainActor in
                guard let self, self.playhead != step else { return }
                self.playhead = step
            }
        }
    }

    /// Audition a step immediately, so editing while stopped is never silent.
    func audition(track index: Int, note: UInt8, velocity: UInt8) {
        guard index < chains.count else { return }
        let chain = chains[index]
        let renderClock = clock
        chain.schedule(MIDIEvent(sample: renderClock.currentSample + 32,
                                 note: note, velocity: velocity, isOn: true))
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            chain.schedule(MIDIEvent(sample: renderClock.currentSample,
                                     note: note, velocity: 0, isOn: false))
        }
    }

    // MARK: - Plugins

    func loadInstrument(_ plugin: AUv3Plugin?, onTrack index: Int) async {
        guard index < chains.count else { return }
        guard let plugin else {
            chains[index].setInstrument(nil, in: engine)
            loadedInstruments[index] = nil
            project.tracks[index].instrument = nil
            reconnect(index)
            return
        }
        do {
            let unit = try await AUv3Registry.instantiate(plugin.description)
            chains[index].setInstrument(unit, in: engine)
            loadedInstruments[index] = unit
            project.tracks[index].instrument = plugin.ref
            reconnect(index)
            statusMessage = "\(plugin.name) → \(project.tracks[index].name)"
        } catch {
            statusMessage = "Couldn't load \(plugin.name)"
        }
    }

    func addEffect(_ plugin: AUv3Plugin, onTrack index: Int) async {
        guard index < chains.count else { return }
        do {
            let unit = try await AUv3Registry.instantiate(plugin.description)
            var units = loadedEffects[index] ?? []
            units.append(unit)
            chains[index].setEffects(units, in: engine)
            loadedEffects[index] = units
            project.tracks[index].effects.append(plugin.ref)
            reconnect(index)
            statusMessage = "\(plugin.name) on \(project.tracks[index].name)"
        } catch {
            statusMessage = "Couldn't load \(plugin.name)"
        }
    }

    func removeEffect(at slot: Int, onTrack index: Int) {
        guard index < chains.count, var units = loadedEffects[index], slot < units.count else { return }
        units.remove(at: slot)
        chains[index].setEffects(units, in: engine)
        loadedEffects[index] = units
        if slot < project.tracks[index].effects.count {
            project.tracks[index].effects.remove(at: slot)
        }
        reconnect(index)
    }

    private func reconnect(_ index: Int) {
        chains[index].connect(in: engine, to: engine.mainMixerNode, format: stereoFormat)
        start()
        applyMix()
    }

    /// Reopen whatever the saved project had loaded. Failures are per slot: a
    /// missing plugin costs you that sound, not the session.
    private func restorePlugins() {
        let snapshot = project.tracks
        Task {
            for (index, track) in snapshot.enumerated() {
                if let ref = track.instrument,
                   let plugin = registry.instruments.first(where: { $0.ref == ref }) {
                    await loadInstrument(plugin, onTrack: index)
                }
                for ref in track.effects {
                    if let plugin = registry.effects.first(where: { $0.ref == ref }) {
                        await addEffect(plugin, onTrack: index)
                    }
                }
            }
        }
    }

    func voiceKind(forTrack index: Int) -> VoiceKind {
        index < chains.count ? chains[index].instrument.kind : .tone
    }

    func setVoiceKind(_ kind: VoiceKind, forTrack index: Int) {
        guard index < chains.count else { return }
        chains[index].instrument.kind = kind
    }

    func clearStatus() { statusMessage = nil }
}

/// The clock-driven step scheduler. Lives entirely off the main actor.
final class Transport: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var running = false
    private var nextStep = 0
    private var nextSample: Double = 0
    private var pendingOffs: [(sample: Double, track: Int, note: UInt8)] = []
    private var chains: [TrackChain] = []
    private var metronome: TrackChain?
    private var sampleRate: Double = 48_000

    func configure(chains: [TrackChain], metronome: TrackChain?, sampleRate: Double) {
        os_unfair_lock_lock(&lock)
        self.chains = chains
        self.metronome = metronome
        self.sampleRate = sampleRate
        os_unfair_lock_unlock(&lock)
    }

    func begin(atSample sample: Double) {
        os_unfair_lock_lock(&lock)
        running = true
        nextStep = 0
        nextSample = sample
        pendingOffs.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    func end() {
        os_unfair_lock_lock(&lock)
        running = false
        pendingOffs.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    /// Fill a 120 ms horizon. Returns the step the listener is currently
    /// hearing, or nil if stopped.
    func advance(pattern: Pattern.Snapshot, clock: RenderClock) -> Int? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard running else { return nil }

        let now = clock.currentSample
        let horizon = now + sampleRate * 0.12
        let samplesPerStep = 60.0 / pattern.tempo / 4.0 * sampleRate
        let loop = max(1, pattern.loopSteps)

        // Note-offs first, so a retriggered note releases before it reattacks.
        pendingOffs.removeAll { entry in
            guard entry.sample <= horizon else { return false }
            guard entry.track < chains.count else { return true }
            chains[entry.track].schedule(MIDIEvent(sample: entry.sample, note: entry.note,
                                                   velocity: 0, isOn: false))
            return true
        }

        var guardCount = 0
        while nextSample < horizon && guardCount < 64 {
            guardCount += 1
            let step = nextStep % loop
            let swing = (pattern.swing > 0 && step % 2 == 1)
                ? samplesPerStep * pattern.swing * 0.5 : 0
            let at = nextSample + swing

            for (i, track) in pattern.tracks.enumerated() where i < chains.count {
                guard step < track.steps.count else { continue }
                let s = track.steps[step]
                guard s.isOn else { continue }
                let audible = track.isSoloed || (!pattern.anySoloed && !track.isMuted)
                guard audible else { continue }
                chains[i].schedule(MIDIEvent(sample: at, note: s.note, velocity: s.velocity, isOn: true))
                pendingOffs.append((at + Double(max(1, s.length)) * samplesPerStep * 0.9, i, s.note))
            }

            if pattern.metronomeOn, step % 4 == 0, let metronome {
                metronome.schedule(MIDIEvent(sample: nextSample,
                                             note: step % 16 == 0 ? 84 : 72,
                                             velocity: step % 16 == 0 ? 90 : 50, isOn: true))
            }

            nextSample += samplesPerStep
            nextStep += 1
        }

        // Derive the playhead from the clock rather than counting it, so the
        // cursor can never drift away from what you are hearing.
        let stepsAhead = (nextSample - now) / samplesPerStep
        let heard = Double(nextStep) - stepsAhead
        let index = Int(floor(max(0, heard))) % loop
        return index
    }
}

/// Coalesces the playhead as it crosses from the sequencer queue to the UI.
final class PlayheadBox: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var last = -1
    var onChange: ((Int) -> Void)?

    func publish(_ step: Int) {
        os_unfair_lock_lock(&lock)
        let changed = step != last
        last = step
        let handler = onChange
        os_unfair_lock_unlock(&lock)
        if changed { handler?(step) }
    }
}

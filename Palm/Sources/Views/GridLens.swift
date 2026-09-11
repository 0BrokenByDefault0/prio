import SwiftUI

/// The sequencer.
///
/// Portrait gives you one track as a 4×4 pad matrix — pads large enough to play
/// one-handed while walking. Landscape gives you all eight tracks against all
/// sixteen steps. Same data, same gestures, same selection; only the density
/// changes, so rotating the phone never costs you your place.
struct GridLens: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selectedTrack: Int
    @Binding var selectedBar: Int

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            VStack(spacing: P.gap) {
                TrackStrip(engine: engine, selected: $selectedTrack, compact: landscape)
                BarStrip(engine: engine, selectedBar: $selectedBar)

                if landscape {
                    matrix
                } else {
                    padGrid
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    private var stepOffset: Int { selectedBar * Project.stepsPerBar }

    // MARK: - Landscape: every track, every step

    private var matrix: some View {
        VStack(spacing: 3) {
            ForEach(engine.project.tracks.indices, id: \.self) { t in
                HStack(spacing: 3) {
                    ForEach(0..<Project.stepsPerBar, id: \.self) { s in
                        StepCell(engine: engine,
                                 track: t,
                                 step: stepOffset + s,
                                 isBeat: s % 4 == 0,
                                 compact: true)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Portrait: one track, sixteen big pads

    private var padGrid: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { col in
                        StepCell(engine: engine,
                                 track: selectedTrack,
                                 step: stepOffset + row * 4 + col,
                                 isBeat: col == 0,
                                 compact: false)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// One step. Tap toggles it; drag up and down sets velocity without any mode
/// change, so there is no second editing state to learn or get stuck in.
private struct StepCell: View {
    @ObservedObject var engine: PalmEngine
    let track: Int
    let step: Int
    let isBeat: Bool
    let compact: Bool

    @State private var dragStart: Int?

    private var value: Step {
        guard track < engine.project.tracks.count,
              step < engine.project.tracks[track].steps.count else { return .empty }
        return engine.project.tracks[track].steps[step]
    }

    private var isPlaying: Bool {
        engine.isPlaying && engine.playhead == step
    }

    var body: some View {
        let color = P.trackColor(track)
        let on = value.isOn
        let strength = Double(value.velocity) / 127

        RoundedRectangle(cornerRadius: compact ? 6 : 16, style: .continuous)
            .fill(on ? color.opacity(0.30 + 0.55 * strength) : (isBeat ? P.raised : P.surface))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 16, style: .continuous)
                    .strokeBorder(isPlaying ? P.ink.opacity(0.9) : (on ? color.opacity(0.9) : P.line),
                                  lineWidth: isPlaying ? 2 : 1)
            )
            .overlay {
                if !compact {
                    VStack(spacing: 2) {
                        Text("\(step % Project.stepsPerBar + 1)")
                            .font(P.label(11))
                            .foregroundStyle(on ? P.ground.opacity(0.75) : P.faint)
                        if on {
                            Text("\(value.velocity)")
                                .font(P.numeral(15))
                                .foregroundStyle(P.ground)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard track < engine.project.tracks.count,
                              step < engine.project.tracks[track].steps.count else { return }
                        if dragStart == nil {
                            dragStart = Int(engine.project.tracks[track].steps[step].velocity)
                        }
                        let travel = -Double(g.translation.height)
                        guard abs(travel) > 6 else { return }
                        let base = Double(dragStart ?? 0)
                        let v = max(1, min(127, base + travel * 0.6))
                        engine.project.tracks[track].steps[step].velocity = UInt8(v)
                        engine.project.tracks[track].steps[step].note = engine.project.tracks[track].rootNote
                    }
                    .onEnded { g in
                        defer { dragStart = nil }
                        let moved = abs(g.translation.height) > 6 || abs(g.translation.width) > 6
                        guard !moved else { Haptic.tap(); return }
                        toggle()
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: on)
            .accessibilityLabel("Track \(track + 1) step \(step + 1)")
            .accessibilityValue(on ? "on, velocity \(value.velocity)" : "off")
    }

    private func toggle() {
        guard track < engine.project.tracks.count,
              step < engine.project.tracks[track].steps.count else { return }
        let root = engine.project.tracks[track].rootNote
        if engine.project.tracks[track].steps[step].isOn {
            engine.project.tracks[track].steps[step] = .empty
            Haptic.tap()
        } else {
            engine.project.tracks[track].steps[step] = Step(velocity: 100, note: root, length: 1)
            Haptic.firm()
            engine.audition(track: track, note: root, velocity: 100)
        }
    }
}

/// The track selector. Always on screen in both orientations — selecting a
/// track is never a trip into a menu.
private struct TrackStrip: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selected: Int
    let compact: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(engine.project.tracks.indices, id: \.self) { i in
                    let track = engine.project.tracks[i]
                    let color = P.trackColor(i)
                    Button {
                        Haptic.select()
                        selected = i
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(track.name).font(P.label(13))
                            if track.isMuted {
                                Image(systemName: "speaker.slash.fill").font(.system(size: 9))
                            }
                            if track.isSoloed {
                                Text("S").font(P.label(10)).foregroundStyle(P.teal)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(height: P.touch - 4)
                        .foregroundStyle(selected == i ? P.ground : P.dim)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected == i ? color : P.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(selected == i ? .clear : P.line)
                        )
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: P.touch - 4)
    }
}

/// Which bar you are editing, plus the loop length. Two things that belong
/// together and are usually two screens apart.
private struct BarStrip: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selectedBar: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { bar in
                let inLoop = bar < engine.project.loopBars
                Button {
                    Haptic.select()
                    selectedBar = bar
                } label: {
                    Text("\(bar + 1)")
                        .font(P.label(13))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(selectedBar == bar ? P.ground : (inLoop ? P.dim : P.faint))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedBar == bar ? P.ink : P.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(inLoop ? P.line : P.line.opacity(0.4))
                        )
                        .opacity(inLoop ? 1 : 0.5)
                }
                .buttonStyle(PressStyle())
            }

            Divider().frame(height: 24).overlay(P.line)

            Button {
                Haptic.select()
                engine.project.loopBars = engine.project.loopBars % 4 + 1
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "repeat").font(.system(size: 11, weight: .bold))
                    Text("\(engine.project.loopBars) bar\(engine.project.loopBars == 1 ? "" : "s")")
                        .font(P.label(12))
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(P.teal)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(P.raised))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.line))
            }
            .buttonStyle(PressStyle())
        }
    }
}

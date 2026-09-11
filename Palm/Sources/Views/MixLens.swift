import SwiftUI

/// The mixer. A grid of identical track cards that reflows by available width:
/// one column on a narrow phone, two in landscape, four on an iPad. No
/// horizontal scrolling to find track 8, and no fader thinner than a finger.
struct MixLens: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selectedTrack: Int

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: P.gap)],
                      spacing: P.gap) {
                ForEach(engine.project.tracks.indices, id: \.self) { i in
                    TrackCard(engine: engine, index: i, isSelected: selectedTrack == i) {
                        selectedTrack = i
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            MasterCard(engine: engine)
                .padding(.horizontal, 12)
                .padding(.top, P.gap)
                .padding(.bottom, 14)
        }
    }
}

private struct TrackCard: View {
    @ObservedObject var engine: PalmEngine
    let index: Int
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let color = P.trackColor(index)
        let track = engine.project.tracks[index]

        VStack(spacing: P.gap) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(track.name)
                    .font(P.title(16))
                    .foregroundStyle(P.ink)
                Spacer(minLength: 0)

                Toggle2(label: "M", isOn: track.isMuted, tint: P.rose) {
                    engine.project.tracks[index].isMuted.toggle()
                }
                Toggle2(label: "S", isOn: track.isSoloed, tint: P.teal) {
                    engine.project.tracks[index].isSoloed.toggle()
                }
            }

            DragValue(title: "Level",
                      value: Binding(get: { Double(track.volume) },
                                     set: { engine.project.tracks[index].volume = Float($0) }),
                      range: 0...1,
                      format: { $0 <= 0.001 ? "−∞" : String(format: "%.0f%%", $0 * 100) },
                      tint: color)

            DragValue(title: "Pan",
                      value: Binding(get: { Double(track.pan) },
                                     set: { engine.project.tracks[index].pan = Float($0) }),
                      range: -1...1,
                      format: { v in
                          abs(v) < 0.02 ? "Centre"
                              : String(format: "%@ %.0f", v < 0 ? "L" : "R", abs(v) * 100)
                      },
                      tint: color)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: P.radius + 4, style: .continuous).fill(P.surface))
        .overlay(
            RoundedRectangle(cornerRadius: P.radius + 4, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.8) : P.line, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { Haptic.select(); select() }
    }
}

private struct MasterCard: View {
    @ObservedObject var engine: PalmEngine

    var body: some View {
        VStack(spacing: P.gap) {
            HStack {
                Text("MASTER").font(P.label(11)).tracking(1.8).foregroundStyle(P.faint)
                Spacer()
            }
            DragValue(title: "Output",
                      value: Binding(get: { Double(engine.project.masterVolume) },
                                     set: { engine.project.masterVolume = Float($0) }),
                      range: 0...1,
                      format: { String(format: "%.0f%%", $0 * 100) },
                      tint: P.amber)
            DragValue(title: "Swing", value: $engine.project.swing, range: 0...0.6,
                      format: { String(format: "%.0f%%", 50 + $0 * 50) }, tint: P.teal)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: P.radius + 4, style: .continuous).fill(P.surface))
        .overlay(RoundedRectangle(cornerRadius: P.radius + 4, style: .continuous).strokeBorder(P.line))
    }
}

/// Mute and solo. Square, 48pt, and always in the same corner of every card.
private struct Toggle2: View {
    let label: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(label)
                .font(P.label(14))
                .frame(width: P.touch, height: P.touch - 6)
                .foregroundStyle(isOn ? P.ground : P.dim)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isOn ? tint : P.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(isOn ? .clear : P.line)
                )
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label == "M" ? "Mute" : "Solo")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

import SwiftUI

enum Lens: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case mix = "Mix"
    case rack = "Rack"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .mix:  return "slider.vertical.3"
        case .rack: return "rectangle.stack.fill"
        }
    }
    var tipLens: Tip.Lens {
        switch self {
        case .grid: return .grid
        case .mix:  return .mix
        case .rack: return .rack
        }
    }
}

/// The shell. There is one layout, described once, and it reflows by axis —
/// not two layouts chosen by orientation, which is how most iOS DAWs end up
/// with controls that exist in landscape and vanish in portrait.
struct RootView: View {
    @StateObject private var engine = PalmEngine()
    @State private var lens: Lens = .grid
    @State private var selectedTrack = 0
    @State private var selectedBar = 0
    @State private var showTips = false
    @AppStorage("palm.railOnLeading") private var railOnLeading = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            ZStack {
                P.ground.ignoresSafeArea()

                Group {
                    if landscape {
                        HStack(spacing: 0) {
                            if railOnLeading { rail(axis: .vertical) }
                            content
                            if !railOnLeading { rail(axis: .vertical) }
                        }
                    } else {
                        VStack(spacing: 0) {
                            content
                            rail(axis: .horizontal)
                        }
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: landscape)

                if let message = engine.statusMessage {
                    Toast(message: message) { engine.clearStatus() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTips) {
            TipsView(initial: lens.tipLens)
                .presentationDetents([.medium, .large])
                .presentationBackground(P.surface)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Header(engine: engine, lens: lens, showTips: $showTips)
            Divider().overlay(P.line)

            switch lens {
            case .grid:
                GridLens(engine: engine,
                         selectedTrack: $selectedTrack,
                         selectedBar: $selectedBar)
            case .mix:
                MixLens(engine: engine, selectedTrack: $selectedTrack)
            case .rack:
                RackLens(engine: engine, selectedTrack: $selectedTrack)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rail

    @ViewBuilder
    private func rail(axis: Axis) -> some View {
        let items = AnyView(
            RailItems(engine: engine, lens: $lens, axis: axis,
                      showTips: $showTips, railOnLeading: $railOnLeading)
        )

        Group {
            if axis == .horizontal {
                items
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
            } else {
                items
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
            }
        }
        .background(P.surface.ignoresSafeArea())
        .overlay(alignment: axis == .horizontal ? .top : (railOnLeading ? .trailing : .leading)) {
            Rectangle().fill(P.line)
                .frame(width: axis == .horizontal ? nil : 1,
                       height: axis == .horizontal ? 1 : nil)
        }
    }
}

/// The rail's contents, laid out along whichever axis it was given. Same
/// controls, same order, same sizes — only the stack changes.
private struct RailItems: View {
    @ObservedObject var engine: PalmEngine
    @Binding var lens: Lens
    let axis: Axis
    @Binding var showTips: Bool
    @Binding var railOnLeading: Bool

    var body: some View {
        let stack: AnyLayout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: P.gap))
            : AnyLayout(VStackLayout(spacing: P.gap))

        stack {
            TransportButton(isPlaying: engine.isPlaying) { engine.togglePlay() }

            Pad(isOn: engine.project.metronomeOn, tint: P.teal, minSize: P.touch) {
                engine.project.metronomeOn.toggle()
            } content: {
                Image(systemName: "metronome.fill").font(.system(size: 19, weight: .semibold))
            }
            .frame(width: axis == .horizontal ? P.touch + 8 : nil,
                   height: axis == .horizontal ? nil : P.touch)

            if axis == .horizontal {
                DragValue(title: "Tempo", value: $engine.project.tempo,
                          range: 50...200, format: { "\(Int($0))" })
                    .frame(maxWidth: 130)
            }

            LensPicker(lens: $lens, axis: axis)

            Pad(isOn: showTips, tint: P.amber, minSize: P.touch) {
                showTips = true
            } content: {
                Image(systemName: "lightbulb.fill").font(.system(size: 18, weight: .semibold))
            }
            .frame(width: axis == .horizontal ? P.touch + 8 : nil,
                   height: axis == .horizontal ? nil : P.touch)

            if axis == .vertical {
                Spacer(minLength: 0)
                // Handedness. In landscape the rail should be under the thumb
                // you actually hold the phone with.
                Pad(isOn: false, tint: P.dim, minSize: P.touch) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        railOnLeading.toggle()
                    }
                } content: {
                    Image(systemName: railOnLeading ? "arrow.right.to.line" : "arrow.left.to.line")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(height: P.touch)
            }
        }
        .frame(width: axis == .vertical ? P.touch + 16 : nil)
    }
}

private struct TransportButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.firm()
            action()
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isPlaying ? P.ground : P.ground)
                .frame(width: P.touch + 16, height: P.touch + 8)
                .background(
                    RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                        .fill(isPlaying ? P.rose : P.amber)
                )
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(isPlaying ? "Stop" : "Play")
    }
}

private struct LensPicker: View {
    @Binding var lens: Lens
    let axis: Axis

    var body: some View {
        let stack: AnyLayout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 6))
            : AnyLayout(VStackLayout(spacing: 6))
        stack {
            ForEach(Lens.allCases) { item in
                Button {
                    Haptic.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { lens = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 16, weight: .semibold))
                        if axis == .horizontal {
                            Text(item.rawValue).font(P.label(9))
                        }
                    }
                    .frame(minWidth: P.touch, minHeight: axis == .horizontal ? P.touch + 8 : P.touch)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(lens == item ? P.ground : P.dim)
                    .background(
                        RoundedRectangle(cornerRadius: P.radius - 3, style: .continuous)
                            .fill(lens == item ? P.ink : Color.clear)
                    )
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.rawValue)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.raised))
        .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous).strokeBorder(P.line))
    }
}

private struct Header: View {
    @ObservedObject var engine: PalmEngine
    let lens: Lens
    @Binding var showTips: Bool

    var body: some View {
        let bar = engine.playhead / 4 + 1
        let beat = engine.playhead % 4 + 1

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lens.rawValue.uppercased())
                    .font(P.label(10)).tracking(1.6)
                    .foregroundStyle(P.faint)
                Text("\(bar).\(beat)")
                    .font(P.numeral(19))
                    .foregroundStyle(engine.isPlaying ? P.amber : P.ink)
                    .contentTransition(.numericText())
            }
            .frame(width: 64, alignment: .leading)

            Button {
                showTips = true
            } label: {
                TipChip(tip: Tips.rotating(for: lens.tipLens, seed: engine.playhead / 16))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct TipChip: View {
    let tip: Tip

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(P.amber)
            Text(tip.headline)
                .font(P.label(12))
                .foregroundStyle(P.dim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(P.faint)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(P.raised))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(P.line))
        .contentShape(Rectangle())
    }
}

private struct Toast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(P.label(13))
                .foregroundStyle(P.ground)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Capsule().fill(P.ink))
                .padding(.bottom, 96)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            dismiss()
        }
    }
}

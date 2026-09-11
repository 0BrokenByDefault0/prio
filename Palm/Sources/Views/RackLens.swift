import SwiftUI
import AVFoundation

/// The plugin rack for the selected track: one instrument slot, then effects in
/// signal order. Tapping a loaded plugin opens its own interface full-bleed —
/// one tap in, one tap out, no nested navigation to get lost in.
struct RackLens: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selectedTrack: Int

    @State private var browsing: BrowseTarget?
    @State private var openPlugin: OpenPlugin?

    private struct BrowseTarget: Identifiable {
        let isInstrument: Bool
        var id: Bool { isInstrument }
    }

    private struct OpenPlugin: Identifiable {
        let unit: AVAudioUnit
        let name: String
        var id: ObjectIdentifier { ObjectIdentifier(unit) }
    }

    var body: some View {
        let track = engine.project.tracks[selectedTrack]
        let color = P.trackColor(selectedTrack)

        ScrollView {
            VStack(spacing: P.gap) {
                TrackPicker(engine: engine, selected: $selectedTrack)

                SectionLabel("Instrument")
                if let unit = engine.loadedInstruments[selectedTrack] {
                    SlotRow(title: track.instrument?.name ?? "Instrument",
                            subtitle: "AUv3 · out of process",
                            tint: color,
                            open: { openPlugin = OpenPlugin(unit: unit, name: track.instrument?.name ?? "Plugin") },
                            remove: { Task { await engine.loadInstrument(nil, onTrack: selectedTrack) } })
                } else {
                    BuiltInRow(engine: engine, index: selectedTrack, tint: color)
                    EmptySlot(title: "Load an AUv3 instrument", tint: color) {
                        browsing = BrowseTarget(isInstrument: true)
                    }
                }

                SectionLabel("Effects")
                let units = engine.loadedEffects[selectedTrack] ?? []
                ForEach(units.indices, id: \.self) { i in
                    let name = i < track.effects.count ? track.effects[i].name : "Effect"
                    SlotRow(title: name,
                            subtitle: "Slot \(i + 1) · signal order",
                            tint: P.teal,
                            open: { openPlugin = OpenPlugin(unit: units[i], name: name) },
                            remove: { engine.removeEffect(at: i, onTrack: selectedTrack) })
                }
                EmptySlot(title: "Add an effect", tint: P.teal) {
                    browsing = BrowseTarget(isInstrument: false)
                }

                Text("Palm hosts instruments, audio effects, MIDI processors, generators and panners — every AUv3 type iOS exposes.")
                    .font(P.label(12))
                    .foregroundStyle(P.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .sheet(item: $browsing) { target in
            PluginBrowser(engine: engine,
                          isInstrument: target.isInstrument,
                          trackIndex: selectedTrack)
                .presentationDetents([.medium, .large])
                .presentationBackground(P.surface)
        }
        .fullScreenCover(item: $openPlugin) { plugin in
            PluginWindow(unit: plugin.unit, name: plugin.name) { openPlugin = nil }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text.uppercased()).font(P.label(10)).tracking(1.8).foregroundStyle(P.faint)
            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct TrackPicker: View {
    @ObservedObject var engine: PalmEngine
    @Binding var selected: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(engine.project.tracks.indices, id: \.self) { i in
                    Button {
                        Haptic.select()
                        selected = i
                    } label: {
                        Text(engine.project.tracks[i].name)
                            .font(P.label(13))
                            .padding(.horizontal, 13)
                            .frame(height: P.touch - 4)
                            .foregroundStyle(selected == i ? P.ground : P.dim)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(selected == i ? P.trackColor(i) : P.raised))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(selected == i ? .clear : P.line))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .frame(height: P.touch - 4)
    }
}

private struct SlotRow: View {
    let title: String
    let subtitle: String
    let tint: Color
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptic.firm()
                open()
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.22))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(P.title(15)).foregroundStyle(P.ink).lineLimit(1)
                        Text(subtitle).font(P.label(11)).foregroundStyle(P.faint).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(P.dim)
                }
                .padding(12)
                .frame(minHeight: P.touch + 16)
                .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.surface))
                .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous).strokeBorder(P.line))
            }
            .buttonStyle(PressStyle())

            Button {
                Haptic.tap()
                remove()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: P.touch, height: P.touch + 16)
                    .foregroundStyle(P.rose)
                    .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.surface))
                    .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous).strokeBorder(P.line))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Remove \(title)")
        }
    }
}

private struct EmptySlot: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                Text(title).font(P.label(14))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: P.touch + 4)
            .foregroundStyle(tint)
            .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.surface.opacity(0.6)))
            .overlay(
                RoundedRectangle(cornerRadius: P.radius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(tint.opacity(0.45))
            )
        }
        .buttonStyle(PressStyle())
    }
}

/// The built-in voice, shown whenever no AUv3 instrument is loaded — so a
/// track is never silent and never a dead slot.
private struct BuiltInRow: View {
    @ObservedObject var engine: PalmEngine
    let index: Int
    let tint: Color

    var body: some View {
        let kind = engine.voiceKind(forTrack: index)
        VStack(alignment: .leading, spacing: 8) {
            Text("Built-in · \(kind.label)")
                .font(P.title(15)).foregroundStyle(P.ink)
            HStack(spacing: 6) {
                ForEach(VoiceKind.allCases, id: \.rawValue) { option in
                    Button {
                        Haptic.select()
                        engine.setVoiceKind(option, forTrack: index)
                    } label: {
                        Text(option.label.replacingOccurrences(of: " synth", with: ""))
                            .font(P.label(12))
                            .frame(maxWidth: .infinity)
                            .frame(height: P.touch - 6)
                            .foregroundStyle(kind == option ? P.ground : P.dim)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(kind == option ? tint : P.raised))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(kind == option ? .clear : P.line))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: P.radius, style: .continuous).fill(P.surface))
        .overlay(RoundedRectangle(cornerRadius: P.radius, style: .continuous).strokeBorder(P.line))
    }
}

// MARK: - Browser

private struct PluginBrowser: View {
    @ObservedObject var engine: PalmEngine
    let isInstrument: Bool
    let trackIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var plugins: [AUv3Plugin] {
        let all = isInstrument ? engine.registry.instruments : engine.registry.effects
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.manufacturer.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isInstrument ? "Instruments" : "Effects")
                    .font(P.title(19)).foregroundStyle(P.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(P.label(15))
                    .foregroundStyle(P.amber)
                    .frame(minWidth: P.touch, minHeight: P.touch)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if plugins.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(P.faint)
                    Text(query.isEmpty
                         ? "No AUv3 \(isInstrument ? "instruments" : "effects") installed yet."
                         : "Nothing matches “\(query)”.")
                        .font(P.label(14)).foregroundStyle(P.dim)
                        .multilineTextAlignment(.center)
                    if query.isEmpty {
                        Text("Install any AUv3 app from the App Store and it appears here automatically.")
                            .font(P.label(12)).foregroundStyle(P.faint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(plugins) { plugin in
                    Button {
                        Haptic.firm()
                        Task {
                            if isInstrument {
                                await engine.loadInstrument(plugin, onTrack: trackIndex)
                            } else {
                                await engine.addEffect(plugin, onTrack: trackIndex)
                            }
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.name).font(P.title(15)).foregroundStyle(P.ink)
                            Text(plugin.manufacturer).font(P.label(12)).foregroundStyle(P.faint)
                        }
                        .frame(maxWidth: .infinity, minHeight: P.touch, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(P.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .modifier(SearchBar(query: $query))
            }
        }
        .background(P.surface)
    }
}

/// `searchable` needs a navigation container to render into; wrapping only the
/// list keeps the sheet's own header as the title.
private struct SearchBar: ViewModifier {
    @Binding var query: String
    func body(content: Content) -> some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .searchable(text: $query, prompt: "Search plugins")
        }
    }
}

// MARK: - Plugin window

private struct PluginWindow: View {
    let unit: AVAudioUnit
    let name: String
    let close: () -> Void
    @StateObject private var loader = PluginViewLoader()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(name).font(P.title(17)).foregroundStyle(P.ink).lineLimit(1)
                Spacer()
                Button {
                    Haptic.tap()
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: P.touch, height: P.touch)
                        .foregroundStyle(P.ink)
                        .background(Circle().fill(P.raised))
                }
                .accessibilityLabel("Close plugin")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(P.surface)

            switch loader.state {
            case .loading:
                ProgressView().tint(P.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .custom(let controller):
                AUv3CustomView(controller: controller)
            case .generic:
                GenericParameterList(unit: unit.auAudioUnit)
            }
        }
        .background(P.ground.ignoresSafeArea())
        .onAppear { loader.load(unit.auAudioUnit) }
    }
}

/// iOS ships no generic AU editor, so Palm builds one from the plugin's own
/// parameter tree. A plugin without a custom view is still fully playable.
private struct GenericParameterList: View {
    let unit: AUAudioUnit
    @State private var parameters: [AUParameter] = []
    @State private var values: [AUParameterAddress: Double] = [:]

    var body: some View {
        Group {
            if parameters.isEmpty {
                Text("This plugin exposes no parameters.")
                    .font(P.label(14)).foregroundStyle(P.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: P.gap)],
                              spacing: P.gap) {
                        ForEach(parameters, id: \.address) { parameter in
                            DragValue(
                                title: parameter.displayName,
                                value: Binding(
                                    get: { values[parameter.address] ?? Double(parameter.value) },
                                    set: { newValue in
                                        values[parameter.address] = newValue
                                        parameter.value = AUValue(newValue)
                                    }),
                                range: Double(parameter.minValue)...Double(max(parameter.minValue + 0.0001,
                                                                              parameter.maxValue)),
                                format: { value in
                                    let unitName = parameter.unitName.map { " \($0)" } ?? ""
                                    return String(format: "%.2f", value) + unitName
                                },
                                tint: P.teal)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear {
            let tree = unit.parameterTree?.allParameters ?? []
            parameters = Array(tree.prefix(64))
            for parameter in parameters { values[parameter.address] = Double(parameter.value) }
        }
    }
}

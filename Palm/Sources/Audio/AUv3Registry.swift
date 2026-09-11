import AVFoundation
import CoreAudioKit
import SwiftUI

/// A discovered plugin on this device.
struct AUv3Plugin: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let description: AudioComponentDescription
    let hasCustomView: Bool
    let isInstrument: Bool

    var ref: PluginRef {
        PluginRef(manufacturer: description.componentManufacturer,
                  type: description.componentType,
                  subtype: description.componentSubType,
                  name: name)
    }
}

/// Everything installed on the phone that we can host. Palm hosts every AUv3
/// category iOS exposes — instruments, effects, MIDI-controlled effects and
/// generators — rather than the instruments-plus-reverb subset most hosts stop at.
@MainActor
final class AUv3Registry: ObservableObject {
    @Published private(set) var instruments: [AUv3Plugin] = []
    @Published private(set) var effects: [AUv3Plugin] = []
    @Published private(set) var isScanning = false

    static let instrumentTypes: [OSType] = [
        kAudioUnitType_MusicDevice,
    ]

    static let effectTypes: [OSType] = [
        kAudioUnitType_Effect,
        kAudioUnitType_MusicEffect,
        kAudioUnitType_Generator,
        kAudioUnitType_Mixer,
        kAudioUnitType_Panner,
        kAudioUnitType_MIDIProcessor,
    ]

    func scan() {
        isScanning = true
        let manager = AVAudioUnitComponentManager.shared()

        func collect(_ types: [OSType], instrument: Bool) -> [AUv3Plugin] {
            var seen = Set<String>()
            var result: [AUv3Plugin] = []
            for type in types {
                var desc = AudioComponentDescription()
                desc.componentType = type
                for component in manager.components(matching: desc) {
                    let d = component.audioComponentDescription
                    let key = "\(d.componentType)-\(d.componentSubType)-\(d.componentManufacturer)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    result.append(AUv3Plugin(
                        id: key,
                        name: component.name,
                        manufacturer: component.manufacturerName,
                        description: d,
                        hasCustomView: component.hasCustomView,
                        isInstrument: instrument))
                }
            }
            return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let found = (collect(Self.instrumentTypes, instrument: true),
                     collect(Self.effectTypes, instrument: false))
        instruments = found.0
        effects = found.1
        isScanning = false
    }

    /// Instantiate out of process, which is what keeps a crashing third-party
    /// plugin from taking the whole session down with it.
    static func instantiate(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: [.loadOutOfProcess]) { unit, error in
                if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: error ?? PalmError.instantiationFailed)
                }
            }
        }
    }
}

enum PalmError: Error {
    case instantiationFailed
}

/// Wraps a plugin's own view controller. iOS ships no generic AU editor, so
/// when a plugin has no custom view the caller falls back to Palm's own
/// parameter list rather than showing an empty panel.
struct AUv3CustomView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .clear
        container.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        controller.didMove(toParent: container)
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Asks a plugin for its interface once, and reports what came back.
@MainActor
final class PluginViewLoader: ObservableObject {
    enum State { case loading, custom(UIViewController), generic }
    @Published private(set) var state: State = .loading

    func load(_ audioUnit: AUAudioUnit) {
        guard case .loading = state else { return }
        audioUnit.requestViewController { [weak self] controller in
            Task { @MainActor in
                guard let self else { return }
                if let controller { self.state = .custom(controller) }
                else { self.state = .generic }
            }
        }
    }
}

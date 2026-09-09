import SwiftUI

/// All of the app's text. There are no buttons, no tab bar, no now-playing bar
/// and no list — so this is four labels, and three of them are usually invisible.
struct Chrome: View {
    @ObservedObject var engine: SpellEngine
    @ObservedObject var world: World
    var library: [Track]
    var maxR: CGFloat

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            if let track = world.focused {
                VStack(spacing: 10) {
                    Text(track.title.uppercased())
                        .font(.system(size: 15, weight: .light, design: .default))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.86))

                    Text(inscription(for: track))
                        .font(.system(size: 10, weight: .light))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.34))
                }
                .multilineTextAlignment(.center)
                .opacity(world.bloom)
                .offset(y: (1 - world.bloom) * 18)
            } else {
                Text("TOUCH A SIGIL")
                    .font(.system(size: 10, weight: .light))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.22 + 0.10 * sin(world.drift * 1.1)))
            }

            Spacer().frame(height: 42)
        }
        .padding(.horizontal, 28)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: world.focused?.id)
    }

    /// A track's stats, written the way the app thinks about them.
    private func inscription(for track: Track) -> String {
        let d = track.dna
        let elapsed = world.scrubbing
            ? world.scrubFraction * SpellEngine.trackLength
            : engine.position
        return "\(clock(elapsed))  ·  \(Int(d.bpm)) BPM  ·  \(d.scale.rawValue.uppercased())  ·  \(d.petals) PETALS"
    }

    private func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

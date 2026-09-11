import Foundation

/// Tips are not a help system. They are the thing a good engineer says over
/// your shoulder while you work — short, specific, and about the lens you are
/// currently looking at.
struct Tip: Identifiable, Hashable {
    let id: Int
    let lens: Lens
    let headline: String
    let body: String

    enum Lens: String, CaseIterable {
        case grid = "Grid"
        case mix = "Mix"
        case rack = "Rack"
        case craft = "Craft"
    }
}

enum Tips {
    static let all: [Tip] = [
        // Grid
        Tip(id: 1, lens: .grid, headline: "Leave space on the one",
            body: "Dropping the kick on beat 1 of a bar makes the return on beat 2 hit twice as hard. Silence is a transient."),
        Tip(id: 2, lens: .grid, headline: "Swing the sixteenths, not the eighths",
            body: "Swing above about 15% starts to sound like a shuffle. Between 54% and 58% is where most house and hip-hop grooves actually sit."),
        Tip(id: 3, lens: .grid, headline: "Velocity is the groove",
            body: "A hat pattern with every note at 100 sounds like a machine. Drop the offbeats to 60–70 and the same pattern breathes."),
        Tip(id: 4, lens: .grid, headline: "Two-bar loops lie to you",
            body: "Anything sounds good for two bars. Set the loop to four and listen again before you commit."),
        Tip(id: 5, lens: .grid, headline: "Ghost notes on the snare",
            body: "Add snare hits at velocity 25–40 between the backbeats. You won't hear them consciously — you'll feel the track push."),
        Tip(id: 6, lens: .grid, headline: "Move one note",
            body: "When a loop feels stiff, nudge a single bass note off the grid by one step rather than adding anything new."),
        Tip(id: 7, lens: .grid, headline: "Root, fifth, then leave",
            body: "A bassline that plays the root on the downbeat and the fifth anywhere else will sit under almost any chord you write later."),

        // Mix
        Tip(id: 20, lens: .mix, headline: "Set levels with the faders down",
            body: "Start every track at silence and bring each one up until you can just hear it. You'll end up with far more headroom than mixing downward."),
        Tip(id: 21, lens: .mix, headline: "Pan narrow, not wide",
            body: "Hard-panning thins a track on phone speakers. 25–40% either side gives you width that survives mono."),
        Tip(id: 22, lens: .mix, headline: "Kick and bass share one lane",
            body: "Keep both near the centre. If they fight, move the bass — the kick owns the middle."),
        Tip(id: 23, lens: .mix, headline: "Solo lies, mute tells the truth",
            body: "Judging a sound in solo tells you nothing about whether it belongs. Mute it instead: if you don't miss it, it wasn't doing anything."),
        Tip(id: 24, lens: .mix, headline: "Leave the master at 0.85",
            body: "Headroom on the master is free. If the mix is too quiet, everything else is too loud."),
        Tip(id: 25, lens: .mix, headline: "Check it at a whisper",
            body: "Turn the phone down until you can barely hear it. Whatever still reads clearly is your actual arrangement."),

        // Rack
        Tip(id: 40, lens: .rack, headline: "Effects run top to bottom",
            body: "The order in a track's rack is the order of the signal. EQ before compression shapes what the compressor reacts to; after it shapes the result."),
        Tip(id: 41, lens: .rack, headline: "One reverb, shared",
            body: "Rather than a reverb on every track, put one on a single track and send the parts that need space through it. Fewer plugins, more coherent room."),
        Tip(id: 42, lens: .rack, headline: "Plugins run out of process",
            body: "Palm loads every AUv3 out of process, so a plugin that crashes takes itself down and leaves your session running."),
        Tip(id: 43, lens: .rack, headline: "Save the preset, not the project",
            body: "Plugin state travels inside your Palm project, but export presets from the plugin too. Projects move between apps badly; presets don't."),
        Tip(id: 44, lens: .rack, headline: "Try the MIDI effects",
            body: "AUv3 MIDI processors — arpeggiators, chord generators, humanisers — slot into a rack the same way audio effects do. Most hosts hide them."),

        // Craft
        Tip(id: 60, lens: .craft, headline: "Finish something short",
            body: "A finished 90-second loop teaches you more than a fourth unfinished 4-minute arrangement."),
        Tip(id: 61, lens: .craft, headline: "Write the ending first",
            body: "Knowing where a track lands makes every decision before it easier. Build the last eight bars, then work out how to arrive there."),
        Tip(id: 62, lens: .craft, headline: "Change one thing every eight bars",
            body: "Not a new section — one element. Drop the hats, open a filter, mute the bass for two bars. Attention renews on change, not on addition."),
        Tip(id: 63, lens: .craft, headline: "Tempo is a decision, not a default",
            body: "Try your loop at ±6 BPM before you build on it. A groove that only works at one tempo is usually a groove with a timing problem."),
        Tip(id: 64, lens: .craft, headline: "Record the mistake",
            body: "The take where your finger slipped is worth keeping until you're certain the correct one is better. It usually isn't."),
        Tip(id: 65, lens: .craft, headline: "Sleep on the mix",
            body: "Ears adapt within twenty minutes. Anything you mix past that point you are mixing for a version of yourself that no longer exists."),
    ]

    static func forLens(_ lens: Tip.Lens) -> [Tip] {
        all.filter { $0.lens == lens }
    }

    /// A stable rotation, so the tip on screen changes as you work but never
    /// flickers between two states within a single session.
    static func rotating(for lens: Tip.Lens, seed: Int) -> Tip {
        let pool = forLens(lens)
        guard !pool.isEmpty else { return all[0] }
        return pool[abs(seed) % pool.count]
    }
}

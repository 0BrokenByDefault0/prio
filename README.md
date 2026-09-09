# Sigil

A music player with no library, no list, no album art, and no buttons.

Every track is a seed. The seed grows a **sigil** — a living glyph — and the same
seed grows the music, note for note, as a pure function of the beat index.
Nothing here was recorded. Seeking is exact and instant because bar 97 isn't
stored anywhere; it is recomputed.

You turn the field to browse. You touch a glyph to summon it: it doesn't open a
screen, it travels to the centre and unfolds into a mandala. Its outer ring is
the scrubber. Its core is play/pause. Pull down and it folds back into the field.

There are no cuts anywhere in the app. Every state is a number travelling toward
another number, and every track change is a 2.6-second equal-power dissolve —
including the colour of the room, which is lit by whatever is currently burning.

## The idea, concretely

| Most players | Sigil |
| --- | --- |
| A list of rows | A field of orbiting glyphs |
| Album art | A glyph drawn from the track's own genome |
| A scrub bar | The mandala's outer ring |
| A play button | The mandala's core |
| "Back" | Pull the mandala down until it folds away |
| A queue screen | One thread of light to the next sigil |
| Audio files | A synth that is a pure function of the beat index |

## Layout

```
Sigil/Sources/App/Sigil.swift        seeds, scales, the genome, the grimoire
Sigil/Sources/App/SigilApp.swift     @main
Sigil/Sources/Audio/Synth.swift      the voice: pad, sub, plucks, per-sample render
Sigil/Sources/Audio/SpellEngine.swift AVAudioEngine graph + the crossfade
Sigil/Sources/Views/SigilRenderer.swift one routine draws both the glyph and the mandala
Sigil/Sources/Views/RootView.swift   the single scene, layout, and every gesture
Sigil/Sources/Views/Veil.swift       three enormous soft lights behind everything
Sigil/Sources/Views/World.swift      continuous state, stepped once per frame
web/index.html                       the whole app again, in one file, for a browser
scripts/build_ipa.sh                 unsigned .ipa
```

The Swift app and the web build are the same design implemented twice — same
genome, same scales, same layout maths, same gestures. The Swift synth renders
per sample through `AVAudioSourceNode`; the web synth schedules native WebAudio
nodes with a 180 ms lookahead. They sound like siblings, not clones.

## Running the web build

Open `web/index.html` in any modern browser. Audio starts on your first touch
(browsers require a gesture). Space toggles playback, arrows scrub, Escape
releases.

## Building the unsigned IPA

This requires **macOS with Xcode 15+** (iOS 17 SDK) and `xcodegen`:

```sh
brew install xcodegen
./scripts/build_ipa.sh
# → build/Sigil-unsigned.ipa
```

The script archives with `CODE_SIGNING_ALLOWED=NO` and assembles `Payload/` into
a zip by hand, because `xcodebuild -exportArchive` refuses an unsigned archive.

An unsigned `.ipa` will **not** install on a stock iPhone. Install it with a tool
that applies your own certificate — Sideloadly, AltStore, or `ideviceinstaller`
after re-signing — or on a jailbroken device.

> The IPA was not built in this repo's CI environment: it is x86-64 Linux with no
> Swift toolchain, no Xcode and no iOS SDK, and a real `.ipa` needs a compiled
> ARM64 Mach-O binary. The sources and the build script are complete; the binary
> has to be produced on a Mac.

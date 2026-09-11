# prio

Two iOS music apps, built from scratch.

- **[Palm](#palm)** — a DAW that works the same in every orientation.
- **[Sigil](#sigil)** — a player with no list, no album art, and no buttons.

---

## Palm

An iPhone DAW whose whole argument is that you can *use* it. Other iOS DAWs
put controls behind menus, shrink targets below what a thumb can hit, and
build two different apps for portrait and landscape. Palm has one layout,
described once, that reflows by axis.

### What makes it different

| Most iOS DAWs | Palm |
| --- | --- |
| Landscape-only, or a cut-down portrait mode | One layout, reflowed by axis — nothing appears or vanishes on rotation |
| Controls behind nested menus and modals | One rail, always on screen, holding every global control |
| Fixed control position | Rail moves to the thumb's edge; one tap flips it for handedness |
| Faders a few points wide | Nothing touchable is under 48pt — drag anywhere on a control, not on a track |
| Separate "edit velocity" mode | Tap toggles a step, drag up and down sets its velocity — no mode to enter or escape |
| Instruments plus a few effect types | Every AUv3 type iOS exposes |
| Blank slot until you buy a plugin | Built-in drum and tone voices on every track from first launch |

**Portrait** gives you one track as a 4×4 pad matrix — pads big enough to play
one-handed. **Landscape** gives you all eight tracks against all sixteen steps.
Same data, same gestures, same selection; only the density changes, so rotating
never costs you your place.

### AUv3 hosting

- Instruments, audio effects, MIDI processors, generators, mixers and panners
  — every type `AVAudioUnitComponentManager` will report.
- Every plugin instantiated with `.loadOutOfProcess`, so a third-party crash
  takes itself down and leaves your session running.
- Plugin UI opens full-bleed: one tap in, one tap out.
- iOS ships no generic AU editor, so Palm builds one from the plugin's own
  `parameterTree`. A plugin with no custom view is still fully playable.
- Loaded plugins are saved with the project and reopened on launch; a plugin
  you've uninstalled costs you that slot, not the session.

### Timing

The sequencer does not run on the main actor. It runs on its own queue against
a lock-guarded snapshot of the pattern, stamping events in render-clock samples
with a 120 ms lookahead. Built-in voices are drained per frame inside the render
block, so notes land on the right *frame*, not merely in the right buffer.
Scrolling the grid, opening a plugin window or rotating the phone cannot move
the beat.

### Music tips

Twenty-five of them, scoped to the lens you're looking at — grid, mix, rack, and
craft. The tip on the header is always about what's in front of you, and tapping
it opens the rest.

### Layout

```
Palm/Sources/Model/Project.swift        project, tracks, steps, persistence
Palm/Sources/Model/Tips.swift           the tips
Palm/Sources/Audio/PalmEngine.swift     graph, transport, plugin slots
Palm/Sources/Audio/TrackChain.swift     one track's signal path + render clock
Palm/Sources/Audio/BuiltInInstrument.swift  the fallback drum and tone voices
Palm/Sources/Audio/AUv3Registry.swift   discovery, instantiation, plugin views
Palm/Sources/Audio/Pattern.swift        the sequencer's lock-guarded snapshot
Palm/Sources/Audio/EventQueue.swift     sequencer → render thread
Palm/Sources/Views/Design.swift         tokens, the 48pt floor, shared controls
Palm/Sources/Views/RootView.swift       the shell and the rail
Palm/Sources/Views/GridLens.swift       sequencer, both densities
Palm/Sources/Views/MixLens.swift        mixer
Palm/Sources/Views/RackLens.swift       plugin rack, browser, plugin window
Palm/Sources/Views/TipsView.swift       tips sheet
```

### Getting the unsigned IPA

**Without a Mac** — GitHub Actions builds it. Open the repo's **Actions** tab,
pick the latest **Palm unsigned IPA** run on this branch, and download the
`Palm-unsigned-ipa` artifact. You can also trigger a build by hand from that
tab (Run workflow).

**With a Mac:**

```sh
brew install xcodegen
./scripts/build_palm_ipa.sh      # → build/Palm-unsigned.ipa
```

Either way the archive is built with `CODE_SIGNING_ALLOWED=NO`, and `Payload/`
is assembled into a zip by hand because `xcodebuild -exportArchive` refuses an
unsigned archive.

An unsigned `.ipa` will **not** install on a stock iPhone. Install it with a
tool that applies your own certificate — Sideloadly, AltStore, or
`ideviceinstaller` after re-signing — or on a jailbroken device.

---

## Sigil

A music player with no library, no list, no album art, and no buttons.

Every track is a seed. The seed grows a **sigil** — a living glyph — and the
same seed grows the music, note for note, as a pure function of the beat index.
Nothing was recorded. Seeking is exact and instant because bar 97 isn't stored
anywhere; it is recomputed.

You turn the field to browse. Touch a glyph to summon it: it doesn't open a
screen, it travels to the centre and unfolds into a mandala. Its outer ring is
the scrubber. Its core is play/pause. Pull down and it folds back into the
field. Every state is a number travelling toward another number, and every
track change is a 2.6-second equal-power dissolve — including the colour of the
room.

```
Sigil/Sources/App/Sigil.swift           seeds, scales, the genome, the grimoire
Sigil/Sources/Audio/Synth.swift         pad, sub, plucks, per-sample render
Sigil/Sources/Audio/SpellEngine.swift   AVAudioEngine graph + the crossfade
Sigil/Sources/Views/SigilRenderer.swift one routine draws glyph and mandala
Sigil/Sources/Views/RootView.swift      the single scene and every gesture
web/index.html                          the whole app again, in one file
scripts/build_ipa.sh                    unsigned .ipa (macOS)
```

The web build runs in any modern browser — open `web/index.html`. Audio starts
on your first touch. Space toggles playback, arrows scrub, Escape releases.

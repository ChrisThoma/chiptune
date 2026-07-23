# Chiptune

A small iOS step sequencer for writing chiptune songs. Four channels to start
with, NES-style: two pulses, a triangle and a noise channel, all synthesised
from scratch — no samples, no audio files.

Notes live in *patterns*; the *arrangement* chains patterns into a song, so a
piece can have an intro, a verse and a chorus rather than being one loop.

## Build and run

The Xcode project is generated, so it isn't checked in:

```sh
brew install xcodegen        # once
xcodegen generate
open Chiptune.xcodeproj
```

Or straight to a simulator:

```sh
xcodegen generate
xcodebuild -project Chiptune.xcodeproj -scheme Chiptune \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Chiptune.app
xcrun simctl launch booted me.christhoma.chiptune
```

## Using it

- Pick a note on the keyboard at the bottom, then tap a grid cell to place it.
  Tapping a filled cell clears it.
- The column headers select a channel, mute it, and open its sound settings
  (volume, decay, pulse width, arpeggio).
- `OFF` writes a note-off, which cuts a sustaining note — mainly useful on the
  triangle channel, which holds by default.
- Tap the BPM readout to type a tempo, or use −/+ to nudge it.
- The lettered chips under the transport are the patterns. Tap to edit one, `+`
  to add, long-press to rename, duplicate, clear or delete. `STEPS` sets the
  length of the pattern on screen (4–64), and patterns can differ in length.
- `PATT` loops the pattern you're editing. `SONG` plays the arrangement.
- The list button opens the arrangement: a play order of sections, each naming a
  pattern and a repeat count, reorderable and deletable.
- Songs save themselves as you edit, and the app reopens the last one. The
  music-note button in the title bar is the library.
- The ••• menu makes a new song, duplicates one, and exports a WAV. Exporting
  renders the whole arrangement.

## How it works

`Sources/Audio/ChipCore.swift` is the whole synth: oscillators, envelopes and
the step sequencer. It runs inside an `AVAudioSourceNode` render callback, so it
never allocates, locks, or copies during playback — every pattern, the flattened
play order, and the per-channel parameters live in manually allocated buffers
that the main thread writes into field by field. Following the arrangement costs
the audio thread one array lookup at each pattern boundary and never a trip back
to the main thread.

- **Pulse 1 / 2** — variable duty (12/25/50/75%)
- **Triangle** — quantised to 16 steps per half cycle, like the NES channel
- **Noise** — 15-bit LFSR clocked at a multiple of the note frequency, so it's
  pitched rather than flat hiss

The master chain is a gentle lowpass, a ~10 Hz DC blocker (narrow pulse duties
are strongly asymmetric and would otherwise eat headroom and click), and a
`tanh` soft clip.

Retriggering a voice that is still ringing does not restart it on the spot: the
envelope is ramped down over ~2.5 ms first, then the new note ramps up over
~1.2 ms. Snapping the level back to 1.0 and the phase back to 0 while the
previous note is still near full amplitude is a step discontinuity, which is
what a run of the same note used to sound like.

`WavExport` reuses the same core to render offline, so an exported file is
sample-identical to what you hear.

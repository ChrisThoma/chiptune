# Chiptune

A small iOS step sequencer for writing chiptune loops. Four channels, NES-style:
two pulses, a triangle and a noise channel, all synthesised from scratch — no
samples, no audio files.

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
- BPM and pattern length (4–64 steps) are in the transport bar.
- The ••• menu saves, opens, and exports the loop as a WAV.

## How it works

`Sources/Audio/ChipCore.swift` is the whole synth: oscillators, envelopes and
the step sequencer. It runs inside an `AVAudioSourceNode` render callback, so it
never allocates, locks, or copies during playback — the pattern and per-channel
parameters live in manually allocated buffers that the main thread writes into
field by field.

- **Pulse 1 / 2** — variable duty (12/25/50/75%)
- **Triangle** — quantised to 16 steps per half cycle, like the NES channel
- **Noise** — 15-bit LFSR clocked at a multiple of the note frequency, so it's
  pitched rather than flat hiss

The master chain is a gentle lowpass, a ~10 Hz DC blocker (narrow pulse duties
are strongly asymmetric and would otherwise eat headroom and click), and a
`tanh` soft clip.

`WavExport` reuses the same core to render offline, so an exported file is
sample-identical to what you hear.

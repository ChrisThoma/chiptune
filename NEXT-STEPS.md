# Next steps

Written at the end of the verification-and-launch-polish branch (168 tests,
~8 s). This is the engineering follow-on: what that branch left unproven, what
it deliberately didn't cover, and what was cut.

Submission *mechanics* — developer account, App Store Connect fields, upload —
are not here. They're in `AppStore/CHECKLIST.md`, which is local-only and
untracked. This file is about the code.

---

## 1. Before the branch merges

### CI has never actually run

The workflow is written but no push has exercised it. Two things it will prove
or disprove on the first run:

- **The Xcode pin.** `.github/workflows/ci.yml` pins `Xcode_16.4.app` on
  `macos-15`. That was chosen for a runner image, not verified against one. The
  Select Xcode step fails loudly and lists what's installed if the pin is
  wrong, so a bad pin is a one-line fix rather than a mystery.
- **Local and CI are on different toolchains.** This machine is on Xcode 26.5;
  CI is pinned to 16.4. Everything green here was green under 26.5 only.

Push the branch and read the first run before merging.

### The golden fixture is the most likely CI failure

`Tests/Fixtures/golden-demo.wav` was rendered on this machine, on an arm64
simulator, under Xcode 26.5, and `testGoldenRenderIsUnchanged` compares against
it within ±2 LSB. A different toolchain can emit different floating-point code
— FMA contraction, vectorisation, a different `libm` `tanh`.

The arithmetic says this should hold comfortably: accumulated error is around
1e-11 against an LSB of 3e-5, three orders of magnitude of headroom even after
the DC blocker's feedback. But it is the one assertion in the suite that is
sensitive to the compiler rather than to the code, so if CI fails on exactly
this test and nothing else, that's why — not a regression.

If it does fail, in order of preference:

1. Pin the same Xcode locally and regenerate, so both sides agree.
2. Widen the tolerance, and write down the measured drift in the commit.
3. Make CI regenerate rather than compare, keeping only the structural
   assertions as a gate. This is the weakest option — it converts a change
   detector into nothing — so take it only if 1 and 2 are impractical.

The structural tests next to it (exact duration from the tempo, per-quarter
level bounds) are not compiler-sensitive and stay meaningful either way.

### Screenshots are now stale

The title bar gained undo and redo buttons, so every App Store screenshot
showing it is out of date — at minimum `1-grid`, and any other set framing the
top of the main screen. Recapture with `AppStore/shoot.sh` before submitting.

---

## 2. What has no automated coverage, on purpose

The XCUITest target was cut: largest surface, least trust, slowest. What that
leaves untested, and the manual pass that replaces it.

**Simulator, once per release:**

- Launch past the splash; PLAY and STOP.
- Library: open, duplicate, rename, delete-with-confirm.
- Undo and redo buttons enable and disable as expected; undo after a pattern
  delete puts the cursor back.
- Export sheet: repeat count, both endings, progress advances, cancel works and
  raises no error.
- Share sheet appears with the WAV.

**Real device only** — none of these can be staged in the simulator:

- A real phone call arriving mid-playback (interruption), and playback *not*
  resuming by itself afterwards.
- Headphones unplugged mid-playback.
- Background and foreground during playback.
- A `.chipsong` opened from Files and from Mail — this exercises `onOpenURL`,
  the exported UTI and the document-type declaration, none of which a unit test
  can reach. **This is the least-proven thing in the branch:** the plist
  declarations are written but have never been exercised by the system.
- Audio timing and render performance under a real CPU governor.

---

## 3. Loose ends in the code

Small, none blocking. Roughly in order of how likely they are to matter.

- **Renaming the song from the title bar isn't undoable.** The `TextField`
  binds `studio.song.name` directly with no checkpoint, so typing over a name
  can't be undone. Every other edit can. Either checkpoint it (coalesced, or
  it's one undo step per keystroke) or decide that's fine and note why.
- **`Studio.importError` also carries share failures.** One string, two
  meanings, because share can only fail by failing to write a temp file. If a
  third use appears, split it.
- **`assertSameSong` / "equal ignoring `modified`" is copy-pasted** across four
  test files. Hoist it into `Tests/Support/`.
- **The undo stack holds up to 50 `Song` snapshots.** Copy-on-write makes each
  one cheap when little changed, but a full-size song is ~64 KB of note data,
  so a session of structural edits could hold a few MB. Measure before tuning
  `undoLimit`; don't guess.
- **The Thread Sanitizer job reports every run.** That's expected —
  `ChipCore` is lock-free by contract and TSan can't know the argument. The
  surprising signal would be it going *quiet*, or reporting somewhere outside
  ChipCore's word-sized parameter fields.

---

## 4. Deferred post-launch

Cut deliberately, with reasons, not forgotten.

- **Stereo / pan export.** Touches `ChipCore.render`'s signature,
  `AudioEngine.fill`, the WAV writer and the schema, and invalidates the golden
  fixture. The tempting "pan 0 behaves like the old mono" equivalence does not
  hold under equal-power panning, so there's no cheap version of this.
- **XCUITest automation.** See §2.
- **MIDI export.** An SMF format-1 writer, one MIDI track per chip track, noise
  to channel 10. A pure function with byte-level tests — self-contained and
  pleasant, just not a launch blocker.
- **Background-audio mode.** `stopEngineIfIdle()` currently stops the engine on
  backgrounding. Declaring `UIBackgroundModes: audio` is a product decision
  (playback continuing with the screen off) rather than a bug fix.
- **iPad layout.** `AppStore/REVIEW-NOTES.md` rates this the single most likely
  cause of rejection: the build is iPhone-only and portrait-locked, and iPadOS
  windows everything. Decide before submitting — handle the sizes, or ship
  iPhone-only deliberately.

---

## 5. If you're adding a feature next

The proof loop the last branch established: **every feature lands with its
tests in the same change.** The machinery that makes that cheap —

- `RenderHarness` renders `ChipCore` offline and measures it (RMS, peak, duty
  ratio, onsets, Goertzel pitch, spectral peakiness, level steps). No audio
  hardware, no timing, no flake. Any claim about how something *sounds* is
  assertable.
- `TempStore` gives a `Studio` a throwaway directory and defaults suite. Use it
  for anything that constructs a `Studio`; the default store writes real
  Documents and makes tests order-dependent.
- `Studio` takes injectable `store`, `renderer` and autosave settings, and
  exposes `engine` so a test can assert the DSP core agrees with the model.
  That last one catches the bug class where an edit lands in `song` and is
  silently inaudible — assert it after any new mutating operation.
- `SongPropertyTests` generates hostile songs from a fixed seed. Anything new
  that reads a file, or that the synth consumes, belongs in its invariants.

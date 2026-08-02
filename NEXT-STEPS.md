# Next steps

Written at the end of the verification-and-launch-polish branch, and updated as
that work was closed out. This is the engineering follow-on: what was left
unproven, what is deliberately uncovered, and what was cut.

Submission *mechanics* — developer account, App Store Connect fields, upload —
are not here. They're in `AppStore/CHECKLIST.md`, which is local-only and
untracked. This file is about the code.

---

## 1. What the first CI run proved

The branch is merged and the workflow has run (PR #1, 2 August 2026). Both of
the things it existed to settle came out green.

- **The Xcode pin holds.** `Xcode_16.4.app` (build 16F6) is installed on
  `macos-15` and the simulator discovery picked a device without help — though
  what it picked was an iOS 26.2 runtime next to an 18.5 SDK, a pairing Apple
  never shipped. The resolver now caps discovery at the pinned toolchain's
  SDK version.
- **The golden fixture survives a toolchain change.** This was the expected
  failure: `Tests/Fixtures/golden-demo.wav` was rendered here under Xcode 26.5
  and `testGoldenRenderIsUnchanged` compares within ±2 LSB, which is an
  assertion about the compiler as much as about the code. It passed unchanged
  under 16.4. The headroom argument turned out to be right — accumulated error
  around 1e-11 against an LSB of 3e-5 — so the fixture is a genuine
  cross-toolchain change detector, not a local one.

If it ever *does* drift, the order that actually works is: measure the drift
from the failure output, widen the tolerance by the measured amount and write
that number down, and only then consider a per-toolchain fixture. Regenerating
locally under the other toolchain does not work — you are there precisely
because the two disagree by more than the tolerance, so a fixture that suits
one makes the other fail by the same margin.

Regenerating at all has two traps worth knowing before you try it. The
`CHIPTUNE_REGEN_GOLDEN` flag lives on the *shared* scheme (`project.yml`) and
cannot be passed on the `xcodebuild` command line, because a test bundle hosted
in the app takes its environment from the scheme. Turn it on, regenerate, then
turn it off *and check that it is off* — left on, every local run silently
rewrites the fixture and the test becomes a no-op that can never fail. And
`testGoldenRenderIsUnchanged` sorts before `testRegenerateGolden`, so the
regenerating run itself goes red against the stale copy; the run after it is
the real one.

### What the Thread Sanitizer job actually reports

An earlier revision of this section read the first run's failure as TSan
aborting on its first race report. The log says otherwise: the host crashed
with SIGABRT *before starting test execution*, with no sanitizer report at
all. **On CI the TSan tests had never run.** The first theory — the resolver
pairing pinned Xcode 16.4 with a much newer iOS 26.2 runtime — did not
survive testing: the crash reproduced on the matched iOS 18.5 runtime. The
result bundle (which the job now uploads, precisely because a launch crash
leaves nothing in the console) had the real cause in the host's stderr:
`Initialize: RPC timeout. Apparently deadlocked. Aborting now.` The app host
was booting its own `Studio`, whose `AudioEngine` build goes through CoreAudio
initialisation; under TSan's slowdown that init blows CoreAudio's internal
RPC timeout and CoreAudio aborts the process — while the test bundle is still
bootstrapping. The fix is `ChiptuneApp.isTestHost`: the app no longer builds
its `Studio` when hosting tests, which also stops it writing real Documents
underneath every hosted test run. The SDK-version cap on simulator discovery
was kept anyway — testing on an OS the pinned toolchain never shipped against
proves less — but it was not the fix.

The races themselves — observed *locally* (Xcode 26.5, matching runtime) — are
inside `ChipCore`'s word-sized parameter fields, which is exactly the
contract: a size-8 write to `tempo` in `load(song:)` against a size-8 read in
`samplesPerStep()`, and a size-4 write to a transport `Int32` in `start()`
against the matching read in `render`. The function names in the stacks are
where the *assignment* lives, not evidence of anything bulkier; the address in
both reports is inside the 160-byte `ChipCore` instance, not the pattern
array. Nothing is reported outside the contract.

With the host surviving launch, the job ran end to end for the first time
(run of 2 August 2026, after the `isTestHost` fix): both tests executed, each
surfaced its documented race, and CI *does* relaunch the host between tests —
"Restarting after unexpected exit" — with the final relaunch finding zero
tests left. So the job is now the record its comment claims, with one
structural limit: TSan still aborts the host on the first report within a
test, so each test surfaces at most one race. That is fine while each test
exercises one contract; keep it that way when adding to the suite. The red
cross on the job is the designed outcome. A *green* TSan job now means TSan
reported nothing — which, while the lock-free contract stands, is itself
surprising and worth a look at whether the tests really ran.

### Screenshots are stale, and the shoot script doesn't run

The title bar gained undo and redo buttons, so every App Store screenshot
framing the top of the main screen is out of date — at minimum `1-grid`.

`AppStore/shoot.sh` cannot be re-run as-is. It resolves its output directory
and its `make_song.py` seeder through a scratchpad path that no longer exists,
its usage comment claims three arguments where the code reads two, and — the
part that would have been silent — the launch arguments it passes for shots 2
through 4 (`-shotArrangement`, `-shotEditor`, `-shotLibrary`) have never had a
handler in `Sources/`. Every shot would have come out as the grid, which is
precisely the "minimum functionality" impression `AppStore/REVIEW-NOTES.md`
warns about. The script needs repairing before the recapture, not after.

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

### Closed

- **Renaming is undoable now**, from the title bar and from the library both.
  Worth knowing why it looks the way it does, because the two obvious
  implementations are both wrong. Checkpointing per keystroke under the
  existing time coalescing splits a slow rename in two, since the window is
  wall-clock and typing a name has no rhythm to stay inside. Holding the text
  in view state and committing on blur is worse: undo restores a snapshot of
  the *same* song, so there is no id change for the view to resynchronise on —
  the field keeps showing the name that was just undone, then commits it back
  on the next blur and clears the redo stack doing it. So `checkpoint(run:)`
  coalesces by named run instead of by clock, and the field writes straight
  through to the model. Trimming happens when editing ends; trimming per
  keystroke makes a space untypeable.
- **`shareError` is separate from `importError`.** A share that couldn't write
  its temp file used to alert under the title "Import failed".
- **`assertSameSong` is in `Tests/Support/`.** It was in three suites, not
  four, and they had drifted — one copy had lost its `message` parameter.
- **The Thread Sanitizer job runs its tests now.** It never had: the app host
  booted its own `Studio` under tests, and CoreAudio init under TSan's
  slowdown aborted the host before any test started. See §1 for the full
  story and the one limit that remains (one report per test).

### Still open

- **The undo stack holds up to 50 `Song` snapshots.** Copy-on-write makes each
  one cheap when little changed, but a full-size song is ~64 KB of note data,
  so a session of structural edits could hold a few MB. Measure before tuning
  `undoLimit`; don't guess. Measure it under Instruments rather than as an
  assertion — a retained-bytes test would be a second compiler-sensitive
  assertion in a suite that deliberately has one.

---

## 4. Deferred post-launch

Cut deliberately, with reasons, not forgotten. Ordered by what to pick up
first, which is roughly the inverse of blast radius.

- **MIDI export.** An SMF format-1 writer, one MIDI track per chip track, noise
  to channel 10. A pure function with byte-level tests — self-contained and
  pleasant, and the obvious next feature.
- **iPad layout.** No longer a decision — `TARGETED_DEVICE_FAMILY` is `"1"` and
  1.0 ships iPhone-only, on the evidence in `AppStore/screenshots/ipad-13/`: a
  16-step pattern fills the grid and leaves a dead band under it. A native
  layout is a 1.1 feature.
- **Background-audio mode.** `stopEngineIfIdle()` currently stops the engine on
  backgrounding. Declaring `UIBackgroundModes: audio` is a product decision
  (playback continuing with the screen off) rather than a bug fix.
- **XCUITest automation.** See §2.
- **Stereo / pan export.** Last, because it touches the most: `ChipCore.render`'s
  signature, `AudioEngine.fill`, the WAV writer and the schema, and it
  invalidates the golden fixture. The tempting "pan 0 behaves like the old mono"
  equivalence does not hold under equal-power panning, so there is no cheap
  version of this.

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

# Chiptune APPMAP

Bundle ID: `dev.individuation.chiptune`
Scheme: `Chiptune` | Project: `Chiptune.xcodeproj` | Deployment target: iOS 17.0
Target: iPhone (SE-class and large). iPad behavior is out of scope for this hunt. This is a fresh hunt for the iPhone target: all journey and condition coverage starts reset. iPad-only facts from a prior hunt are retained below only where they describe app behavior relevant to iPhone (shared model/state/limits); iPad-specific layout/coverage rows are removed or superseded.

Chiptune is an offline NES-style step sequencer. Its model is Song -> Patterns -> Tracks -> Steps, with a separate arrangement controlling full-song playback.

## Simulators

Reuse these; never duplicate them.

| Slot | Name | UDID | Runtime/device |
|---|---|---|---|
| SIM-A | BugHunt-Chiptune-iPhone-A | `660775D2-6CB5-4147-BCE2-515915732284` | iOS 17.5, iPhone SE (3rd generation) |
| SIM-B | BugHunt-Chiptune-iPhone-B | `7363CA73-CAE8-4581-9A85-AD144C05745D` | iOS 26.5, iPhone 16 Pro Max |

iPad simulators from a prior hunt (`BugHunt-Chiptune-iPad-A` / `-B`) remain registered but are out of scope for this target; do not drive them.

Current source HEAD: `a30e5e4`. Built and installed on both iPhone simulators for this hunt.

Repository notes report an iOS 26 Simulator dimming artifact on 13-inch iPad sheets; not applicable to this iPhone target.

## Build, Install, Launch, Reset

Run from the repository root. `project.yml` is authoritative; generate the project but never edit or commit generated project changes.

```sh
xcodegen generate
xcodebuild -project Chiptune.xcodeproj -scheme Chiptune -configuration Debug -destination "id=<UDID>" -derivedDataPath build/BugHunt CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <UDID> build/BugHunt/Build/Products/Debug-iphonesimulator/Chiptune.app
xcrun simctl launch <UDID> dev.individuation.chiptune
```

There is no in-app reset. Songs and current-song state persist in the app container. For a clean state:

```sh
xcrun simctl terminate <UDID> dev.individuation.chiptune
xcrun simctl uninstall <UDID> dev.individuation.chiptune
xcrun simctl install <UDID> build/BugHunt/Build/Products/Debug-iphonesimulator/Chiptune.app
```

Screenshot/test entry arguments require the `YES` value and are alternatives:

- `-shotArrangement YES`
- `-shotEditor YES`
- `-shotLibrary YES`
- `-shotExport YES`

If several are supplied, enum order wins: arrangement, instrument, library, export. The wide-landscape-iPad inert case for `-shotEditor YES` does not apply on iPhone.

To seed a deterministic five-song library, install without launching, resolve the data container, then run:

```sh
CONTAINER="$(xcrun simctl get_app_container <UDID> dev.individuation.chiptune data)"
mkdir -p "$CONTAINER/Documents/Songs"
python3 AppStore/make_song.py "$CONTAINER/Documents/Songs"
```

The seeded library includes Neon Ascent, Coin Rush, Slow Cartridge, Boss Door, and Overworld Sketch. An ordinary empty-store launch instead creates the populated starter song `First Loop` at 132 BPM.

## Navigation And Surfaces

- `ChiptuneApp` shows `SplashView`, builds `Studio`, restores the last song or seeds `First Loop`, then fades to `ContentView`.
- `ContentView` is the single editor root. It has no tab bar or root navigation stack.
- Title bar: Songs, editable song title, Undo, Redo, and song menu.
- Transport: Play/Stop, PATT/SONG mode, Arrangement, and BPM controls.
- Pattern bar: select, add, rename, duplicate, clear, delete, and change step count.
- Grid: tracks as columns and steps as rows; cells place/replace/clear/preview notes; track headers select, mute, edit, duplicate, clear, or delete tracks.
- Keyboard: octave, selected note/track, OFF, and one-octave piano controls.
- Modal/system surfaces: SongListView, ArrangementView, InstrumentEditor, ExportSheet, WAV ShareSheet, song-file ShareSheet, file importer, alerts, confirmation dialogs, support Link, and StoreKit review request.
- InstrumentEditor is always a sheet on iPhone (compact layout); the popover (regular portrait iPad) and docked (wide landscape iPad) variants do not apply to this target.
- The app accepts `.chipsong` files through document activation and `onOpenURL`; it has no custom URL scheme or universal-link route.

## State, Data, And Limits

- `Studio` is the app-wide observable state owner for the song, selections, playback, autosave, undo/redo, import/share/export, and user-visible errors.
- Songs persist as `Documents/Songs/<UUID>.json`; current song and review counters use UserDefaults. There is no account, database, cloud sync, analytics, ad SDK, or first-party network transport.
- Autosave is the only save model: it runs 1.5 seconds after edits and immediately when the app becomes inactive or opens the library.
- Limits: 1-8 tracks, 1-16 patterns, 4-64 steps, 40-300 BPM, 1-16 section repeats, and 128 flattened arrangement play-throughs.
- Note values are MIDI 0-127; `-1` is empty and `-2` is note-off.
- Arrangement entries past 128 play-throughs remain editable but intentionally do not play or export; the UI must warn about this cap.
- Imported documents are normalized, copied into the local library, and edited there. The original is never edited in place.
- iPhone is portrait-only. iPad supports all orientations and resolves layout from actual window size; narrow Split View can receive phone metrics.
- Multi-window, background audio, MIDI, sample/audio import, stereo/pan, collaboration, and cloud library are unsupported.
- The app forces dark appearance with `.preferredColorScheme(.dark)`.

## Journeys

J1 | hear and restore the starter song | clean launch -> Splash -> editor -> Play | empty app container or existing saved song | starter audio plays; stop/mode state is truthful; relaunch restores the last song
states/branches: first launch; existing library; PATT/SONG; play/stop; audio-start failure; background while idle/playing; output loss/interruption
coverage: discovered | tested: none this hunt | next: clean launch, immediate playback, stop, and relaunch restoration

J2 | compose and revise notes by touch | editor keyboard + step grid | selected pattern/track/note | taps place, replace, clear, preview, and note-off correctly; audio model follows edits; undo/redo restores intent
states/branches: empty/occupied cell; same/different note; long-press preview; OFF; octave; muted track; sustained note; rapid painting; undo/redo
coverage: discovered | tested: none this hunt | next: build a recognizable loop, revise it, and undo/redo distinct edits

J3 | compose with a hardware keyboard | editor with hardware keyboard connected | Simulator I/O -> Keyboard -> Connect Hardware Keyboard | mapped keys move the cursor, enter/clear notes, control octave/OFF, and play/stop without stealing text-field input
states/branches: first key reveals cursor; arrow edge; step wrap; pattern shrink; track deletion; rename focus handoff; unsupported/modifier keys
coverage: iPhone pass 1 | tested: first-key-reveals-cursor, pattern-length wrap-on-type, title-field decoupling during editing — correct; found hardware-key capture is lost PERMANENTLY after any title-field edit, not recovering on any subsequent UI interaction, only on relaunch — filed. Arrow-key edge/step behavior not testable with current tooling (ui_type cannot send non-printable HID keys) | next: track-deletion cursor recovery, unsupported/modifier-key no-op check, an arrow-key injection method

J4 | create and manage pattern variations | Pattern bar | song below 16-pattern limit | add/duplicate/rename/clear/delete/resize produces the intended pattern and coherent arrangement references
states/branches: add; duplicate; unique/blank/long rename; 4/64-step bounds; clear cancel/confirm; delete cancel/confirm; final-pattern guard; undo
coverage: discovered | tested: prior-hunt pass (pre-fix #2/#2-retry) found add, duplicate, rename, 4/64-step bounds, delete confirmation, final-pattern guard, and undo behavior; rename is now an intentional 6-char-capped sheet with a live counter (fixed by #2/#2-retry), not a defect — re-verify rest fresh this hunt | next: add/duplicate/rename/4-64-step bounds/delete/undo pass, then blank/duplicate-name rename validation, Clear confirm/cancel, redo, and step-count-change effect on existing note data

J5 | arrange and play a complete song | ARR -> ArrangementView -> SONG playback | at least two distinct patterns | sections, pattern choices, order, and repeat counts persist and playback follows the visible arrangement
states/branches: add/reorder/delete section; repeats 1/16; empty fallback; PATT vs SONG; edit while playing; exactly/over 128 plays
coverage: iPhone pass 2 | tested: reorder(partial)/delete sections, repeats 1/16 bounds, PATT↔SONG switch, live-edit-while-playing, >128-play-through capacity warning (orange banner shown correctly) — all correct; arrangement summary mislabel (fixed, #9); empty-arrangement branch unreachable (final-section guard, intentional); found "Add section" Menu control appears completely non-functional via tap — the only way a section is ever added is the undocumented side effect of creating a new pattern (filed, #11) | next: confirm #11 isn't a testing-tool Menu-tap artifact before/while fixing; J9 cancel-mid-render remains blocked (simulator DSP render too fast even at max 128-play/4:16 arrangement)

J6 | design and manage a track sound | select track header -> InstrumentEditor/docked editor | existing track | preset/manual parameters, mute, channel kind, rename, duplicate, clear, and delete affect the intended voice and notes
states/branches: preset/custom; pulse duty; hold/decay; arpeggio; mute/preview; kind switch; duplicate; clear current pattern; delete across patterns; 1/8-track bounds; undo
coverage: iPhone pass 3 | tested: preset/custom switch, channel-kind switch, duplicate-with-multi-pattern-notes, clear-current-pattern-only, delete-across-patterns+undo, 1/8-track bounds, pulse duty (persist/revert-on-kind-switch), arpeggio (set + kind-switch reset), mute visual toggle — all correct except Hold toggle requires a long-press instead of a normal tap (filed) | next: audio-verification of mute/preview needs a physical device (no audio capture in this toolset)

J7 | manage the song library | Songs -> SongListView | starter or seeded five-song library | create/open/rename/duplicate/share/delete updates the right project and current-song indicator without losing edits
states/branches: immediate save on open; newest-first sort; new; open; rename validation; duplicate; share; delete non-current/current/last; close/reopen
coverage: discovered | tested: none this hunt | next: seeded-library create/open/rename/duplicate and current/non-current deletion

J8 | share and import an editable song | song menu/library Share; Songs -> Add -> Import; open `.chipsong` URL | valid, malformed, legacy, hostile, and duplicate-ID files | valid input becomes a normalized local copy; invalid input explains failure; shared file is usable and named safely
states/branches: share success/failure/cancel; picker cancel; malformed JSON; ID collision; legacy migration; out-of-range normalization; launch-time URL
coverage: iPhone pass 1 (partial) | tested: malformed-JSON import, valid-JSON-missing-required-fields import, duplicate-ID re-import — all correct (clean "Import failed" alert or fresh-UUID distinct entry, no crash/corruption) | next: share success/cancel via real Files/Mail flow, legacy migration, out-of-range normalization, launch-time cold URL, hostile/oversized files. Lead: the system "Save to Files" document picker from in-app Share appeared to hang navigating the Apps location list — needs a follow-up pass with correct point-based tap coords (first attempt used screenshot-pixel coords) before treating as a real bug.

J9 | export and share a WAV | song menu -> Export WAV | song with audible arrangement | render progress is truthful; cancel/retry works; completed WAV has selected repeat/ending and share appears once
states/branches: repeats 1/16; seamless/ring-out; progress; cancel; retry; double submit; write failure; oversized RIFF; share cancel/complete/failure
coverage: iPhone pass 1 | tested: repeats 1/16 bounds, seamless/ring-out duration reflection, progress UI, double-submit (single share sheet), share-sheet-once across 3 exports — all correct; stepper buttons stay enabled past bounds rather than disabling (S4, not filed) | next: cancel-mid-render/retry (simulator DSP render too fast to land a cancel tap — needs a much longer arrangement or different technique) and the 128-flattened-playthrough cap warning (needs a multi-section arrangement built first)

J10 | recover edits across undo, autosave, and lifecycle changes | mutate tempo/title/cells/patterns/tracks/arrangement -> undo/relaunch | sentinel edits in one song and at least two songs | unrelated operations undo separately; redo invalidates correctly; autosave preserves the active song without crossing song boundaries
states/branches: coalesced same-kind edits; unrelated rapid edits; title run; background before debounce; save failure; open/new/delete resets history; 50-entry limit
coverage: iPhone pass 1 | tested: unrelated-edit segmentation, background-before-debounce save, cross-song autosave boundary, song-switch undo reset, title-edit coalescing, redo invalidation — all correct; discrete BPM-stepper taps don't coalesce (lead, not filed as a bug) | next: 50-entry undo limit, save-failure path, BPM drag/slider coalescing

## Condition Matrix

Conditions are recorded in each journey's `tested` field after use. They are not JIDs and never substitute for core journey coverage.

| Condition | Stage | Fresh-hunt status |
|---|---|---|
| iPhone SE (3rd gen)/iOS 17.5 and iPhone 16 Pro Max/iOS 26.5 | representative target coverage across core journeys | not run |
| portrait only (iPhone has no landscape/split/docked layout per app contract) | representative iPhone branches | not run |
| status-bar extremes (top safe area) | applicable Track B layout branch | not run |
| forced dark appearance | representative Track B states | not run |
| realistic long names and maximum app-valid data | core journey depth | not run |
| pseudo-localization | Track B compatibility escalation | not run |
| RTL locale | changed-environment escalation | not run |
| accessibility Dynamic Type/contrast/motion settings | accessibility-specific presentation escalation | not run |
| VoiceOver semantics/focus | accessibility-specific Track A escalation | not run |
| physical-device audio interruption, route, latency, and timing | hardware-only follow-up; simulator cannot certify | not run |

## Product Intent And Exclusions

- There is no onboarding. The populated starter song is the first-run teaching path.
- PATT loops the edited pattern. SONG follows the arrangement until the user intentionally pins another pattern.
- Song deletion is permanent. Pattern and track deletion are undoable.
- The arrangement capacity warning is mitigation for a fixed DSP limit, not a promise that all visible sections play.
- No background-audio mode is declared; continuing playback after suspension is not expected.
- Removing headphones or losing an output route intentionally stops playback rather than switching to speakers.
- Lock-free, word-sized `ChipCore` parameter races are intentional and known to TSan; races elsewhere are not covered by that exception.
- SongListView's normal empty state is effectively unreachable because launch and last-song deletion create a song. Do not force artificial reachability and call it a user defect.
- Use actual VoiceOver for semantic findings. A historical tree walker reported an empty SongList toolbar group despite visible labeled controls, so tree output alone is inconclusive there.

## Tests And Fixtures

- `Tests/Support/TestSongs.swift`: empty, single-note, two-pattern, golden, and deterministic seeded songs.
- `Tests/Support/TempStore.swift`: isolated Documents and UserDefaults storage.
- `Tests/Fixtures/golden-demo.wav`: deterministic DSP golden output.
- `AppStore/make_song.py`: five-song visual/library fixture.
- There is extensive hosted unit coverage but no XCUITest or snapshot-test target.

```sh
xcodebuild test -project Chiptune.xcodeproj -scheme Chiptune -destination "id=<UDID>" -resultBundlePath TestResults.xcresult -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
```

The unit-test host intentionally suppresses creation of the real app `Studio`, so hosted tests do not exercise the normal launch UI or CoreAudio startup path.

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

Current source HEAD: `7f0643f`. Built and installed on both iPhone simulators.

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
coverage: discovered | tested: none this hunt | next: note-entry run, cursor boundaries, and focus return after title editing

J4 | create and manage pattern variations | Pattern bar | song below 16-pattern limit | add/duplicate/rename/clear/delete/resize produces the intended pattern and coherent arrangement references
states/branches: add; duplicate; unique/blank/long rename; 4/64-step bounds; clear cancel/confirm; delete cancel/confirm; final-pattern guard; undo
coverage: iPhone SIM-A pass 1 | tested: add (works, auto-letters B/C, empty+selected), duplicate via long-press context menu (correctly copies sentinel note content), long rename (BUG: silently truncates to 6 characters, see below), 4-step floor and 64-step ceiling (both correctly disable their stepper button, +/-4 linear increments), delete confirmation dialog (uses truncated name), final-pattern guard (Delete menu item correctly disabled when 1 pattern remains), undo of pattern delete (restores pattern AND its note content intact) | next: blank/duplicate-name rename validation, Clear confirm/cancel, redo, and step-count-change effect on existing note data (steps beyond new count)

J5 | arrange and play a complete song | ARR -> ArrangementView -> SONG playback | at least two distinct patterns | sections, pattern choices, order, and repeat counts persist and playback follows the visible arrangement
states/branches: add/reorder/delete section; repeats 1/16; empty fallback; PATT vs SONG; edit while playing; exactly/over 128 plays
coverage: discovered | tested: none this hunt | next: two-pattern arrangement, reorder/repeats, SONG playback, and capacity warning

J6 | design and manage a track sound | select track header -> InstrumentEditor/docked editor | existing track | preset/manual parameters, mute, channel kind, rename, duplicate, clear, and delete affect the intended voice and notes
states/branches: preset/custom; pulse duty; hold/decay; arpeggio; mute/preview; kind switch; duplicate; clear current pattern; delete across patterns; 1/8-track bounds; undo
coverage: discovered | tested: none this hunt | next: edit one track via the InstrumentEditor sheet, then duplicate/delete with sentinel notes

J7 | manage the song library | Songs -> SongListView | starter or seeded five-song library | create/open/rename/duplicate/share/delete updates the right project and current-song indicator without losing edits
states/branches: immediate save on open; newest-first sort; new; open; rename validation; duplicate; share; delete non-current/current/last; close/reopen
coverage: discovered | tested: none this hunt | next: seeded-library create/open/rename/duplicate and current/non-current deletion

J8 | share and import an editable song | song menu/library Share; Songs -> Add -> Import; open `.chipsong` URL | valid, malformed, legacy, hostile, and duplicate-ID files | valid input becomes a normalized local copy; invalid input explains failure; shared file is usable and named safely
states/branches: share success/failure/cancel; picker cancel; malformed JSON; ID collision; legacy migration; out-of-range normalization; launch-time URL
coverage: discovered | tested: none this hunt | next: share then re-import a sentinel song, malformed import, and duplicate-ID import

J9 | export and share a WAV | song menu -> Export WAV | song with audible arrangement | render progress is truthful; cancel/retry works; completed WAV has selected repeat/ending and share appears once
states/branches: repeats 1/16; seamless/ring-out; progress; cancel; retry; double submit; write failure; oversized RIFF; share cancel/complete/failure
coverage: discovered | tested: none this hunt | next: normal export/share, cancellation/retry, and rapid repeated Export

J10 | recover edits across undo, autosave, and lifecycle changes | mutate tempo/title/cells/patterns/tracks/arrangement -> undo/relaunch | sentinel edits in one song and at least two songs | unrelated operations undo separately; redo invalidates correctly; autosave preserves the active song without crossing song boundaries
states/branches: coalesced same-kind edits; unrelated rapid edits; title run; background before debounce; save failure; open/new/delete resets history; 50-entry limit
coverage: discovered | tested: none this hunt | next: mixed edits, background before debounce, relaunch, and cross-song undo boundary

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

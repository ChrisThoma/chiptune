# Chiptune APPMAP

Bundle ID: `dev.individuation.chiptune`
Scheme: `Chiptune` | Project: `Chiptune.xcodeproj` | Deployment target: iOS 17.0
Target: iPhone (SE-class and large). iPad behavior is out of scope for this hunt. This is a fresh hunt for the iPhone target: all journey and condition coverage starts reset. iPad-only facts from a prior hunt are retained below only where they describe app behavior relevant to iPhone (shared model/state/limits); iPad-specific layout/coverage rows are removed or superseded.

Chiptune is an offline NES-style step sequencer. Its model is Song -> Patterns -> Tracks -> Steps, with a separate arrangement controlling full-song playback.

## Simulators

Reuse these; never duplicate them.

| Slot | Name | UDID | Runtime/device |
|---|---|---|---|
| SIM-A | BugHunt-Chiptune-iPhone-A | `DEE64415-DCDF-4C29-9252-D20243BDE2C6` | iOS 26.5, iPhone SE (3rd generation) |
| SIM-B | BugHunt-Chiptune-iPhone-B | `DD767673-47C3-41C9-9ED6-8C4BC1B04B37` | iOS 26.5, iPhone 16 Pro Max |

iPad simulators from a prior hunt (`BugHunt-Chiptune-iPad-A` / `-B`) remain registered but are out of scope for this target; do not drive them.

Deployment target is iOS 17.0 but the only installed runtimes are iOS 26.5 and 27.0, so minimum-OS behavior is `unsupported` on this machine: a fix that relies on an iOS 18+ API cannot be checked for iOS 17 users here.

Environment baseline per sim: locale en_US, appearance dark (app forces dark), content size large, no status-bar override. Assert before wave 1 and after every worker, reading the values from the simulator, never from the host:

```sh
xcrun simctl ui <UDID> appearance            # prints dark
xcrun simctl ui <UDID> content_size          # prints large
xcrun simctl spawn <UDID> defaults read -g AppleLocale   # en_US; a "does not exist" error means the default en_US was never overridden
```

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

To import a hand-made song, write a `.chipsong` JSON file (same shape as the files `AppStore/make_song.py` emits; give each copy a fresh song UUID) and deliver it by URL. This is also the way to reach large states such as 16 patterns, 8 tracks or a 129-play arrangement; do not tap them into existence.

```sh
xcrun simctl openurl <UDID> "file:///absolute/path/fixture.chipsong"
```

To force save, duplicate, rename, delete and export write failures, make the store read-only, and always restore it afterwards:

```sh
chmod 555 "$CONTAINER/Documents/Songs"   # probe
chmod 755 "$CONTAINER/Documents/Songs"   # restore
```

The seeded library includes Neon Ascent, Coin Rush, Slow Cartridge, Boss Door, and Overworld Sketch. An ordinary empty-store launch instead creates the populated starter song `First Loop` at 132 BPM.

## Navigation And Surfaces

- `ChiptuneApp` shows `SplashView`, builds `Studio`, restores the last song or seeds `First Loop`, then fades to `ContentView`.
- `ContentView` is the single editor root. It has no tab bar or root navigation stack.
- Title bar: Songs, editable song title, Undo, Redo, and song menu.
- Transport: Play/Stop, PATT/SONG mode, Arrangement, and BPM controls.
- Pattern bar: select, add, rename, duplicate, clear, delete, and change step count.
- Grid: tracks as columns and steps as rows; cells place/replace/clear/preview notes; track headers select, mute, and open the sound settings (duplicate, clear, delete); long-press enters reorder mode (drag or arrows, Done/tap grid exits).
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

J2 | compose and revise notes by touch | editor keyboard + step grid | selected pattern/track/note | taps place, replace, clear, preview, and note-off correctly; audio model follows edits; undo/redo restores intent
states/branches: empty/occupied cell; same/different note; long-press preview; OFF; octave; muted track; sustained note; rapid painting; undo/redo

J3 | compose with a hardware keyboard | editor with hardware keyboard connected | Simulator I/O -> Keyboard -> Connect Hardware Keyboard | mapped keys move the cursor, enter/clear notes, control octave/OFF, and play/stop without stealing text-field input
states/branches: first key reveals cursor; arrow edge; step wrap; pattern shrink; track deletion; rename focus handoff; unsupported/modifier keys

J4 | create and manage pattern variations | Pattern bar | song below 16-pattern limit | add/duplicate/rename/clear/delete/resize produces the intended pattern and coherent arrangement references
states/branches: add; duplicate; unique/blank/long rename; 4/64-step bounds; clear cancel/confirm; delete cancel/confirm; final-pattern guard; undo

J5 | arrange and play a complete song | ARR -> ArrangementView -> SONG playback | at least two distinct patterns | sections, pattern choices, order, and repeat counts persist and playback follows the visible arrangement
states/branches: add/reorder/delete section; repeats 1/16; empty fallback; PATT vs SONG; edit while playing; exactly/over 128 plays

J6 | design and manage a track sound | select track header -> InstrumentEditor/docked editor | existing track | preset/manual parameters, mute, channel kind, rename, duplicate, clear, and delete affect the intended voice and notes
states/branches: preset/custom; pulse duty; hold/decay; arpeggio; mute/preview; kind switch; duplicate; clear current pattern; delete across patterns; reorder (header long-press, drag/arrows, 1-track no-op); 1/8-track bounds; undo

J7 | manage the song library | Songs -> SongListView | starter or seeded five-song library | create/open/rename/duplicate/share/delete updates the right project and current-song indicator without losing edits
states/branches: immediate save on open; newest-first sort; new; open; rename validation; duplicate; share; delete non-current/current/last; close/reopen

J8 | share and import an editable song | song menu/library Share; Songs -> Add -> Import; open `.chipsong` URL | valid, malformed, legacy, hostile, and duplicate-ID files | valid input becomes a normalized local copy; invalid input explains failure; shared file is usable and named safely
states/branches: share success/failure/cancel; picker cancel; malformed JSON; ID collision; legacy migration; out-of-range normalization; launch-time URL

J9 | export and share a WAV | song menu -> Export WAV | song with audible arrangement | render progress is truthful; cancel/retry works; completed WAV has selected repeat/ending and share appears once
states/branches: repeats 1/16; seamless/ring-out; progress; cancel; retry; double submit; write failure; oversized RIFF; share cancel/complete/failure

J10 | recover edits across undo, autosave, and lifecycle changes | mutate tempo/title/cells/patterns/tracks/arrangement -> undo/relaunch | sentinel edits in one song and at least two songs | unrelated operations undo separately; redo invalidates correctly; autosave preserves the active song without crossing song boundaries
states/branches: coalesced same-kind edits; unrelated rapid edits; title run; background before debounce; save failure; open/new/delete resets history; 50-entry limit

J11 | reorder tracks by drag | track header long-press (about 0.9 s) -> reorder mode -> drag a header, or per-header arrows -> Done or tap grid | song with at least 3 tracks, notes in more than one pattern, a muted track, a selected track | track order changes in header, grid columns, keyboard track label and every pattern together; notes, names, mute and sound stay with their track; selection follows the moved track; undo restores the old order
states/branches: enter by long-press; drag one slot left/right; drag to first/last position; drag and release in place; arrows at first/last (stopped control explains itself); drag a muted or selected track; reorder while playing; Done vs tap-grid exit; hardware Return/Escape intentionally do nothing; 1-track no-op; 8-track song; undo/redo after reorder; relaunch persistence
notes: iOS drag needs a slow `idb ui swipe` with a 0.5 s or longer duration, since `ui_swipe` may do nothing; enter reorder mode with a long-press of 0.9 s (`idb ui tap --duration`); a released drag outside the header strip must not lose the track; the held notes of a ringing track must not hang after a move (moveTrack releases voices)

## Condition Matrix

Conditions are recorded in each journey's `tested` field after use. They are not JIDs and never substitute for core journey coverage.

| Condition | Stage |
|---|---|
| iPhone SE (3rd gen) and iPhone 16 Pro Max, both iOS 26.5 (no iOS 17 runtime installed) | representative target coverage across core journeys |
| portrait only (iPhone has no landscape/split/docked layout per app contract) | representative iPhone branches |
| status-bar extremes (top safe area) | applicable Track B layout branch |
| forced dark appearance | representative Track B states |
| realistic long names and maximum app-valid data | core journey depth |
| pseudo-localization | Track B compatibility escalation |
| RTL locale | changed-environment escalation |
| accessibility Dynamic Type/contrast/motion settings | accessibility-specific presentation escalation |
| VoiceOver semantics/focus | accessibility-specific Track A escalation |
| physical-device audio interruption, route, latency, and timing | hardware-only follow-up; simulator cannot certify |

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
- Generated large-state fixtures (git-ignored, regenerate with `python3 .qa/hunt-2026-10-03/fixtures/gen_fixtures.py`): `bpm300_longname.chipsong` (300 BPM, 33-character name, 3 patterns), `ten_patterns.chipsong`, `plays129.chipsong` (S1-S8 at 16 repeats plus S9 once), `plays128.chipsong` (S1-S8 at 16 repeats; S9 defined but unused), `one_track.chipsong`, `eight_tracks.chipsong` (track 3 muted). Deliver each with `xcrun simctl openurl <UDID> "file:///abs/path/<file>.chipsong"`. Shape: plain JSON with `id, name, tempo, modified, tracks, patterns, arrangement`; `tempo` is the BPM key; `modified` is seconds since 2001-01-01; each pattern's `rows` holds one 64-entry list per track regardless of `length`; arrangement entries are `{id, patternID, repeats}`.
- There is extensive hosted unit coverage but no XCUITest or snapshot-test target.

```sh
xcodebuild test -project Chiptune.xcodeproj -scheme Chiptune -destination "id=<UDID>" -resultBundlePath TestResults.xcresult -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
```

The unit-test host intentionally suppresses creation of the real app `Studio`, so hosted tests do not exercise the normal launch UI or CoreAudio startup path.

## Tooling Caveats

- First `simctl launch` on a freshly booted sim can hang indefinitely (seen on SIM-B); shutdown and reboot fixes it. macOS has no `timeout` binary, so background the call. Screenshot-verify the frontmost app after launch.
- Earlier workers leave imported test songs and edited starter songs behind. Start each finder from the clean-state reset above (starter song) or from the seeded five-song library, and say which in the prompt; never rely on a leftover song as a fixture.
- Act and look in one shell call: `idb ui tap --udid <UDID> <x> <y>; sleep 1; xcrun simctl io <UDID> screenshot <orig>.png; sips -Z 750 <orig>.png --out <view>.png`. The MCP screenshot tool only writes a file, so separate tap, screenshot, downscale and view calls cost four tool calls per interaction.
- `ui_swipe` may do nothing for drags; use a slow `idb ui swipe --duration 0.5` or longer. Wait about 2 s after a sheet or share-sheet dismissal before the next tap, or the tap is dropped.
- Tap coordinates are per device. Never reuse SE coordinates on the Pro Max or the reverse; locate the control on the assigned sim.
- Pass `ui_find_element` search terms as a JSON array of quoted strings; a bare word fails validation.
- `xcrun simctl terminate` exits 1 when the app is not running and breaks a `&&` chain; follow it with `;`.
- The harness blocks a leading `sleep N; cmd` longer than a couple of seconds; keep waits short and inside the act-and-look call.
- Typing into the song title field can trigger autocorrect ("Zq" became "Zach"); use sentinel names that are real words or check the committed text.
- Undo and Redo are absent from the accessibility tree while a sheet is open; close the sheet before looking them up.
- zsh treats a bare `==` in `echo` as a command; avoid it in scripts.
- The in-app song-menu footer build stamp shows the HEAD at build time, which is the previous commit when a build is made before committing, and CFBundleVersion is the same for every local build. Neither proves build identity; use the app path and its mtime.
- `-NSDoubleLocalizedStrings YES` doubles whole format strings, so one-argument formats show leaked fragments (lld, @) in the BPM and STEPS readouts, Export summary and ARR rows. This is a property of the pseudo-locale, not an app defect (round-3 #6); only clipping, wrapping and lost tap targets under that condition are findings.
- `idb` is not on PATH inside scripts: use the full path from `which idb` or the pyenv shim path, or the first run of every script silently no-ops.
- A real RTL layout needs `-NSForceRightToLeftWritingDirection YES`; `-AppleLanguages "(ar)" -AppleLocale ar_SA` alone leaves the app LTR (no Arabic localization), so RTL is unsupported for real users.
- The accessibility walker renders a Stepper as two Buttons, reports a dimmed bound button as enabled, and shows Volume and Decay slider values as null; ui_find_element on the visible label is the cross-check. The pattern chip menu opens with `idb ui tap --duration 1.0` on a chip and its actions are also exposed as accessibility custom actions.
- A verification build must come from `git archive <commit>` into a scratch directory under `build/`, then `xcodegen generate` and `xcodebuild` with its own `-derivedDataPath`; a build from the working tree can include another agent's uncommitted edits.

# Chiptune APPMAP

Bundle ID: `dev.individuation.chiptune`
Scheme: `Chiptune` | Project: `Chiptune.xcodeproj` | Deployment target: iOS 17.0
Target: iPad (two sizes: iPad mini and 13-inch iPad Pro). iPhone behavior is out of scope for this map. iPhone-only facts are kept below only where they describe shared model, state or limits.

Chiptune is an offline NES-style step sequencer. Its model is Song -> Patterns -> Tracks -> Steps, with a separate arrangement controlling full-song playback.

## Simulators

Reuse these; never duplicate them.

| Slot | Name | UDID | Runtime/device |
|---|---|---|---|
| SIM-A | BugHunt-Chiptune-iPad-A | `364E182C-E581-4112-A332-5AFA806DD2F3` | iOS 26.5, iPad mini (A17 Pro), 744x1133 pt portrait |
| SIM-B | BugHunt-Chiptune-iPad-B | `64697D11-B8FB-46BE-9BCF-BCCC33A6F4B7` | iOS 27.0, iPad Pro 13-inch (M5), 1032x1376 pt portrait |

iPhone simulators (`BugHunt-Chiptune-iPhone-A` / `-B`) belong to the iPhone target; do not drive them.

Deployment target is iOS 17.0 but the only installed runtimes are iOS 26.5 and 27.0, so minimum-OS behavior is `unsupported` on this machine: a fix that relies on an iOS 18+ API cannot be checked for iOS 17 users here.

Environment baseline per sim: locale en_US, appearance dark (app forces dark), content size large, no status-bar override. Assert before wave 1 and after every worker, reading the values from the simulator, never from the host:

```sh
xcrun simctl ui <UDID> appearance            # prints dark
xcrun simctl ui <UDID> content_size          # prints large
xcrun simctl spawn <UDID> defaults read -g AppleLocale   # en_US; a "does not exist" error means the default en_US was never overridden
```

Repository notes report an iOS 26 Simulator dimming artifact on 13-inch iPad sheets; treat sheet-dimming oddities on SIM-B as a tooling lead until reproduced on SIM-A.

Orientation on iPad: `xcrun simctl` has no rotate command and this Xcode has no Simulator.app; use the `ios-simulator`/idb server's orientation support if present, otherwise mark landscape `unsupported` for that worker. Split View/Stage Manager is not automatable here.

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

If several are supplied, enum order wins: arrangement, instrument, library, export. `-shotEditor YES` is inert in wide landscape on iPad, where the instrument editor is docked.

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
- Modal/system surfaces: SongListView, ArrangementView, InstrumentEditor, ExportSheet (Format WAV / MIDI / Video; Video adds a Style picker with Cartridge and Grid styles and social-platform framing for IG, TikTok and YouTube), export ShareSheet (Save Video to Photos needs Photos add permission), song-file ShareSheet, file importer, alerts, confirmation dialogs, support Link, and StoreKit review request.
- InstrumentEditor is a popover in regular-width portrait iPad and docked beside the grid in wide landscape iPad; it falls back to a sheet at compact width (narrow Split View).
- On iPad the first tap on a track header selects the track and a second tap opens its instrument editor; the portrait popover is anchored by its arrow to that header and scrolls internally below Channel.
- On iPad, Songs, export share and song-file share are `.sheet`s (form sheets; the share sheets host `UIActivityViewController` with no popover anchor). Arrangement is a popover anchored to the transport's ARR control, Export a popover off the ••• menu, keyboard help a popover; all three adapt to sheets at compact width. PatternBar rename is a sheet.
- Layout resolves from horizontal size class plus window size (never device idiom): `.pad` metrics at regular width, `.phone` at compact; falls back to a stacked, scrolled layout when the height left after the fixed editor chrome holds fewer than 4 grid rows. The instrument editor is docked exactly when the side keyboard layout is used, a popover at regular width otherwise, a sheet at compact width; the docked editor owns its own Clear track and Delete track alerts.
- Songs rows: newest first with a green OPEN badge on the current song; a row's context menu (Rename, Duplicate, Share song file, Delete) opens with a long press (a 1.2 s idb press works); opening a song closes Songs.
- ARR popover: Edit / Arrangement / Done header; Add section and each row's pattern picker are Pattern A/B/C menus; footer "<n> patterns · <steps> steps · <m:ss> at <BPM> BPM"; a green speaker marks the sounding section; a tap outside it (including on the transport) only dismisses it.
- In 13-inch portrait the grid is a fixed viewport (about y 300 to 1111 pt) above a fixed piano dock; a 16-step pattern shows steps 00 to 14 and scrolls one row for step 15 (by design; checked by measurement).
- Song menu (•••): New song, Import song…, Duplicate song, Export…, Share song file, Clear pattern, Contact support. Import song… opens the Files picker. A re-imported file whose song ID already exists becomes a new song named "<name> (imported)".
- Presenter bookkeeping: `anyPresented` covers Songs, Arrangement, Export, Share, keyboard help, song-bound presenters and a pending share URL; `SongBoundPresenters` surfaces are pattern rename/clear/delete, tempo alert and track sound.
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
- Multi-window, background audio, MIDI input, sample/audio import, stereo/pan, collaboration, and cloud library are unsupported.
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

J9 | export and share a WAV or MIDI file | song menu -> Export… | song with audible arrangement | render progress is truthful; cancel/retry works; completed WAV has selected repeat/ending; MIDI hides Repeats/Ending and shares a `.mid` that matches the `midi-*.mid` golden rules; share appears once
states/branches: repeats 1/16; seamless/ring-out; progress; cancel; retry; double submit; write failure; oversized RIFF; share cancel/complete/failure; each opening starts at WAV/1x/Seamless loop, but a canceled share keeps the choices; at compact width the Export sheet reopens by itself, at regular-width iPad it stays closed until reopened

J10 | recover edits across undo, autosave, and lifecycle changes | mutate tempo/title/cells/patterns/tracks/arrangement -> undo/relaunch | sentinel edits in one song and at least two songs | unrelated operations undo separately; redo invalidates correctly; autosave preserves the active song without crossing song boundaries
states/branches: coalesced same-kind edits; unrelated rapid edits; title run; background before debounce; save failure; open/new/delete resets history; 50-entry limit

J11 | reorder tracks by drag | track header long-press (about 0.9 s) -> reorder mode -> drag a header, or per-header arrows -> Done or tap grid | song with at least 3 tracks, notes in more than one pattern, a muted track, a selected track | track order changes in header, grid columns, keyboard track label and every pattern together; notes, names, mute and sound stay with their track; selection follows the moved track; undo restores the old order
states/branches: enter by long-press; drag one slot left/right; drag to first/last position; drag and release in place; arrows at first/last (stopped control explains itself); drag a muted or selected track; reorder while playing; Done vs tap-grid exit; hardware Return/Escape intentionally do nothing; 1-track no-op; 8-track song; undo/redo after reorder; relaunch persistence
notes: iOS drag needs a slow `idb ui swipe` with a 0.5 s or longer duration, since `ui_swipe` may do nothing; enter reorder mode with a long-press of 0.9 s (`idb ui tap --duration`); a released drag outside the header strip must not lose the track; the held notes of a ringing track must not hang after a move (moveTrack releases voices)

J12 | export a song as a video for social posting | song menu -> Export… -> Format: Video -> Style (Cartridge or Grid) and other video options -> Export -> share sheet (Save Video, AirDrop, apps) | song with audible arrangement; long or line-broken song name for title layout; Photos add permission granted or denied | progress is truthful; cancel/retry works; the video shows the chosen style with the song's title, tracks and notes in time with the soundtrack; length follows the arrangement and repeat choice; the file is shareable and Save Video lands in Photos or explains a denied permission
states/branches: each Style; Repeats/Ending as offered for Video; progress; cancel mid-render; cancel while the file finishes; retry; double submit; background mid-render (the app says to stay in the app); write failure (read-only store or disk full); too-long arrangement refused up front; share cancel/complete; Photos denied; muted tracks dimmed; pattern changes scroll the Grid style; long caption keeps content above it
notes: Video always rings out, so the Ending choice is hidden for Video; Style resets to Grid on each opening of the sheet; the video cap is 600 s and an over-cap song disables Export with the footer "Too long for a video — 10:00 max." (no alert); a Reels/Shorts note appears above 180 s; a song switch or import mid-render closes the sheet and cancels silently. Cartridge style draws tempo, a total length, an elapsed clock and a progress bar; Grid style draws the title on one line and "PAT · STEP nn · BPM". Exports write only to tmp, so an unwritable Songs store does not affect them; an unwritable tmp fails at once with "Export failed — Couldn't export "<song>". The app doesn't have permission to write the video." and the Export sheet stays open. After Save Video the app returns to the editor with no confirmation; the asset appears in the simulator's `data/Media/DCIM/100APPLE/`. Scratch lives in `tmp/video-scratch` (soundtrack WAV plus the mp4 being written, swept only by the next video export) and `tmp/wav-scratch`; the finished file is `tmp/<songUUID>/<safeName>.mp4`.
notes: the Video format shows "A 9:16 video for sharing to IG, TikTok, YouTube, etc.", a Repeats stepper 1x-16x with "The whole arrangement, N times, <length>" (video length includes the ring-out tail, so it exceeds the WAV seamless length), and Style Grid/Cartridge with a one-line description each; Export shows an in-sheet "Exporting… N%" bar with settings dimmed and a red Cancel export; output is 1080x1920 h264 30 fps plus AAC; after a share finishes the sheet resets to WAV. With Photos add permission unset or denied, iOS omits Save Video from the share sheet. `xcrun simctl privacy ... revoke photos-add` terminates the running app (iOS behavior).
notes: pull the finished file with `find "$(xcrun simctl get_app_container <UDID> dev.individuation.chiptune data)" -name '*.mp4' -o -name '*.mov'` and inspect it off-simulator with `ffprobe` (duration, size, streams) and `ffmpeg -ss <t> -frames:v 1` stills; Photos permission is `xcrun simctl privacy <UDID> grant|revoke photos-add dev.individuation.chiptune`

## Condition Matrix

Conditions are recorded in each journey's `tested` field after use. They are not JIDs and never substitute for core journey coverage.

| Condition | Stage |
|---|---|
| iPad mini (iOS 26.5) and iPad Pro 13-inch (iOS 27.0) (no iOS 17 runtime installed) | representative target coverage across core journeys |
| iPad portrait vs landscape (docked instrument editor) | representative iPad branches where rotation is automatable |
| iPad Split View / Stage Manager narrow widths | changed-environment escalation; not automatable here |
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
- `ui_swipe` may do nothing for drags; use a slow `idb ui swipe --duration 0.5` or longer. Wait about 2 s after a sheet dismissal before the next tap. Closing the export share sheet with its X re-raises the Export panel at compact width; at regular width it stays closed. On a build where the Export popover comes back, a tap outside it only dismisses it: look for the popover in the screenshot before calling a tap swallowed, and take the screenshot after a 1-2 s wait (idb tap calls can take several seconds to return).
- Tap coordinates are per device. Never reuse coordinates from another simulator (iPad mini, 13-inch iPad Pro, or any iPhone); locate the control on the assigned sim.
- Pass `ui_find_element` search terms as a JSON array of quoted strings; a bare word fails validation.
- Landscape on this machine: no rotate command exists, so build a scratch landscape-only variant from `git archive <commit>` (in its Info.plist set `UISupportedInterfaceOrientations~ipad` to the two landscape values and `UIRequiresFullScreen` YES) into its own `build/` folder; screenshots of it come out sideways and must be rotated back with `sips -r`. In that landscape-only build on the iPad mini, idb taps are not in accessibility-frame space: convert a frame point (x, y) to an input point (x/1.523, (y+484)/1.523) and check with describe-point.
- Under heavy host load (two fixers building plus other sessions' simulators; load average near 1000) `simctl openurl`, `launch` and `io screenshot` can hang past 120 s and idb returns "No translation object returned for simulator". Do not run simulator finders while fixers do cold builds; check `uptime` first.
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
- A simulator whose preferences daemon has wedged logs `Couldn't write values … Path not accessible` and floods `Couldn't read values … com.apple.assistant.support … Unable to determine access`; focusing any text field then pins the app at 70-90% CPU in `UIDictationController` and the accessibility tree comes back empty. It is a simulator fault (it reproduces on older builds). `xcrun simctl shutdown` then `boot` clears it. Turning dictation off on a simulator (`xcrun simctl spawn <UDID> defaults write com.apple.assistant.support "Dictation Enabled" -bool false`) avoids it.

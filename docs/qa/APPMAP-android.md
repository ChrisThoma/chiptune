# Chiptune Android APPMAP

Package: `dev.individuation.chiptune` | Launcher activity: `.ui.MainActivity` (`singleTask`) | Module: `android/app` | minSdk 26, targetSdk 36

Chiptune for Android is a port of the iOS app (`APPMAP.md` is the iOS map). The model, limits and product intent are the same: an offline NES-style step sequencer, Song -> Patterns -> Tracks -> Steps, with a separate arrangement for full-song playback. This file records what differs on Android and how to drive it.

## Emulators

Reuse these; never duplicate or kill an emulator you did not start. Always pass `-s <serial>`; other serials on the host (such as `emulator-5554`) belong to other projects.

| Slot | AVD | Serial | Notes |
|---|---|---|---|
| PHONE | `Chiptune_Audio_API_36` | `emulator-5580` | API 36 phone |
| TABLET | `Chiptune-Tablet-API36` | `emulator-5582` | API 36 tablet, `hw.keyboard=yes` |

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices
```

## Build, Install, Launch, Reset

JDK 17 only (`JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home`). The machine's default JDK 23 is unverified.

```sh
cd android && ./gradlew --no-daemon assembleDebug
$ADB -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk
$ADB -s <serial> shell am start -n dev.individuation.chiptune/.ui.MainActivity
```

A release build signed with the debug key may already be installed; signatures differ, so `install -r` fails. Uninstall first:

```sh
$ADB -s <serial> uninstall dev.individuation.chiptune
```

Clean state without reinstalling (wipes songs, current-song pointer and review counters):

```sh
$ADB -s <serial> shell am force-stop dev.individuation.chiptune
$ADB -s <serial> shell pm clear dev.individuation.chiptune
```

An empty-store launch creates the starter song `First Loop` at 132 BPM, as on iOS. There is no in-app reset.

Debug builds accept one screenshot extra, truthy value, as alternatives (first in this order wins): `shotArrangement`, `shotEditor`, `shotLibrary`, `shotExport`, `shotPlaying`, `shotPatternB`.

```sh
$ADB -s <serial> shell am start -n dev.individuation.chiptune/.ui.MainActivity --es shotEditor YES
```

Release builds ignore them.

## Seeding A Library

Songs persist as `files/Songs/<UUID>.json` in the app's private storage; there is no shared-storage copy.

1. **Import through the picker (any build).** Push fixtures, then in the app use Songs -> Add -> Import song and pick them from Downloads:
   ```sh
   $ADB -s <serial> push Tests/Fixtures/song-<name>.chipsong /sdcard/Download/
   ```
   `Tests/Fixtures/song-fixtures.json` lists each `song-*.chipsong` and whether it is meant to decode (malformed and legacy ones included). Give hand-made copies a fresh song `id`; a repeated id is a collision case (J8). Large states (16 patterns, 8 tracks, a 129-play arrangement) should be imported, not tapped in.
2. **Open with intent (any build).** Deliver a file through VIEW (see J8): `$ADB -s <serial> shell am start -a android.intent.action.VIEW -t application/json -d file:///sdcard/Download/x.chipsong -n dev.individuation.chiptune/.ui.MainActivity` (a `file:` URI works only where the app can read it; prefer the picker or Files app on API 30+).
3. **run-as (debug builds only).** Write straight into the library, then force-stop and relaunch so the store reloads:
   ```sh
   $ADB -s <serial> push x.chipsong /data/local/tmp/x.json
   $ADB -s <serial> shell "run-as dev.individuation.chiptune sh -c 'mkdir -p files/Songs; cp /data/local/tmp/x.json files/Songs/<UUID>.json'"
   ```
   The file must be a full song document (`id, name, tempo, modified, tracks, patterns, arrangement`; `modified` is seconds since 2001-01-01). `AppStore/make_song.py` builds the iOS five-song library in this shape and can be pointed at a scratch directory first.

## Forcing Write Failures

Debug builds only. Make the library read-only to probe save, duplicate, rename, delete and import failures, and restore it afterwards:

```sh
$ADB -s <serial> shell "run-as dev.individuation.chiptune chmod 555 files/Songs"   # probe
$ADB -s <serial> shell "run-as dev.individuation.chiptune chmod 755 files/Songs"   # restore
```

Export writes into the cache directory and "Save to device" through the system picker, so those fail differently (J9).

## Navigation And Surfaces

- `ChiptuneApp` builds the `Studio`; the system splash (Android 12+ `windowSplashScreenAnimatedIcon`, the vector launcher foreground on `#0D0D17`) covers startup, then the editor appears with the last song or `First Loop`.
- `AppRoot` is the single editor root; no tab bar, no navigation stack.
- Title bar: Songs, editable song title, Undo, Redo, song menu. Transport: Play/Stop, PATT/SONG, Arrangement, BPM. Pattern bar: select, add, rename, duplicate, clear, delete, step count. Grid: tracks as columns, steps as rows; header long-press enters reorder mode. Keyboard: octave, note, OFF, piano.
- Phone (compact width): Songs, Arrangement, the Instrument editor and Export are sheets over the editor. Back closes the top sheet.
- Tablet: the instrument editor is a popover in regular portrait and docked beside the grid in wide landscape; on a wide tablet the keyboard sits beside the grid. Layout comes from window size, not device type, so a small resizable window gets phone rules.
- Other surfaces: alerts and confirmation dialogs, the system file picker (import, Save to device), the system chooser (Share), the Play in-app review flow (no-op without Play).
- Intent filters on `MainActivity`: `VIEW` (schemes `content` and `file`; MIME `application/json` and `application/octet-stream`, `DEFAULT` + `BROWSABLE`) and `SEND` (the same two MIME types). Drag and drop of song files onto the editor is accepted on tablets and ChromeOS. No custom URL scheme, no web links.
- `Meta+/` opens the system keyboard-shortcut helper, fed by `onProvideKeyboardShortcuts` (Song, Edit, Pattern groups plus the unmodified keys).

## State, Data, And Limits

Same as iOS (`APPMAP.md`): autosave 1.5 s after edits and when the app stops, 1-8 tracks, 1-16 patterns, 4-64 steps, 40-300 BPM, 1-16 section repeats, 128 flattened arrangement play-throughs (entries past that stay editable but do not play or export, with a warning), note `-1` empty and `-2` note-off, imports normalized and copied into the library, deleting a song is permanent, pattern and track deletion undoable, undo history 50 entries.

Android-specific:
- Current song and review-prompt counters live in SharedPreferences (`chiptune.xml`); `files/Songs/` and that file are in Auto Backup and device transfer (`backup_rules.xml`, `data_extraction_rules.xml`); the cache (share/export copies) is excluded.
- No network permission, no account, no analytics. The only Google dependency is the Play in-app review library.
- Phones and tablets support all orientations and the activity is recreated on configuration change; the Studio lives in a ViewModel.
- Audio runs through `AudioTrack` with audio focus. Focus loss stops playback (like an iOS interruption), focus gain is handled, becoming-noisy (headphones unplugged) stops playback rather than moving to the speaker, and backgrounding stops the engine.
- The theme is a single dark palette (no light scheme); edge-to-edge with transparent system bars.

## Journeys

J1-J11 are the iOS journeys with the same intent and branches (see `APPMAP.md`), re-run on both emulators; the rows below give the Android changes. Conditions replace iOS specifics: touch coordinates are pixels from `adb shell input tap` (read them from `uiautomator dump` or the screenshot, never reuse phone coordinates on the tablet).

J1 | hear and restore the starter song | clean launch -> splash -> editor -> Play | `pm clear` or an existing library | starter audio plays, PATT/SONG truthful, relaunch restores the last song
states/branches: first launch; existing library; play/stop; audio-start failure; background while idle/playing; focus loss; cold vs warm start

J2 | compose and revise notes by touch | keyboard + grid | selected pattern/track/note | place, replace, clear, preview, note-off; undo/redo; same branches as iOS J2

J3 | compose with a hardware keyboard | TABLET emulator (hw.keyboard=yes) | keyboard attached | note row `A W S E D F T G Y H U J K`, `Z`/`X` octave, arrows, Space, Return, `\`, Delete; Ctrl chords: Ctrl+Z Undo, Ctrl+Shift+Z Redo, Ctrl+N New Song, Ctrl+O Songs, Ctrl+D Duplicate Song, Ctrl+E Export…, Ctrl+Shift+S Share Song File, Ctrl+Shift+N New Pattern, Ctrl+Shift+A Arrangement, Ctrl+Backspace Clear Pattern; Meta+/ lists them
states/branches: key with a sheet open (chords that open a surface wait; Ctrl+N works behind Songs/Arrangement/Export); text field focused (chords still run, Ctrl+Backspace stays word-delete); Escape in the title ends the rename; Escape with no sheet does nothing (not Back); auto-repeat of a held letter must not retrigger; Alt-modified keys pass through
notes: `adb shell input keyevent` events come from virtual device -1 and do not report as a hardware keyboard, so use a keyboard-configured AVD; Meta+/ needs `hw.keyboard=yes`

J4 | pattern variations | Pattern bar | below 16 patterns | add/duplicate/rename/clear/delete/resize; coherent arrangement references (as iOS J4)

J5 | arrange and play a complete song | Arrangement sheet -> SONG | two or more patterns | order, repeats, 128-play cap warning, edit while playing (as iOS J5)

J6 | design a track sound | track header -> instrument editor (sheet / popover / docked) | existing track | presets, duty, hold/decay, arpeggio, mute, kind, rename, duplicate, clear, delete, reorder, undo; the editor survives rotation and tablet resize

J7 | manage the song library | Songs | starter or seeded library | create/open/rename/duplicate/share/delete; current-song indicator; delete current/last

J8 | share, import and open an editable song | menu Share, Songs -> Import, intents, drop | valid, malformed, legacy, hostile and duplicate-ID files | valid becomes a normalized local copy; invalid explains itself; shared file named safely
states/branches (Android): picker cancel; VIEW intent from Files, Gmail or Drive (`content:` URI, octet-stream or json MIME); `adb shell am start -a android.intent.action.VIEW -t application/octet-stream -d <uri>`; SEND intent (Share sheet from another app, `--eu`/`EXTRA_STREAM`); intent arriving while the app is running (`onNewIntent`) and cold; rotation after an import must not re-import the same intent; drag a `.chipsong` from Files onto the editor on the tablet (split screen) or ChromeOS; several files dropped at once; non-song drop ignored; ID collision; legacy migration; out-of-range normalization

J9 | export and share a WAV or MIDI file | menu Export… | song with an audible arrangement | repeats 1/16, seamless/ring-out, progress, cancel, retry, double submit
states/branches (Android): result sheet offers Share and **Save to device**; Save to device opens `CreateDocument` (audio/wav, or audio/midi for a `.mid`) with a suggested name, cancel leaves the export available; saved file equals the exported WAV byte for byte (pull it and compare); Share shows the system chooser through FileProvider and the review prompt only follows a milestone share; write failure into the cache; low storage

J10 | recover edits across undo, autosave and lifecycle | edit -> undo / background / kill | sentinel edits in two songs | as iOS J10, plus process death: edit, wait under 1.5 s, `adb shell am kill dev.individuation.chiptune` (needs the app backgrounded) and reopen; or Developer options "Don't keep activities"; the last song and its edits return and the title/selection do not cross songs
states/branches: HOME then kill; kill during playback (reopen is stopped); activity recreate on rotation, font scale, dark/light and locale change; undo history reset after process death is expected

J11 | reorder tracks | header long-press -> drag or arrows -> Done | at least 3 tracks, notes in several patterns, a muted track | as iOS J11; slow drag with `adb shell input swipe x1 y1 x2 y2 900`

J12 | audio focus and output route | play SONG | audio running | losing focus stops playback truthfully (transport shows Stop state) and regaining it does not resume by surprise
states/branches: incoming call `adb -s <serial> emu gsm call 5551234`, answer with `emu gsm accept`, end with `emu gsm cancel 5551234`; another media app taking focus; becoming noisy: needs a root shell, `adb -s <serial> root`, then `adb -s <serial> shell am broadcast -a android.media.AUDIO_BECOMING_NOISY` (a protected broadcast; only works from root on emulator images that allow it); playback stops and does not move to the speaker; background while playing stops the engine; returning with focus lost shows the right state

J13 | tablet and window changes | TABLET emulator | any song | portrait/landscape, popover vs docked editor, resizing, split-screen with the Files app, hardware keyboard attached/detached; no state loss, grid and keyboard re-lay out, open editor survives
states/branches: rotate with a sheet open; split-screen narrow (phone rules); font scale 1.3+; display size large

## Condition Matrix

| Condition | Stage |
|---|---|
| phone emulator (API 36) and tablet emulator (API 36) | representative coverage across core journeys |
| portrait and landscape on both | Track B layout branches |
| dark theme (app is dark; check system light mode does not leak) | Track B |
| font scale 1.3-2.0 and display size large | accessibility presentation |
| TalkBack semantics and focus | accessibility Track A (use real TalkBack; `uiautomator dump` alone is inconclusive) |
| `adb shell wm density` / locale changes | recreate paths |
| real-device audio latency, route, call handling, jank | hardware-only; emulator cannot certify |

## Product Intent And Exclusions

- No onboarding; the starter song is the teaching path.
- PATT loops the edited pattern, SONG follows the arrangement.
- Song deletion is permanent; pattern and track deletion are undoable.
- Removing headphones stops playback rather than switching to the speaker; no background audio.
- The arrangement cap warning mitigates a fixed engine limit.
- Multi-window is allowed by the system but unsupported as a feature; MIDI input, sample import, stereo, collaboration and cloud library are out of scope.

## Tests And Fixtures

- `cd android && ./gradlew --no-daemon test lint assembleDebug`: 873 JVM unit tests, no instrumented suite.
- Shared fixtures in `Tests/Fixtures` (read in place), including `golden-demo.wav` (bit-exact WAV contract) and `song-fixtures.json`.
- `core/TestSongs.kt` builds the in-memory songs.

## Known Emulator Caveats

- The emulator has no FastMixer, so output latency is about 180 ms (about a few ms on hardware). Do not file latency against the emulator.
- Playback `dumpsys gfxinfo` shows janky frames on the emulator's host-GPU renderer; it does not reproduce a user-visible stall on hardware. Judge jank by video, not only by gfxinfo.
- `AudioTrack` dead-object recovery (the engine rebuilding after the audio server restarts) cannot be triggered on API 36; it is covered by reading and unit tests only.
- `adb shell input keyevent` events come from virtual device -1, which Android does not treat as a hardware keyboard, so Meta+/ and any `hasKeyboard` branch need an AVD with `hw.keyboard=yes` (the tablet) and key events sent through the emulator console or window.
- `uiautomator dump` shows Compose nodes only where the app set semantics; never treat a missing node as a visual defect.
- `adb shell am start -W` can report a very long `WaitTime` right after a long idle on a busy host; screenshot to verify the frontmost app.
- Screenshots are 1080x2340 on the phone; reduce them before viewing, and tap in pixels.

## Tooling Caveats

- macOS has no `timeout`; background long adb calls.
- Splash capture: `adb -s <serial> shell "am start -n dev.individuation.chiptune/.ui.MainActivity >/dev/null; screencap -p /sdcard/s.png"` then pull; a screencap on the host side of `exec-out` is usually too late.
- The harness blocks a leading `sleep N; cmd`; keep waits short.
- `monkey -p` launches and `am start -W` can wedge a slow emulator; check `pidof` and a screenshot.
- Never run a test-running fixer on an emulator another worker is using; give each its own.
- A verification build should come from a clean checkout; the debug build stamp's trailing `+` means uncommitted changes.

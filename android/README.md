# Chiptune for Android

Jetpack Compose port of the iOS app in the parent directory. One `:app` module,
package `dev.individuation.chiptune`, minSdk 26, targetSdk 36, compileSdk 37.
It reads and writes the same `.chipsong` files as iOS, and its WAV export is
bit-identical to iOS's.

## Architecture

```
app/src/main/java/dev/individuation/chiptune/
  core/      pure Kotlin, no android.* imports (enforced by CorePurityTest)
    model/     Song, patterns, tracks, presets, SongCodec (strict .chipsong JSON)
    audio/     ChipCore (the synth and sequencer), WavExport, PcmWriteLoop
    store/     SongStore (files/Songs/<UUID>.json), KeyValueStore
    studio/    Studio: the state owner (selection, playback, autosave, undo,
               import/share/export, errors), plus EditorShortcut and key routing
    text/      grapheme-aware name handling
  platform/  Android glue: AudioTrack output with audio focus and
             becoming-noisy handling, SharedPreferences, FileProvider sharing,
             song import, hardware-key mapping, Meta+/ shortcut groups
  ui/        Compose: AppRoot, editor, arrangement, instrument, songs, export,
             layout (phone vs tablet rules), theme
```

`core/` is a straight port of the Swift: `Studio` talks to the platform only
through small interfaces (`AudioOutput`, `Scheduler`, `KeyValueStore`), so the
whole editor is unit-tested on the JVM with fakes. iOS is the source of truth:
when the two disagree, the Kotlin changes.

## Build

Use JDK 17; the default JDK 23 is unverified.

```sh
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home
cd android
./gradlew --no-daemon test lint assembleDebug
```

`local.properties` (gitignored) must point at the SDK: `sdk.dir=/Users/<you>/Library/Android/sdk`.

## Tests

`./gradlew test` runs 873 JVM unit tests (all green at the last count):

| Area | Tests |
| --- | --- |
| `core/studio` (Studio, undo, shortcuts, key routing, policies) | 373 |
| `ui/layout` (phone/tablet rules, screenshot modes) | 185 |
| `core/model` (codec, presets, names) | 149 |
| `core/audio` (ChipCore, WAV export, golden file) | 98 |
| `platform` (key mapper, incoming intents, sharing, list encoding) | 31 |
| `core/store` | 24 |
| `core/text` | 11 |
| root (`CorePurityTest`) | 2 |

There is no instrumented (`androidTest`) suite; the on-device checks are the
journeys in `../docs/qa/APPMAP-android.md`.

### Shared fixtures and the golden WAV

The golden WAV and `.chipsong` fixtures are shared with iOS and live in
`../Tests/Fixtures`; the unit tests read them in place as test resources.
`golden-demo.wav` is the contract: the Kotlin engine renders the demo song and
the output must match it **byte for byte**. `song-fixtures.json` lists every
`song-*.chipsong` and whether it decodes, with facts about the normalized song.
`SharedFixtureTest` (here) and `Tests/SharedFixtureTests.swift` (iOS) assert the
same manifest.

## Emulators

Two AVDs, kept running by whoever started them. Never kill an emulator you did
not start, and always pass `-s <serial>`:

| AVD | Serial | Notes |
| --- | --- | --- |
| `Chiptune_Audio_API_36` | `emulator-5580` | phone |
| `Chiptune-Tablet-API36` | `emulator-5582` | tablet, `hw.keyboard=yes` in its `config.ini` (needed for Meta+/) |

Other serials on this machine (for example `emulator-5554`) belong to other projects.

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices
$ADB -s emulator-5580 install -r app/build/outputs/apk/debug/app-debug.apk
$ADB -s emulator-5580 shell am start -n dev.individuation.chiptune/.ui.MainActivity
```

The emulator has no FastMixer, so output latency is about 180 ms there; a real
device is a few ms. See `../docs/qa/APPMAP-android.md` for the other emulator caveats.

## Debug screenshot extras

Debug builds (never release) stage a screen from an intent extra, the
counterpart of iOS's `-shot*` launch arguments. The value must be truthy
(`YES`, `true` or a non-zero number); if several are given the first in this
order wins.

```sh
$ADB -s emulator-5580 shell am start -n dev.individuation.chiptune/.ui.MainActivity --es shotEditor YES
```

| Extra | Shows |
| --- | --- |
| `shotArrangement` | the arrangement |
| `shotEditor` | the instrument editor |
| `shotLibrary` | the song library |
| `shotExport` | the export sheet |
| `shotPlaying` | the editor with playback running |
| `shotPatternB` | the second pattern |

## Launcher icon

The adaptive icon is all vectors: `res/drawable/ic_launcher_background.xml`
(`#0D0D17`), `ic_launcher_foreground.xml` (the bars in the channel colours) and
`ic_launcher_monochrome.xml` (themed icon). The foreground also serves as the
Android 12+ splash icon (`values-v31/themes.xml`). The two bar layers are
generated from measured geometry by `Tools/icon/gen-vector-icon.py <res dir>`;
the XML is the source of truth, so only re-run it to change the design. minSdk
26 means no legacy PNG launcher icons are needed. `docs/play-store/icon-512.png`
is the iOS 1024 tile downscaled.

## Release build and signing

```sh
export CHIPTUNE_KEYSTORE=~/chiptune-upload-key.jks
export CHIPTUNE_KEYSTORE_PASSWORD=...
export CHIPTUNE_KEY_ALIAS=chiptune-upload
export CHIPTUNE_KEY_PASSWORD=...
export CHIPTUNE_VERSION_CODE=1
./gradlew --no-daemon bundleRelease      # app/build/outputs/bundle/release/app-release.aab
```

The four signing values can instead go in the gitignored `keystore.properties`
(same names as keys). Without them the release build still assembles, unsigned,
with a warning. `CHIPTUNE_VERSION_CODE` sets the version code (default 1);
`versionName` stays 1.0. Release is minified with R8. Play submission steps are
in `../docs/play-store/submission.md`.

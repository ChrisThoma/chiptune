# Chiptune for Android

Jetpack Compose port of the iOS app in the parent directory. One `:app` module;
platform-free code lives in `dev.individuation.chiptune.core` (no `android.*`
imports, enforced by `CorePurityTest`).

## Build

Use JDK 17; the default JDK 23 is unverified.

```sh
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home
cd android
./gradlew --no-daemon test assembleDebug lint
```

`local.properties` (gitignored) must point at the SDK: `sdk.dir=/Users/<you>/Library/Android/sdk`.

## Install and launch

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices
$ADB -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk
$ADB -s <serial> shell am start -n dev.individuation.chiptune/.ui.MainActivity
```

Always pass `-s <serial>` when more than one device is attached.

## Shared fixtures

The golden WAV and `.chipsong` fixtures are shared with iOS and live in
`../Tests/Fixtures`; the unit tests read them in place as test resources.
`song-fixtures.json` lists every `song-*.chipsong` and whether it decodes,
with facts about the normalized song. `SharedFixtureTest` (here) and
`Tests/SharedFixtureTests.swift` (iOS) assert the same manifest, and iOS is
the source of truth: when the two disagree, the Kotlin codec changes.

## Release signing

Set `CHIPTUNE_KEYSTORE`, `CHIPTUNE_KEYSTORE_PASSWORD`, `CHIPTUNE_KEY_ALIAS` and
`CHIPTUNE_KEY_PASSWORD` (or put them in the gitignored `keystore.properties`).
Without them the release build is unsigned. `CHIPTUNE_VERSION_CODE` sets the version code.

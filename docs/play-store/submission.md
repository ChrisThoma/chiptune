# Play Store submission: Chiptune 1.0

Checklist of what is left before a Play Console listing goes live, in the
style of `AppStore/CHECKLIST.md`. Listing copy and the items that need a
decision are in `listing-draft.md` (**Needs Chris**). Status: the Android port
is feature-complete through Phase 8 and builds; the listing and a draft
internal build are on Play (see Status). Do not submit anything until Chris
has worked through the items left for him.

## Status (2026-10-16)

Done through the Play Developer API (`android/Tools/play/play_sync.py`,
key `~/.config/google-play/publisher.json`):

- App record exists; listing title, short and full description, contact email
  and website pushed from `android/fastlane/metadata/android/en-US/`.
- Icon, feature graphic, 6 phone and 6 10-inch tablet screenshots uploaded
  (`android/Tools/play/shoot.sh`, `make_feature_graphic.py`).
- Upload key created: `~/.config/google-play/chiptune-upload.jks`, alias
  `chiptune-upload`, password in the macOS Keychain item "Chiptune Play
  upload key" (store and key password are the same). SHA-256
  `8B:BF:0E:AE:...:4D:0B`. Back up the `.jks` and the password together.
- versionCode 2 (1.0) rolled out on Internal testing to the "VTqq" email
  list (3 testers); a "Friends" list (2) exists but is not selected. This
  build adds the song menu's "Privacy policy" row
  (`EditorEffects.PRIVACY_URL`). Until review, testers see the temporary
  name "dev.individuation.chiptune (unreviewed)".
- Privacy policy updated for Android backup, MIDI and the Play rating prompt
  (individuation `5b27cd1`, live).

Done in Play Console (Chrome, 2026-10-16): privacy policy URL, sign-in
details (nothing restricted), ads (none), target audience (13-15, 16-17, 18+),
Data safety (no data collected or shared), government / financial / health
(none), category Music & Audio, content rating, Advertising ID (No; the
versionCode 2 merged release manifest has no `AD_ID` permission). App content
shows nothing needing attention. Price: Paid, with per-country prices set.

Production (2026-10-16): all 173 countries / regions; release "2 (1.0)"
from versionCode 2, full rollout, notes "Initial release.". One warning,
not blocking: no native debug symbols uploaded. Catalog access preferences
left unset (included in catalog exports by default).

**Submitted for review 2026-10-16** (10 changes: production release,
countries, store listing, declarations). Google says reviews typically take
up to 7 days. Managed publishing is off, so the app goes live as soon as
review passes.

Left:

1. Real-phone pass on the internal build (checks in step 5 below); skipped
   before submission.
2. After launch: update individuation.dev/projects/chiptune and the README
   with the Play link.

Production access: the account is an organization account, so the
12-tester, 14-day closed test rule for new personal accounts does not apply;
the Production track is not locked behind closed testing.

## Remaining before submission

1. **Create the upload key.** Play needs a keystore this project generates and
   keeps itself. Run once, outside the repo:

   Done 2026-10-16; see Status. The command used, for a replacement:

   ```sh
   keytool -genkeypair -keystore ~/.config/google-play/chiptune-upload.jks \
     -storetype PKCS12 -alias chiptune-upload -keyalg RSA -keysize 2048 -validity 10000
   ```

   Keep the `.jks` and its passwords in a password manager, never in the repo.
   Enroll in Play App Signing at the first release; Play then re-signs with its
   own key and a lost upload key can be replaced. Back it up regardless.

2. **Play Console app setup.** Create the app, set category, contact email and
   privacy policy URL, answer the declarations: ads (none), target audience
   (not primarily children), government / COVID-19 / news apps (no), and fill
   in Data safety per `listing-draft.md`.

3. **Content rating questionnaire.** Chiptune has no user-generated content
   shown to others, no violence, sexual content, gambling or communication, and
   no network access:

   | Question | Answer |
   | --- | --- |
   | Violence | None |
   | Sexuality | None |
   | Language (profanity) | None |
   | Controlled substances | None |
   | Gambling (simulated or real) | None |
   | User-generated content | No (songs are the user's own files; sharing is through the system share sheet) |
   | Shares user location | No |
   | Personal information shared with third parties | No |
   | Digitally purchased randomized items | No |
   | Unrestricted internet access | No (no `INTERNET` permission) |

   Expected result: Everyone.

4. **Screenshots and feature graphic.** See "Screenshot set" below.

5. **Internal testing track.** Upload the signed `.aab` to Internal testing
   first (live in minutes, no review). Check on a real phone: fresh install and
   the starter song `First Loop`; play, edit, undo; arrangement and SONG
   playback; export a WAV with Share and with Save to device and open the
   saved file; open a `.chipsong` from Files and from Gmail; a phone call and
   unplugged headphones during playback; process kill and relaunch restores the
   last song; rotation mid-edit; a large system font. Then a tablet pass,
   portrait and landscape, with a hardware keyboard (Ctrl chords, Meta+/).

6. **Closed testing.** Promote the same build to a Closed testing track and
   keep it open for the 12-tester, 14-day requirement. Watch the pre-launch
   report for crashes.

7. **Production release.** After production access: create a Production
   release from the same `.aab`, release notes "Initial release.", roll out
   (a staged rollout 20% -> 50% -> 100% costs nothing).

## Signing and building

The release signing config in `android/app/build.gradle.kts` reads the key
from `CHIPTUNE_KEYSTORE`, `CHIPTUNE_KEYSTORE_PASSWORD`, `CHIPTUNE_KEY_ALIAS`
and `CHIPTUNE_KEY_PASSWORD` environment variables, then from the gitignored
`android/keystore.properties` using the same four names as keys. With neither,
the release build assembles unsigned with a Gradle warning, which is fine for
local R8 and size checks but cannot be uploaded.

```sh
cd android
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home
export CHIPTUNE_KEYSTORE=~/.config/google-play/chiptune-upload.jks
export CHIPTUNE_KEYSTORE_PASSWORD="$(security find-generic-password -a chiptune-upload -s 'Chiptune Play upload key' -w)"
export CHIPTUNE_KEY_ALIAS=chiptune-upload
export CHIPTUNE_KEY_PASSWORD="$CHIPTUNE_KEYSTORE_PASSWORD"
export CHIPTUNE_VERSION_CODE=1
./gradlew --no-daemon bundleRelease
cd .. && python3 android/Tools/play/play_sync.py --bundle android/app/build/outputs/bundle/release/app-release.aab --track internal
```

The signed bundle lands at `android/app/build/outputs/bundle/release/app-release.aab`.
Play takes only the App Bundle. **Never create or commit a keystore in the
repo.** JDK 17 is required; the default JDK 23 is unverified.

`versionCode` reads `CHIPTUNE_VERSION_CODE` (default 1). Play requires every
upload to be strictly higher than the last, and nothing increments it
automatically, so bump it per upload. `versionName` stays 1.0 for the whole 1.0
release. Whether it should track the iOS build number is Chris's call.

targetSdk 36 meets Play's target-API requirement for new apps (compileSdk 37).

## Store graphics

| Asset | File | Notes |
| --- | --- | --- |
| Hi-res icon 512x512 | `docs/play-store/icon-512.png` | iOS 1024 tile downscaled; full square, no baked-in corners |
| Feature graphic 1024x500 | to make | no alpha; tagline needs Chris |

The launcher and splash icon are vectors (`android/Tools/icon/gen-vector-icon.py`).

## Screenshot set

None captured. Debug builds stage the same screens as the iOS shots through
intent extras (never in release):

```sh
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB -s emulator-5580 shell am start -n dev.individuation.chiptune/.ui.MainActivity --es shotPlaying YES
$ADB -s emulator-5580 exec-out screencap -p > shot.png
```

Extras: `shotPlaying` (editor with playback), `shotPatternB` (second pattern),
`shotEditor` (instrument editor), `shotArrangement`, `shotLibrary`,
`shotExport`. Clear app data between shots for a clean starter song
(`adb shell pm clear dev.individuation.chiptune`).

| Device type | Source | Play's rule |
| --- | --- | --- |
| Phone | `emulator-5580` (1080 x 2340) | 2-8, sides 320-3840 px, long side at most 2x the short |
| 7-inch tablet | not set up; a 7" AVD or resized tablet AVD is needed | optional but recommended |
| 10-inch tablet | `emulator-5582` (`Chiptune-Tablet-API36`) | 4-8 for the larger-screen tiers, sides 1080-7680 px, 16:9 or 9:16 |

Check the tablet AVD's resolution against Play's size rules before capturing;
phone shots may need cropping or framing to meet the 2x aspect limit. The iOS
shots live in `docs/screenshots/` and `AppStore/screenshots-store/`; their
captions are Chris's and are not reused automatically.

## Data safety and privacy

- Data safety form: `listing-draft.md`. Proposed answer: no data collected or
  shared; no `INTERNET` permission.
- Privacy policy: `https://individuation.dev/projects/chiptune/privacy.html`,
  same page as iOS. Confirm it is deployed and suitable for Android.
- Android backs up `files/Songs/` and `chiptune.xml` through Auto Backup and
  device transfer to the user's own Google account; the privacy policy should
  say so.
- No `PrivacyInfo.xcprivacy` equivalent exists on Android; the Data safety
  form is the whole declaration.

# Play Console listing: Chiptune 1.0

Copy for the Play Console fields (pushed to Play 2026-10-16 from `android/fastlane/metadata/`), updated 2026-10-16 from the
current iOS copy (`AppStore/fields.py`: Chris's description, the confirmed
name and subtitle, MIDI export) and checked against the Android code.
Character counts in brackets are the actual lengths; limits are Google
Play's. The text fields here are a copy; the files under
`android/fastlane/metadata/` are what `play_sync.py` sends.

## Still needs Chris

1. **Price.** iOS is $0.99. A paid Play app needs a payments (merchant)
   profile, and an app published free can never become paid, so decide
   before the first production release.
2. **Closed test.** See `submission.md`; the 12-tester, 14-day closed test
   is the long pole.

## App details

| Field | Value |
| --- | --- |
| App name | `Chiptune: A Simple Composer` (same as iOS) |
| Default language | English (United States) - en-US |
| App or game | App |
| Free or paid | Needs Chris 1 |
| Application ID | `dev.individuation.chiptune` |
| Version name / code | 1.0 / 1 (`CHIPTUNE_VERSION_CODE` overrides the code) |
| Category | Music & Audio |
| Tags (up to 5) | Pick in Play Console from its fixed list; choose the music-creation ones |
| Contact email | `mail@individuation.dev` (the address the privacy policy gives) |
| Website | `https://individuation.dev/projects/chiptune/` |
| Privacy policy URL | `https://individuation.dev/projects/chiptune/privacy.html` |
| Ads | No, the app contains no ads |
| Content rating | Everyone (questionnaire answers in `submission.md`) |
| Target audience | 13 and over; not designed for children |

## App name [27]

```
Chiptune: A Simple Composer
```

## Short description [79]

```
Write 8-bit video game music: tap notes into a grid and chain them into a song.
```

Play has no subtitle; this carries the iOS subtitle "Write 8-bit video game
music".

## Full description [1842]

Chris's iOS description with the iPad line made Android and three Android
lines added (hardware keyboard, Save to device, opening song files).

```
Chiptune is a step sequencer for writing music in a style of old game consoles. Simply tap a note, tap a cell in the grid, and it will play sounds from one of four NES-style channels. Chiptune has two pulses, a triangle and noise. Each channel is synthesized live rather than sampled.

Patterns are customizable from 4 to 64 steps and can be chained into an arrangement. This lets a piece go from just a single loop into a full song with intros, verses, choruses, etc.

WRITE
• Compose on a grid of notes with 4 to 64 steps per pattern
• Customize your track to cut notes short or let them ring
• Set the tempo by typing it or nudging it a step at a time
• Easily undo any changes
• With a hardware keyboard, play the grid like a tracker, with Ctrl shortcuts for undo, export and more

SOUND
• Two pulse channels with four pulse widths, from thin and nasal to full square
• A triangle channel ideal for basslines
• Tunable noise for drums like a hi-hat or a low rumble
• Volume, decay, and arpeggio controls per channel, so one channel can fake a chord
• Sounds come with basic presets

ARRANGE
• Create sections with a named pattern and a repeat count
• Loop one pattern while editing or play the whole song
• Add multiple tracks of any sound when four channels aren't enough
• On a tablet, the sound controls sit beside the grid

SAVE AND SHARE
• Songs autosave as you work so you never lose anything
• Duplicate a song to try something slightly different
• Export any song as a WAV file with a seamless loop or with the last notes ringing out
• Export as a MIDI file to keep working on your notes in another music app
• Share an export or save it straight to your device
• Send a song file to a friend, or open one from Files, Gmail or Drive

Chiptune works fully offline and never asks for a subscription. No account, no ads, no tracking.
```

Verified in the Android code: keyboard chords (`core/studio/EditorShortcut.kt`,
`MainActivity.onProvideKeyboardShortcuts`), tablet docked editor (`ui/layout`),
Save to device (`CreateDocument` in `EditorEffects.kt`), WAV and MIDI formats
(`core/audio/WavExport.kt`), opening files (`VIEW`/`SEND` filters in
`AndroidManifest.xml`), offline (no `INTERNET` permission in the manifest).

## Release notes for 1.0 [500 max] [16]

```
Initial release.
```

## Feature graphic tagline

`Write the music old game consoles made.` (the iOS promo text's first
sentence). 1024 x 500, no alpha. Leave the price off it.

## Store listing graphics

| Asset | Status |
| --- | --- |
| App icon 512 x 512 | `docs/play-store/icon-512.png` |
| Feature graphic 1024 x 500 | to make |
| Phone screenshots (2-8) | to capture |
| 7-inch and 10-inch tablet screenshots | to capture |

## Data safety

Verified against the manifest, the Gradle dependencies and the code:

- No `INTERNET` permission, so the app cannot open a socket. No analytics,
  ads, crash reporting or networking libraries.
- `com.google.android.play:review` (in-app review card after a milestone
  share) talks to the Play Store app on the device and sends nothing from
  Chiptune. Nothing to declare for it.
- Songs live in `files/Songs/`; preferences in SharedPreferences. Auto Backup
  and device transfer copy them to the user's own Google account, which Play
  does not count as collection: the developer never receives it.

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | No |
| Is all of the user data collected encrypted in transit? | Not asked once the answer above is No |
| Account deletion | Not applicable: no accounts |

Same underlying fact as the iOS App Privacy answer ("Data Not Collected").

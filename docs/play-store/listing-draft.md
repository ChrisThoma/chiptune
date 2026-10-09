# Play Console listing draft: Chiptune 1.0

Draft only. Nothing here has been entered in Play Console. Copy is derived from
the iOS listing (`AppStore/LISTING.md`) and the README, checked against the
Android code. Character limits are Google Play's.

## Needs Chris

1. **Price.** iOS is $0.99 paid. Play can do the same, but a paid app needs a
   payments (merchant) profile on the developer account, and an app published as free
   can't be changed to paid later, so decide up front: $0.99 paid, or free.
2. **Content rating.** Expected "Everyone" (no violence, sexuality, language,
   substances, gambling, user-generated content sharing with others, location or
   network access), same as iOS's 4+. Chris runs the questionnaire; answers are
   in `submission.md`.
3. **Data safety.** Proposed answer: no data collected or shared (below).
   Confirm, in particular the in-app review library (see Data safety).
4. **Privacy policy URL.** iOS uses
   `https://individuation.dev/projects/chiptune/privacy.html`
   (`AppStore/PRIVACY.md`, `AppStore/LISTING.md`). The page lives in the
   `individuation` repo, not this one, and this pass did not check that it is
   deployed or that its text is right for Android (it should not mention iOS
   only, and may want a line that Android's backup can carry songs to the
   user's own Google account). Confirm the URL resolves and the wording.
5. **Contact email and support URL.** iOS support URL is
   `https://individuation.dev/contact/` (also what the app's Support link
   opens). Play needs a contact email; the other Chris project uses
   `christhoma@proton.me`. Pick one.
6. **Store category and tags.** Proposed: Music & Audio. Tags are Chris's pick.
7. **Closed test.** A new personal developer account needs at least 12 testers
   opted in to a closed test for 14 continuous days before it can apply for
   production access. Line up testers early.
8. **Upload key.** Not created yet (see `submission.md`).
9. **Screenshots and feature graphic.** None captured yet (see
   `submission.md`). Captions are Chris's.
10. **Short description and feature-graphic line.** Drafts below, not approved.
11. **versionCode.** Counts from 1 on its own unless told otherwise
    (`CHIPTUNE_VERSION_CODE`); Chris to say whether it should track the iOS
    build number.

## Identity

| Field | Value |
| --- | --- |
| Application ID | `dev.individuation.chiptune` |
| Version name | 1.0 |
| Version code | 1 (`CHIPTUNE_VERSION_CODE` overrides it at build time) |
| Default language | English (United States) |
| App category | Music & Audio (proposed) |
| Content rating | Everyone (expected) |
| Price | Needs Chris 1 |
| Privacy Policy URL | Needs Chris 4 |

## App name [30]

```
Chiptune
```

Same as iOS. Check the name in Play Console before settling; iOS keeps
`Chiptune Sequencer` and `Chiptune: Step Sequencer` as fallbacks.

## Short description [80] (76 chars)

```
Write 8-bit game music: tap notes into a grid and chain patterns into songs.
```

Play has no subtitle; this line plays the role of iOS's "Write 8-bit game music".

## Full description [4000]

Newlines paste as typed in Play Console, so every paragraph is one line.

```
Chiptune is a step sequencer for writing the kind of music old game consoles made. Tap a note, tap a cell in the grid, and it plays on one of four NES-style channels: two pulses, a triangle and noise, synthesized live rather than sampled.

Patterns run from 4 to 64 steps and chain into an arrangement, so a piece can have an intro, a verse and a chorus instead of staying one loop.

WRITE
• A grid of steps and notes, 4 to 64 steps per pattern
• Cut a note short, or let it ring
• Set the tempo by typing it or nudging it a step at a time
• Undo anything, including clearing a pattern

SOUND
• Two pulse channels with four pulse widths, from thin and nasal at 12% to the full square at 50%
• A triangle channel for basslines
• Tunable noise for drums, anywhere from a tight hi-hat to a low rumble
• Volume, decay and arpeggio per channel, so one channel can fake a chord
• Presets to start from, with every control still yours to move

ARRANGE
• Sections that name a pattern and a repeat count
• Loop one pattern while you work on it, or play the whole song
• Add more tracks of the same kind when four channels aren't enough
• On a tablet, the sound controls sit beside the grid instead of in a sheet

PHONE, TABLET AND KEYBOARD
• Works on phones and tablets
• With a hardware keyboard, play the grid like a tracker, with Ctrl shortcuts for undo, new song, export and more (press Meta+/ for the list)

SAVE AND SHARE
• Songs autosave as you work, and the app reopens to the last one you were working on
• A library of everything you've written. Duplicate a song to try a variation
• Export any song as a WAV file, as a seamless loop or with the last notes ringing out. Share it or save it straight to your device
• Share a song file with a friend, or open one from Files, Gmail or Drive

Chiptune works fully offline. No account, no ads, no tracking.
```

Derived word for word from the iOS description, with three changes: "On iPad"
became "On a tablet", the iOS "never asks for a subscription" line was cut
(true, but the paid-or-free decision is open), and the PHONE, TABLET AND
KEYBOARD block and the Android save and open options were added. Verified:

- Tablet docked editor and hardware-keyboard chords: `ui/layout`,
  `core/studio/EditorShortcut.kt`, `MainActivity.onProvideKeyboardShortcuts`.
- Save to device (`CreateDocument`, `audio/wav`) and Share: `EditorEffects.kt`.
- Opening from Files, Gmail or Drive: `VIEW` and `SEND` filters in
  `AndroidManifest.xml` (`content` and `file` schemes, `application/json` and
  `application/octet-stream`).
- "No account, no ads, no tracking", offline: the merged release manifest
  declares no `INTERNET` permission.
- No iOS-only wording ("NES" is kept as in the iOS listing).

## Feature graphic [1024x500]

Not made. Suggested tagline, the iOS promo text's first sentence: "Write the
music old game consoles made." Needs Chris to approve; if the price appears on
it, it must match the Play price.

## Store listing graphics

| Asset | Status |
| --- | --- |
| Hi-res icon 512x512 | `docs/play-store/icon-512.png`, the iOS 1024 tile downscaled (full square, no baked-in rounding) |
| Feature graphic 1024x500 | to make |
| Phone screenshots (2-8) | to capture |
| 7-inch and 10-inch tablet screenshots | to capture |

## Data safety section

Verified against the manifest, the Gradle dependencies and the code:

- **No network access.** The merged release manifest declares no `INTERNET`
  permission (its only permission is the signature-protected
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` AndroidX adds), so the app cannot
  open a socket. No analytics, ad, crash-reporting or networking libraries.
- **One Google dependency to confirm:** `com.google.android.play:review`
  (in-app review, `EditorEffects.requestReview`). It talks to the Play Store
  app, not to a server of ours, and sends nothing from Chiptune; it asks Play
  to decide whether to show its review card after a milestone share. Declare
  nothing for it unless Play's form says otherwise. Needs Chris 3.
- **Data stored on the device.** Songs as `files/Songs/<UUID>.json`; the last
  open song id and the review-prompt counters in SharedPreferences. Exported
  WAVs and shared song files go where the user sends them; the app does not
  record that.
- **Backup is not collection.** `backup_rules.xml` and
  `data_extraction_rules.xml` include the song library and `chiptune.xml` in
  Android Auto Backup and device transfer; the cache is excluded. The system
  uploads it to the user's own Google account backup, and the developer never
  receives it. The same framing was settled for the other Chris app.
- No account, no advertising ID, no location, no microphone, no contacts.

Recommended form answers:

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | No |
| Is all of the user data collected encrypted in transit? | N/A (nothing leaves the device) |
| Do you provide a way for users to request that their data is deleted? | N/A (nothing reaches the developer; on-device songs are cleared from Settings -> Apps -> Chiptune -> Storage) |

Same underlying fact as iOS's App Privacy answer ("No, we do not collect data
from this app", `AppStore/PRIVACY.md`).

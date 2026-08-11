# iPad: what's done and what's left

Written on the `ipad-layout` branch. The first commit
(`Lay the editor out natively on iPad`) laid the foundation — the device
family, the orientations, and the metrics layer everything else hangs off —
and items 1 to 4 below have since been built on it.

Nothing here is a launch blocker for the iPhone build already on the store.

---

## What `ChipLayout` holds

`Sources/Views/Layout.swift` keeps a `ChipLayout` in the environment: every
size that differs between an iPhone window and an iPad one, in one place.
`ChipLayout.resolve` takes the window size and the horizontal size class,
because neither decides alone — the class picks the numbers, the proportions
pick the arrangement:

- **Compact width** (iPhone, and an iPad in a narrow Split View slice) gets
  the values the views used before the branch, so an iPhone build renders
  exactly as it did.
- **Regular width** gets larger cells, a wider gutter, taller keys, and a cap
  on how far the chrome rows are allowed to spread.
- **Regular, wider than tall, and wide enough** additionally moves the
  keyboard into a 400pt column beside the grid, with the selected track's
  sound controls docked under the keys.

`Tests/LayoutTests.swift` pins the resolve rules, including the ones that are
invisible until you hold the wrong device: a Split View slice must not get
iPad cells, a square window must not split, and a short wide window must not
split either.

---

## 1. Sheets — done

The instrument editor was the one that mattered: it's opened and closed
constantly while writing a part, and as an iPad form sheet it covered the grid
being edited against every time.

- **Landscape docks it** into the keyboard column, which was otherwise mostly
  empty under the keys. The column now reads as an instrument panel rather
  than a keyboard with space around it.
- **Portrait anchors it to the track header as a popover**, so the grid stays
  visible and the controls sit beside what they change.
- **The phone keeps its sheet.** `.presentationCompactAdaptation(.sheet)`
  adapts the popover back at compact width.

The remaining sheets — Songs, Arrangement, Export — no longer ask for
`.medium` detents at regular width. Detents are a phone idiom; on an iPad they
shrink a form sheet to a small box adrift in a large screen, and without them
the sheet takes the standard form-sheet size its content was laid out for.

One trap worth knowing: a popover hands its *content* a compact horizontal
size class whatever the window is, so a view inside one can't ask the
environment how it's being presented. The presenting side reads it off
`ChipLayout` and passes it down.

## 2. Chrome spread — done

`TransportBar` and `PatternBar` stop widening at 720pt and centre. At 393pt
the row read as two groups; at 1210pt it read as two groups separated by half
a metre of nothing, with the play button and the tempo it sets at opposite
ends of the window. In the side arrangement the chrome rides above the grid
column rather than the whole window, so it stays over what it acts on.

## 3. Hardware keyboard, trackpad, pointer — done

Space plays and stops, arrows walk a cursor around the grid, delete empties a
cell, and the letter row writes notes — `A` is C, `W` is C sharp, up to `K`,
the layout every DAW borrowed. `Z` and `X` move the octave. Typing and
deleting both step down afterwards, the way a tracker does; the arrows stop at
the edges instead. The cursor stays hidden until a key is pressed.

Grid cells, track headers and piano keys have hover effects for a trackpad.

Two things learned the hard way, both recorded in `HardwareKeys.swift`:

- `focusable()` plus `onKeyPress` needs the view to hold SwiftUI focus, and on
  iOS this editor never takes it. Keys go through the responder chain instead.
- The iOS simulator only delivers hardware keys with **I/O > Keyboard >
  Connect Hardware Keyboard** ticked, and it is off per-device by default. A
  plain text field not receiving typed characters is the quickest way to tell
  that apart from a bug in the app.

## 4. App Store metadata and screenshots — done

- `MARKETING_VERSION` is 1.1 and `CURRENT_PROJECT_VERSION` is 3.
- `AppStore/shoot.sh` takes an orientation and captures the iPad set in
  landscape, which is the layout that shows the iPad build is a real one. It
  also captures opaque PNGs now, so the alpha channel no longer needs
  stripping by hand.
- `AppStore/screenshots/ipad-13/` is a current four-shot landscape set at
  2752×2064, `screenshots/iphone-6.9/` a portrait one at 1320×2868, and
  `make_deliver.py` ships both sets.
- `REVIEW-NOTES.md`, `CHECKLIST.md`, `SCREENSHOTS.md`, `LISTING.md`,
  `SUBMISSION.md` and `README.md` all describe an iPhone-and-iPad app.

The iPhone set has been reshot. It held 1206×2622 files — the 6.3" size,
from the wrong simulator at some point before this branch — and App Store
Connect would have refused them. `screenshots/iphone-6.9/` is now a 1320×2868
set off an iPhone 17 Pro Max. The iOS 26 dimming artifact that makes the iPad
set unusable does not appear on a phone: the sheet shots were checked by eye,
and the dimming is even across the screen. Only the iPad set needs iOS 17.

Both sets pack through `make_deliver.py` into `AppStore/fastlane/`.

## 4a. The version the archive carries — fixed

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` were 1.1 and 3, and the
archive came out **1.0 (1)** anyway. `GENERATE_INFOPLIST_FILE` is off, so
`Sources/Info.plist` is what ships, and XcodeGen writes that file from
`info.properties`. Whatever isn't listed there gets XcodeGen's own default —
which for those two keys is 1.0 and 1. The build settings were never read.

Both keys are now `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` in
`project.yml`, so the settings are the single source again.

It failed silently and would have been caught by App Store Connect refusing
1.0 as a duplicate of the shipped build. **Read the version out of the
archive, not out of `project.yml`**, whenever it matters:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  <archive>/Products/Applications/Chiptune.app/Info.plist
```

The same archive was checked for `UIDeviceFamily`, which decides which
screenshot sets App Store Connect demands: it reports `[1, 2]`.

Note that `Chiptune.xcodeproj` and `Sources/Info.plist` are both generated and
both git-ignored, so this is only ever fixed in `project.yml`. Regenerate with
the team exported, or the project gets no signing team:

```sh
CHIPTUNE_TEAM_ID=<team> xcodegen generate
```

## 4b. Which build is this? — the app says so

The `…` menu ends with the build's own identity:

```
Built Aug 11, 2026
ccb90be
Version 1.1
```

The commit leads because it's the part worth trusting. A build phase stamps it
into the *built* `Info.plist` under `ChiptuneGitCommit`, alongside
`ChiptuneBuildDate`, so it names the code that was actually compiled — whereas
the version number is typed into `project.yml`, only changes when someone
remembers, and is routinely shared by builds that differ. The date saves a
lookup when telling last week's build from today's. Tapping the row copies
`1.1 · ccb90be`, which is what a bug report needs.

`CFBundleVersion` is deliberately absent. The upload counter is how App Store
Connect tells two uploads apart; on a device it is bookkeeping, and putting it
in the row made the row read like bookkeeping.

Nothing reports whether the tree had uncommitted edits when the build ran. It
is a real distinction, but on any build someone other than the developer is
holding the tree was clean, so the flag would be noise in every case where it
is read.

`BuildStamp` leaves a line out rather than showing a placeholder. A build made
outside a git checkout has no commit — a source tarball is a legitimate way to
build this — and a dash where a hash should be tells the reader nothing they
can act on. A `$(…)` that never expanded is treated as absent for the same
reason.

Two things about the phase were checked rather than assumed, since both are
ordering questions the build system doesn't promise:

- The stamp survives into the archive, which is the build that ships. It's
  written after the plist is processed, and
  `testTheShippingBundleCarriesACommitAndABuildDate` fails if that stops being
  true.
- A signed archive still passes `codesign --verify --deep --strict`, so the
  edit lands before the bundle is sealed rather than breaking it. A simulator
  build fails that check with or without the phase — an artifact of building
  with `CODE_SIGNING_ALLOWED=NO` — so verify an archive, not a simulator
  build.

The phase runs on every build by design: a stamp refreshed only when something
else changed is one that eventually names the wrong commit. Xcode emits a note
saying so, which is the expected cost.

## 5. Coverage this branch does not have

The layout tests assert the resolve rules and the key-press mapping, which are
the parts with logic in them. They assert nothing about what the views do with
the result, and there are no snapshot tests in this project to catch it. The
things most likely to break silently:

- A rotation while a sheet is open, or while a rename field has focus. The
  docked/popover switch now rides on the same path: a rotation into landscape
  closes the popover so the same controls aren't shown twice.
- Split View and Slide Over transitions, which change the size class under a
  running app — the same path as rotation, but the app is not frontmost when
  it happens.
- Stage Manager. The hole here is closed rather than just untested:
  `resolve` no longer splits on `width > height` alone, and requires the
  window to be wide enough that the grid gets four usable columns beside the
  400pt keyboard. What is still unmeasured is exactly where the size class
  itself flips to compact on a resized window.
- The hardware key handling holds first responder for the whole app. It hands
  the keyboard back to the song name field and to alert text fields, and takes
  it again when they're done, but that hand-off is driven by SwiftUI's update
  cycle rather than by a test.

## Notes for whoever shoots screenshots next

Three simulator behaviours cost real time to find, all written up in
`AppStore/SCREENSHOTS.md`:

- `simctl` can't rotate a device, and the Device > Orientation menu items
  accept an AppleScript click, report success, and do nothing. Cmd-Left works.
- A landscape capture comes out portrait-shaped with the content on its side;
  `simctl` always writes the display's native framebuffer.
- On the iOS 26 simulators a sheet's dimming layer covers about two thirds of
  a 13" screen and leaves the rest at full brightness. It is a simulator
  artifact — iOS 17.5 renders the same build correctly — but it photographs
  as a rendering bug, so shoot the iPad set on iOS 17.

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

## 4. App Store metadata and screenshots — mostly done

- `MARKETING_VERSION` is 1.1 and `CURRENT_PROJECT_VERSION` is 3.
- `AppStore/shoot.sh` takes an orientation and captures the iPad set in
  landscape, which is the layout that shows the iPad build is a real one. It
  also captures opaque PNGs now, so the alpha channel no longer needs
  stripping by hand.
- `AppStore/screenshots/ipad-13/` is a current four-shot landscape set at
  2752×2064, and `make_deliver.py` ships both sets.
- `REVIEW-NOTES.md`, `CHECKLIST.md`, `SCREENSHOTS.md`, `LISTING.md`,
  `SUBMISSION.md` and `README.md` all describe an iPhone-and-iPad app.

**Still to do before uploading:** the iPhone screenshots on disk are
1206×2622, which is the 6.3" size, not the 6.9" one App Store Connect asks
for. They were shot on the wrong simulator at some point before this branch,
and they will be refused. Reshoot with:

```sh
./AppStore/shoot.sh <6.9-inch-iphone-udid> iphone-6.9
```

Also verify the archive reports `UIDeviceFamily [1, 2]` before uploading; the
device family is what decides which screenshot sets are demanded.

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

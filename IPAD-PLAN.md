# iPad: what's done and what's left

Written on the `ipad-layout` branch, after the first commit
(`Lay the editor out natively on iPad`). That commit is the foundation — the
device family, the orientations, and the metrics layer everything else will
hang off. This file is the follow-on work it deliberately left alone.

Nothing here is a launch blocker for the iPhone build already on the store.
The iPad build is shippable at the end of item 4, not before.

---

## What the first commit did

`Sources/Views/Layout.swift` holds a `ChipLayout` in the environment: every
size that differs between an iPhone window and an iPad one, in one place.
`ChipLayout.resolve` takes the window size and the horizontal size class,
because neither decides alone — the class picks the numbers, the proportions
pick the arrangement:

- **Compact width** (iPhone, and an iPad in a narrow Split View slice) gets
  the values the views used before the branch, so an iPhone build renders
  exactly as it did.
- **Regular width** gets larger cells, a wider gutter, taller keys.
- **Regular and wider than tall** additionally moves the keyboard into a
  400pt column beside the grid. Stacking in an 834pt-tall window left the
  grid a band about three steps deep under a keyboard stretched a metre wide.

`GridView` and `KeyboardView` read their metrics from the environment rather
than hardcoding them. `Tests/LayoutTests.swift` pins the resolve rules,
including the two that are invisible until you hold the wrong device: a Split
View slice must not get iPad cells, and a square window must not split.

---

## 1. The sheets are still phone-shaped

Songs, Arrangement, Instrument and Export all present as iPad form sheets
sized for a phone — a small box in the middle of a large dark screen, with the
editor dimmed behind it. The instrument editor is the worst of them, because
it is the one you open and close constantly while writing a part, and every
open/close cycle covers the grid you are editing against.

Two candidate fixes, and they are not exclusive:

- **Instrument editor as a popover**, anchored to the track header that opened
  it. Keeps the grid visible and puts the controls next to the thing they
  change. `TrackHeader` already owns the `showingEditor` state, so the anchor
  is in the right place; the sheet in `ContentView` (the one the screenshot
  shoot opens) needs the same treatment or a reason not to.
- **Dock the instrument editor into the landscape keyboard column.** There is
  a good deal of empty space under the keys on an 11-inch iPad and a lot more
  on a 13-inch. The selected track's controls living there permanently would
  fill it with the one thing you actually want beside a keyboard, and would
  make the column read as an instrument panel rather than a keyboard with
  space around it.

Whichever way this goes, `ScreenshotMode` drives these sheets from launch
arguments for the App Store shoot. Changing how they present changes what the
shoot captures — check `AppStore/shoot.sh` still produces what it claims.

## 2. The chrome rows spread at iPad widths

`TransportBar` and `PatternBar` use a `Spacer` to push BPM and STEPS to the
trailing edge. At 393pt that reads as two groups; at 1210pt it reads as two
groups separated by half a metre of nothing, with the play button and the
tempo it sets at opposite ends of the window.

Options, roughly in order of how much they change: cap the chrome content at
a maximum width and centre it; or move BPM/STEPS into the same tray as the
transport; or, in landscape, move them into the keyboard column with the
other per-performance controls. Worth deciding alongside item 1, since both
are about what belongs in that column.

## 3. Hardware keyboard, trackpad, and pointer

An iPad is often a keyboard-and-trackpad machine, and a step sequencer is one
of the app types where that changes how it is used, not just how it is
driven.

- Space to play/stop, arrow keys to move the grid selection, letter keys to
  enter notes at the selected step, delete to clear a cell.
- Pointer hover states on grid cells, track headers and keys — SwiftUI gives
  these mostly free, but the plain `.buttonStyle(.plain)` buttons used
  throughout will need `.hoverEffect` or they stay inert under a trackpad.
- Note that the grid cell is currently the only way to enter a note, and it
  takes a tap on a cell after a tap on a key. A hardware keyboard makes a
  faster path obvious, which may in turn change what the on-screen keyboard
  is for.

## 4. App Store metadata and screenshots

`TARGETED_DEVICE_FAMILY` is now `1,2`, so the next upload will be offered as
an iPad app whether or not the listing is ready for it. Before shipping:

- iPad screenshots at the sizes App Store Connect demands — `AppStore/shoot.sh`
  currently drives iPhone simulators only, and its four framings assume the
  stacked layout. Landscape shots of the side-by-side arrangement are the ones
  that show the iPad build is a real one.
- Re-check the review notes in `AppStore/REVIEW-NOTES.md`. The "minimum
  functionality" argument was written about the iPhone build.
- `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` — an iPad layout is a
  feature release, not a build bump.

## 5. Coverage this branch does not have

The layout tests assert the resolve rules, which is the part that has logic in
it. They assert nothing about what the views do with the result, and there are
no snapshot tests in this project to catch it. The things most likely to break
silently, in the order they are likely to break:

- A rotation while a sheet is open, or while a rename field has focus.
- Split View and Slide Over transitions, which change the size class under a
  running app — the same path as rotation, but the app is not frontmost when
  it happens.
- Stage Manager, where the window can be resized to any shape at all,
  including ones narrower than the 400pt keyboard column plus a usable grid.
  `resolve` splits on `width > height` alone once the class is regular, so any
  short, wide, regular-width window gets a grid squeezed into whatever is left
  of it. Where the class actually flips to compact on a resized window is
  worth measuring before guessing at a fix; if there is a gap, the fix is a
  minimum width below which a wide window stacks anyway.

The last one is a real hole in the rules rather than an untested path — it
just needs a measurement before it can be closed.

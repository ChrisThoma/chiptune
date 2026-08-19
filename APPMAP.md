# APPMAP — Chiptune (dev.individuation.chiptune)

A step-sequencer chiptune tracker: songs → patterns → tracks (channels) → steps (notes).

## Launch / install / reset
```
xcrun simctl install <UDID> build/BugHunt/Build/Products/Debug-iphonesimulator/Chiptune.app
xcrun simctl launch --console-pty <UDID> dev.individuation.chiptune
xcrun simctl terminate <UDID> dev.individuation.chiptune
```
No reset-data command exists; songs autosave to the app's Documents. To wipe state: `xcrun simctl uninstall <UDID> dev.individuation.chiptune` then reinstall.
Bundle built once by the orchestrator at `build/BugHunt/Build/Products/Debug-iphonesimulator/Chiptune.app` — subagents only install/launch, never build.

## Screens & navigation
- **Splash** → auto-transitions to **ContentView** (main editor) after ~0.3s (audio engine + last song load).
- **ContentView** (main editor) — root screen, phone: stacked layout (chrome on top, GridView + KeyboardView below). iPad landscape: wideEditor (chrome+grid left, keyboard+InstrumentEditor docked right).
  - **Title bar**: Songs button (♪ icon, opens SongListView sheet) · song name TextField (rename) · Undo/Redo · "…" menu (New song, Duplicate song, Share song file, Export WAV, Clear pattern [destructive, confirms], build-info copy).
  - **TransportBar**: play/stop, opens **ArrangementView** sheet.
  - **PatternBar**: pattern selection/management strip.
  - **GridView**: step grid, one column per track (channel), one row per step (0..patternLength). Tap a cell = toggle note at cursor. Long-press a cell = preview sound. Track header: tap = select+preview, tap again = open **InstrumentEditor** (popover on iPad-docked-off / sheet on phone); mute speaker button; context menu (Duplicate, Delete-destructive, confirms). "+" column adds a track by ChannelKind.
  - **KeyboardView**: on-screen piano-style keys to enter notes into the selected track/step.
- **SongListView** (sheet from Songs button): list of saved songs (autosaved, no manual save). Empty state = ContentUnavailableView. Row tap = open song. Swipe-leading: Duplicate, Rename (alert w/ TextField). Swipe-trailing (no full swipe): Delete (confirms, destructive), Share. Context menu mirrors swipe actions. Toolbar: Close, "+" menu (New song, Import song… via fileImporter for .chipsong/.json).
- **ArrangementView** (sheet from TransportBar): song-level pattern arrangement (order of patterns for playback).
- **InstrumentEditor** (popover/sheet from track header, or docked panel on iPad landscape): per-track sound parameters (index-addressed track).
- **ExportSheet** (sheet from "…" menu Export WAV): renders song to WAV, then hands off to **ShareSheet** (UIActivityViewController) once `studio.exportURL` is set.
- **ShareSheet**: also reachable from song-file share (title menu, SongListView row).
- Deep link: `.chipsong` file open via `onOpenURL` → `studio.importSong(from:)`, queued if studio isn't built yet.
- Screenshot-mode launch args (`-shotArrangement/-shotEditor/-shotLibrary/-shotExport YES`) auto-open the named sheet — useful for reaching a screen without navigating.

## Data / model
- `Song`: name, tempo (BPM), patterns (each with tracks/steps), arrangement, id.
- `Studio` (`@Bindable`, the app's single source of truth): current song, selectedTrack, selectedStep, selectedPattern, playhead, isPlaying/playingPattern, undo/redo (UndoHistory), storageError/exportError/audioError/importError/shareError (each surfaced via `.errorAlert`), exportURL, isExporting.
- `SongStore`: persistence (autosave, `loadAll()`, delete/rename/duplicate).
- Autosave: no explicit Save button; `saveNow()` called on backgrounding (`scenePhase` change) and before opening the song list.
- Undo: `checkpoint()` pattern used before mutations (e.g. mute toggle) to make them one undo step.
- Max tracks: `Chip.maxTracks` (grid scrolls horizontally past that).
- ChannelKind: enum of instrument channel types (pulse1 etc.), each with an accent color (Theme).

## Known edge behaviors worth probing (from reading, not yet verified as bugs)
- Rename TextField / alert commit path via `normalizeSongName()` — rejects blank names.
- `GridCell` distinguishes tap (toggle) vs long-press (preview) via manual gesture arbitration — a documented past bug source.
- Export runs off main thread; sheet sequencing (`showingExport = false; showingShare = true`) on `exportURL` change — potential race if triggered rapidly / double-tapped.
- `docksInstrumentEditor` layout change while popover is open force-closes it — check for stale state after a rotation mid-edit.
- Screenshot-mode launch args read once via `UserDefaults.standard.bool` — normal launches should never see them.

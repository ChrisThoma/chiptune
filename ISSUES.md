# Chiptune Bug Hunt — Turn 3 of 40

## Simulators
| Slot | Name | UDID | Runtime |
|------|------|------|---------|
| SIM-A | BugHunt-Chiptune-A | 1D204662-C1A8-464B-9279-096117C19C01 | iOS 17.5 |
| SIM-B | BugHunt-Chiptune-B | D3B1736B-E8D7-459B-AFAC-7179462C8C06 | iOS 26.5 |

Build: `build/BugHunt/Build/Products/Debug-iphonesimulator/Chiptune.app` (Debug, from HEAD at turn 1)
Bundle ID: dev.individuation.chiptune

## Issues

### #1 — REJECTED — Grid scroll fights itself at pattern boundaries during SONG playback
- Repro tried: 20-step pattern, 2 arrangement sections, SONG mode play, watched boundary crossing. Commit: n/a.
- Verdict: "NOT REPRODUCED... Grid was scrolled to a resting position (steps 04–08) with no visible stutter, misalignment, or double-scroll artifact."

### #2 — REJECTED — Grid cell can stay dimmed after long-press-then-drag-to-scroll
- Repro tried: 1.2s swipe starting on a grid cell, dragging to scroll. Commit: n/a.
- Verdict: "NOT REPRODUCED... screenshot shows all visible cells at full opacity, no cell stuck at 0.6 dim."

### #3 — VERIFIED — Undo coalesces unrelated edits into one step
- Repro: tempo stepper tap, then within 1s a grid note toggle, then one Undo. Commit: 0382e5f.
- Verdict: "FIXED... tempo remains at 124 BPM (the changed value persisted), and 'Pulse 1 step 1' is back to... empty (note reverted)... only the note toggle was undone. Undo button remained enabled afterward, indicating a separate undo step still exists for the tempo change."

### #4 — VERIFIED — Double-tap Export WAV kicks off two overlapping export/share flows
- Repro: double-tap Export confirm, dismiss ShareSheet, wait ~5s. Commit: 0382e5f.
- Verdict: "FIXED. Double-tapping the Export confirm button, then dismissing the resulting ShareSheet, produced no second ShareSheet during a ~5-second wait... nothing stole focus or interrupted interaction."

### #5 — SongListView toolbar (Close, "+") invisible to accessibility tree
- Track: A (UI-flow, SIM-A)
- Repro: Open Songs list. `ui_describe_all` shows nav bar `AXGroup` with zero children, though Close and "+" are visibly rendered and tappable by raw coordinate.
- Expected: toolbar buttons exposed to AX tree (VoiceOver reachable). Actual: not exposed; only coordinate taps work.
- Evidence: scratchpad/songlist.png
- Fix attempt 1: added explicit `.accessibilityLabel`/`.accessibilityIdentifier` to Close button and Add Menu (SongListView.swift:104-124). Commit: 626e9d7.
- Verify 1 verdict: REJECTED — "ui_describe_all on the SongListView shows the nav bar as zero children... ui_find_element with [Close, Add, +, New song] returned []. The fix does not appear to be present in this build."
- Fix attempt 2 (opus, escalated after rejection): switched `.cancellationAction`/`.confirmationAction` → `.topBarLeading`/`.topBarTrailing` (avoids UIBarButtonItem bridging that drops custom a11y metadata); Close label moved to `Text` content; Menu's `Label` swapped for an `Image` with its own `.accessibilityLabel`; added `.accessibilityElement(children: .combine)` on the Menu. Commit: 0382e5f.
- Verify 2 verdict: REJECTED — "nav bar toolbar remains inaccessible... empty AXGroup with zero children... ui_find_element for [Close, Add] returned []. Rest of screen (song rows, swipe actions) fully accessible — isolated to the toolbar."
- Two rejections reached. The nav bar itself reports as an empty AXGroup regardless of label/identifier/placement changes tried — likely a limitation of how this SwiftUI NavigationStack toolbar is hosted (UINavigationBar) vs. the accessibility-tree walker used, not something further app-code changes are likely to fix.
- Severity: S3. Status: BLOCKED.

### #6 — VERIFIED — Song title field overflows and hides Songs/Undo nav buttons
- Repro: New song → tap title field → type a 70+ char name. Commit: 626e9d7.
- Verdict: "FIXED. Accessibility tree confirms the title TextField frame is bounded... does not overlap either the Songs button... or the Undo button... Songs icon, Undo/Redo arrows, and the '…' menu button all remain fully visible and unobstructed."

Inconclusive (not a candidate): Export WAV in-flight feedback — render was too fast (small pattern) to tell if a spinner/disabled state is missing; retest with a heavy pattern in a later wave.

Checked, not bugs: blank-name rename reverts correctly; force-quit/relaunch mid-edit restores state exactly; rapid double-tap Clear Pattern confirm produces only one clear.

### #7 — VERIFIED — WAV export crashes on integer overflow for large renders
- Repro: song near several limits at once (max-length patterns, arrangement filling Chip.maxChain=128, min tempo, 16x loop) traps `UInt32(totalSamples * 2)`. Commit: 191143b.
- Verify method: UI repro impractical within action budget (50+ actions to construct); verified by targeted code review instead of live repro.
- Verdict: "FIXED. Overflow is checked before any UInt32(...) conversion, entirely in Int domain... Both dataByteCount and 36+dataByteCount are checked separately... .failed propagates unmodified through render()'s return value to Studio.export's finish closure, which sets exportError... Normal exports... guard is inert for them — no behavior change for reasonable song lengths."

### #8 — VERIFIED — "New Song" (+) button in SongListView does nothing
- Repro: Songs sheet → "+" → "New song". Commit: 191143b.
- Verdict: "FIXED... editor immediately showed a fresh song titled 'Untitled'... Songs list confirms the song count went from 2 to 3, with the new 'Untitled' entry present and marked OPEN."

S4 reserve (log only, don't chase unless needed to hit 10 — max 2 S4 count toward goal):
- SongListView song titles don't line-clamp at AX-XXXL Dynamic Type (wrap to 8 lines, row balloons). scratchpad/9_songlist_axxxl.png.
- InstrumentEditor half-screen sheet shows almost no controls at AX-XXXL (only Preset heading visible, must drag to full screen). scratchpad/4_instreditor_popover_axxxl.png.

### #9 — Arrangement silently truncates past 128-slot chain cap
- Track: C (code audit, wave 4)
- Repro: create 8 arrangement sections at ×16 repeats each (8×16=128, exact cap), then add a 9th section (any repeat count). Row appears, fully editable, but SONG-mode playback / footer duration-step summary / WAV export never reflect it. `Song.chain` (Song.swift:417-426) stops appending once `Chip.maxChain`=128 total play-throughs reached; `ArrangementView`/`Studio.addSection` has no cap and no warning.
- Expected: cap entry (disable Add/clamp) or show an explicit warning that trailing sections won't play. Actual: silent divergence between the visible arrangement list and what actually plays/exports — no alert, no disabled control, no truncation marker.
- Severity: S2. Status: CONFIRMED.

### #10 — "Import song…" crashes the app (or corrupts grid display) via stale track index
- Track: A (UI-flow, wave 4, SIM-A)
- Repro: Songs list → "+" → "Import song…" (crashes before any file is even chosen).
- Expected: file picker (`fileImporter`) presents. Actual: app terminates to Home. Crash report confirms `EXC_BREAKPOINT`/Swift fatal "Index out of range" at GridView.swift:188 (`let muted = studio.song.tracks[track].muted` in `GridCell.body`) — a `ForEach` in `GridView.row` (line 148) captures a track index that goes stale vs. `studio.song.tracks`.
- Non-deterministic: a second attempt didn't crash but instead showed corrupted step-row labels ("30"–"34" instead of "00"–"04") while STEPS still read 16 — same stale-index desync surfacing as silent data corruption instead of a crash.
- Evidence: crash log `~/Library/Logs/DiagnosticReports/Chiptune-2026-08-19-162742.ips`; scratchpad/16.png, 17.png, repro2.png.
- Severity: S1 (crash, with a data-corruption variant). Status: CONFIRMED.

Leads (not candidates, hand to next Track A finder to try): TrackHeader mute button unguarded index (GridView.swift:322-336); PatternBar destructive actions keyed by stale Int index not id (PatternBar.swift:30-31,69-106); stacked sheets on ContentView rely on mutual exclusion discipline (ContentView.swift:80-110); InstrumentEditor docked panel could blank on async selection change (InstrumentEditor.swift:107-165); empty-array `patterns:[]` in a .chipsong import silently discards arrangement (Song.swift:335-349); SONG arrangement chain silently truncates past Chip.maxChain=128 (Song.swift:417-426); two independent rename paths (library vs title-bar) may race (Studio.swift:899-926).

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

### #7 — WAV export crashes on integer overflow for large renders
- Track: C (code audit, audio/export)
- Repro: build a song near several limits at once (patterns at max 64 steps, arrangement repeats filling the chain to Chip.maxChain=128, tempo at minimum 40 BPM), export with a high loop count (e.g. 16x). `WavExport.swift:225`: `let dataSize = UInt32(totalSamples * 2)` — worked example gives totalSamples*2 ≈ 4.34 billion > UInt32.max (≈4.29 billion), trapping the initializer.
- Expected: export fails gracefully (`.failed`, surfaced via `exportError`) or succeeds. Actual: app crashes mid-render (fatal trap on `UInt32(_:)`), losing the in-progress export.
- Severity: S1 (crash/data loss). Status: CONFIRMED (deterministic arithmetic, code-verified — extreme repro impractical to hand-build via UI in reasonable action budget; fix should add a bounds check rather than rely on UI repro for confirmation).

### #8 — "New Song" (+) button in SongListView does nothing
- Track: B (visual, SIM-B, wave 2)
- Repro: Open Songs sheet → tap "+" (top-right). Tried 3 times.
- Expected: a new song is created and appears in the list (or a naming sheet appears). Actual: nothing happens — song count unchanged, no sheet/dialog, no error, no feedback at all.
- Evidence: scratchpad/13_songlist_plus.png, 14_songlist_plus3.png
- Severity: S2. Status: CONFIRMED.

S4 reserve (log only, don't chase unless needed to hit 10 — max 2 S4 count toward goal):
- SongListView song titles don't line-clamp at AX-XXXL Dynamic Type (wrap to 8 lines, row balloons). scratchpad/9_songlist_axxxl.png.
- InstrumentEditor half-screen sheet shows almost no controls at AX-XXXL (only Preset heading visible, must drag to full screen). scratchpad/4_instreditor_popover_axxxl.png.

Leads (not candidates, hand to next Track A finder to try): TrackHeader mute button unguarded index (GridView.swift:322-336); PatternBar destructive actions keyed by stale Int index not id (PatternBar.swift:30-31,69-106); stacked sheets on ContentView rely on mutual exclusion discipline (ContentView.swift:80-110); InstrumentEditor docked panel could blank on async selection change (InstrumentEditor.swift:107-165); empty-array `patterns:[]` in a .chipsong import silently discards arrangement (Song.swift:335-349); SONG arrangement chain silently truncates past Chip.maxChain=128 (Song.swift:417-426); two independent rename paths (library vs title-bar) may race (Studio.swift:899-926).

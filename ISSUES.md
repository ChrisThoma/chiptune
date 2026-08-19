# Chiptune Bug Hunt — Turn 2 of 40

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

### #3 — Undo coalesces unrelated edits into one step
- Track: C (code audit, model/logic)
- Repro: In ContentView, change tempo via the stepper (checkpoint coalescing:true), then within 1s tap a grid cell to toggle a note (also coalescing:true). Tap Undo once. `UndoHistory.record(coalescing:true)` (UndoHistory.swift:39-58) folds by time window only, not by operation kind.
- Expected: only the note toggle undoes. Actual: both the tempo change and the note toggle revert in one Undo.
- Severity: S2. Status: CONFIRMED.

### #4 — Double-tap Export WAV kicks off two overlapping export/share flows
- Track: A (UI-flow, SIM-A)
- Repro: "…" menu → Export WAV → Export sheet → tap the Export confirm button twice rapidly. First ShareSheet appears; dismiss it. A second, identical ShareSheet resurfaces unprompted later, stealing focus from unrelated UI (observed stealing keystrokes mid rename, rename never committed).
- Expected: at most one export/share cycle per confirm. Actual: two independent renders/shares queued; second one hijacks focus later.
- Evidence: scratchpad/longname.png
- Severity: S2. Status: CONFIRMED.

### #5 — SongListView toolbar (Close, "+") invisible to accessibility tree
- Track: A (UI-flow, SIM-A)
- Repro: Open Songs list. `ui_describe_all` shows nav bar `AXGroup` with zero children, though Close and "+" are visibly rendered and tappable by raw coordinate.
- Expected: toolbar buttons exposed to AX tree (VoiceOver reachable). Actual: not exposed; only coordinate taps work.
- Evidence: scratchpad/songlist.png
- Fix: added explicit `.accessibilityLabel`/`.accessibilityIdentifier` to Close button and Add Menu (SongListView.swift:104-124).
- Severity: S3. Status: FIXED-UNVERIFIED (pending rebuild + verify).

### #6 — Song title field overflows and hides Songs/Undo nav buttons
- Track: B (visual, SIM-B)
- Repro: New song → tap title field → type a long name (e.g. "This Is An Extremely Long Song Title That Should Overflow The Text Field Width").
- Expected: title truncates/wraps, Songs icon and Undo button stay visible. Actual: TextField grows unbounded, scrolls to show tail, Songs icon reduced to a stray fragment, Undo button disappears entirely. Persists after keyboard dismissed / sheet reopened — real layout bug, not a mid-edit artifact.
- Evidence: scratchpad/05_longname.png, 13_final.png
- Fix: TextField gets `.lineLimit(1)`, `.truncationMode(.tail)`, `.layoutPriority(-1)` so it shrinks/truncates instead of growing unbounded (ContentView.swift:279-286).
- Severity: S3. Status: FIXED-UNVERIFIED (pending rebuild + verify).

Inconclusive (not a candidate): Export WAV in-flight feedback — render was too fast (small pattern) to tell if a spinner/disabled state is missing; retest with a heavy pattern in a later wave.

Checked, not bugs: blank-name rename reverts correctly; force-quit/relaunch mid-edit restores state exactly; rapid double-tap Clear Pattern confirm produces only one clear.

Leads (not candidates, hand to next Track A finder to try): TrackHeader mute button unguarded index (GridView.swift:322-336); PatternBar destructive actions keyed by stale Int index not id (PatternBar.swift:30-31,69-106); stacked sheets on ContentView rely on mutual exclusion discipline (ContentView.swift:80-110); InstrumentEditor docked panel could blank on async selection change (InstrumentEditor.swift:107-165); empty-array `patterns:[]` in a .chipsong import silently discards arrangement (Song.swift:335-349); SONG arrangement chain silently truncates past Chip.maxChain=128 (Song.swift:417-426); two independent rename paths (library vs title-bar) may race (Studio.swift:899-926).

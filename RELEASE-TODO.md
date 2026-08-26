# Release TODO — 1.0 submission punch list

From the release-readiness audit of 2026-08-26 (HEAD `daad557`). Verified against
the actual test run, a Release archive, the App Store Connect API, and a
fresh-install simulator walkthrough — not the status docs, which are stale
(see "Docs" below).

Already healthy, don't re-churn: 303/303 tests green (all 30 classes execute),
Release archive clean with zero first-party warnings, artifact stamps 1.0 (7)
with the right bundle ID, pricing/territories/reviewer notes/categories/age
rating/export compliance all set in ASC, first-run starter song works, icon
legible, main grid fully labeled for VoiceOver, no debug leftovers, no
permissions requested.

## Blockers — must clear before Submit

- [ ] **Commit the build-7 bump.** `project.yml` carries an uncommitted
      `CURRENT_PROJECT_VERSION: 6 → 7`; build 7 is uploaded but git has no
      record of it.
- [ ] **Attach build 7 to version 1.0 in ASC.** Build 4 (Aug 11) is attached;
      build 7 (uploaded Aug 21) postdates the last commit (Aug 20) and carries
      all ten bug-hunt fixes. (If any code fixes below ship, cut build 8 and
      attach that instead.)
- [ ] **Reshoot the 4 screenshots.** Current set is Aug 11 / `ba731ab`;
      14 Views-touching commits since, including hold switch, track renaming,
      and the per-channel preset menu. `scripts/shoot.sh` works now.
- [ ] **Confirm the App Privacy questionnaire in the browser.** No API surface;
      unverifiable from the machine.
- [ ] **Real-device smoke test.** Audio session on hardware, iOS 17 minimum,
      SE-width layout. Simulator can't stand in for this.

## Code fixes worth taking into the shipping build (build 8)

Ranked by how early a new user hits them. Per TDD: failing test first.

- [ ] 1. **Export button bricks after cancel/failure** —
      `Sources/Views/ExportSheet.swift:16,63-70`: `hasStartedExport` never
      resets, so "Export WAV" stays disabled until the sheet is reopened.
      Reset it when `isExporting` flips false without an `exportURL`.
- [ ] 2. **False "This can't be undone" on track delete** —
      `Sources/Views/ViewModifiers.swift:7`, shown from `GridView.swift:405`
      and `InstrumentEditor.swift:336`; `Studio.removeTrack`
      (`Studio.swift:829-836`) checkpoints, so it *is* undoable.
- [ ] 3. **Too-long export blames disk space** — `Studio.swift:1088`: the
      >4 GB WAV overflow (fix #7 path) reuses the "not enough space" message.
      Own message: "Too long for one WAV — lower the repeat count."

## Polish — still 1.0; nothing is released, so these ride along before Submit

- [ ] **Dynamic Type**: `chipFont` (`Theme.swift:51-53`) is fixed-size with no
      `relativeTo:` — nothing in the chrome scales. Adopt `@ScaledMetric` or
      document fixed-size as a deliberate design choice.
- [ ] **VoiceOver gaps on recent controls**: PATT/SONG read raw
      (`TransportBar.swift:91-106`); STEPS readout ungrouped and −/+ silent on
      value (`ChipStepper.swift:34-67`); chain-cap warning appears without
      announcement (`ArrangementView.swift:38-44`); repeats stepper reads
      "multiplication sign 3" (`ArrangementView.swift:109-115`); "OCT 4"
      spelled out letter-by-letter (`KeyboardView.swift:60`).
- [ ] **Haptics**: none anywhere. Cell taps, play/stop, export completion are
      silent to the hand. Decide deliberately.
- [ ] **Review prompt + contact row**: no `requestReview` and no in-app way to
      reach the developer. `requestReview` after Nth export; a Contact row next
      to the build stamp (`ContentView.swift:332-348`).
- [ ] **Fix #3 incomplete in InstrumentEditor**:
      `InstrumentEditor.swift:353,369` pass no checkpoint kind, so unrelated
      slider drags still coalesce into one undo step.
- [ ] **Chain-cap copy**: "Arrangement exceeds 128x" (`ArrangementView.swift:40`)
      → "More than 128 plays — sections past that won't sound."

## Later / recorded so they're not lost

- [ ] SongListView leaks ~1.2 MB per open/close cycle (ISSUES.md lead).
- [ ] Export freezes the UI ~1.6 s (ISSUES.md lead).
- [ ] ISSUES.md #5 (toolbar AX) marked BLOCKED, but audit found labels present —
      re-test before spending more on it.
- [ ] `SongListView.swift:278-280`: comment says the clock was dropped but it's
      still rendered — stale comment or the wrap bug is back; check on SE width.
- [ ] Raw CoreAudio detail in the audio-failure alert (`Studio.swift:582-585`).
- [ ] **Docs honesty pass**: untracked `AppStore/` docs describe build 2 /
      Aug 11 (CHECKLIST, SUBMISSION, REMAINING, README fact table);
      SCREENSHOTS.md, LISTING.md, REVIEW-NOTES.md still say "ships as 1.1";
      `docs/screenshots/` in the README is from Jul 24. NEXT-STEPS.md §
      shoot.sh is fixed-but-marked-broken.
- Build 3 stranded in the 1.1 train: harmless, ignore forever.

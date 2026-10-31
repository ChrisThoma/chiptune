#!/usr/bin/env python3
"""Write the sample songs Chiptune ships with, as .chipsong files.

  make_samples.py [out-dir]     (default: Sources/Resources/Samples)

Each song shows off one part of the app:

  Sky Arcade    the full band. Eight named tracks, a drum kit spread over four
                noise tracks, a Chord arpeggio, and an Echo track that plays
                the lead three steps late. Every voice is an exact preset, so
                the instrument editor names it.
  Rainy Waltz   hold and OFF, and pattern length. 3/4 time, so a bar is 12
                steps and a pattern is 48. The melody and the pad hold their
                notes until the next one or an OFF.
  Tower Climb   the arrangement. Intro x2, verse, chorus, an 8-step fill, the
                chorus again a tone higher x2, and an outro.

A step is a sixteenth note. IDs are uuid5 of fixed names, so every run writes
the same bytes and the apps can tell a sample they already seeded.
"""
import json, os, sys, uuid

E, OFF = -1, -2
MAX_STEPS = 64
NS = uuid.UUID("3c7d2a51-8f4e-4b6a-9d1e-5a0c7e2b9f13")
NAMES = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5,
         'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10,
         'Bb': 10, 'B': 11}
KICK, SNARE, HAT, CRASH = 30, 68, 98, 80


def uid(name):
    return str(uuid.uuid5(NS, name)).upper()


def n(s):
    """'A4' -> 69. Passes ints, E and OFF through."""
    if isinstance(s, int):
        return s
    return (int(s[-1]) + 1) * 12 + NAMES[s[:-1]]


def bars(length, *per_bar, bar=16):
    """A row from one {step: note} dict per bar."""
    out = [E] * length
    for b, notes in enumerate(per_bar):
        for s, note in notes.items():
            out[b * bar + s] = n(note)
    return out


def shift(row, by, length):
    """The row played `by` steps late, wrapping inside the pattern."""
    out = [E] * length
    for s in range(length):
        if row[s] != E:
            out[(s + by) % length] = row[s]
    return out


def up(row, semis):
    return [x + semis if x >= 0 else x for x in row]


def inst(duty, volume, decay, sustain=False, arpeggio=None):
    return {"duty": duty, "volume": volume, "decay": decay,
            "sustain": sustain, "arpeggio": arpeggio or []}


PU1, PU2, TRI, NOI = 0, 1, 2, 3


class Song:
    def __init__(self, name, tempo):
        self.name, self.tempo = name, tempo
        self.tracks, self.patterns, self.arrangement = [], [], []

    def track(self, kind, instrument, name=None):
        t = {"id": uid(f"{self.name} track {len(self.tracks)}"), "kind": kind,
             "instrument": instrument, "muted": False}
        if name:
            assert len(name) <= 16, name
            t["name"] = name
        self.tracks.append(t)

    def pattern(self, name, length, rows):
        assert len(name) <= 6, name
        assert len(rows) == len(self.tracks), name
        full = []
        for r in rows:
            assert len(r) == length, (name, len(r))
            assert all(x in (E, OFF) or 0 <= x <= 127 for x in r), name
            full.append(r + [E] * (MAX_STEPS - length))
        p = {"id": uid(f"{self.name} pattern {name}"), "name": name,
             "length": length, "rows": full}
        self.patterns.append(p)
        return p

    def section(self, pattern, repeats=1):
        i = len(self.arrangement)
        self.arrangement.append({"id": uid(f"{self.name} section {i}"),
                                 "patternID": pattern["id"], "repeats": repeats})

    def json(self):
        return {"id": uid(f"sample {self.name}"), "name": self.name,
                "tempo": self.tempo, "modified": 0, "tracks": self.tracks,
                "patterns": self.patterns, "arrangement": self.arrangement}


# --- Sky Arcade -------------------------------------------------------------
# C, Bb, F, G then Ab, Bb, C, C: all major, so the Chord preset's 0-4-7
# arpeggio fits every chord.

def sky_arcade():
    s = Song("Sky Arcade", 150)
    s.track(PU1, inst(2, 0.8, 0.35), "Lead")            # Lead
    s.track(PU2, inst(0, 0.45, 0.9), "Echo")            # Echo
    s.track(PU1, inst(2, 0.7, 0.5, arpeggio=[0, 4, 7]), "Chords")  # Chord
    s.track(TRI, inst(2, 0.9, 0.22), "Bass")            # Pluck bass
    s.track(NOI, inst(2, 0.9, 0.09), "Kick")            # Kick
    s.track(NOI, inst(2, 0.7, 0.25), "Snare")           # Snare
    s.track(NOI, inst(2, 0.4, 0.04), "Hat")             # Closed hat
    s.track(NOI, inst(2, 0.6, 1.4), "Crash")            # Crash

    L = 64

    def chords(roots):
        return bars(L, *[{st: r for st in (0, 3, 6, 10, 12)} for r in roots])

    def bass(roots):
        out = []
        for r in roots:
            b = {st: n(r) + (12 if st % 4 == 2 else 0) for st in range(0, 16, 2)}
            out.append(b)
        return bars(L, *out)

    def kick(fill=False):
        b = {0: KICK, 6: KICK, 8: KICK}
        return bars(L, b, b, b, {0: KICK, 6: KICK, 8: KICK, 10: KICK} if not fill else {0: KICK, 8: KICK})

    def snare(fill=False):
        b = {4: SNARE, 12: SNARE}
        last = {4: SNARE, 12: SNARE, 13: SNARE + 2, 14: SNARE + 4, 15: SNARE + 6} if fill else b
        return bars(L, b, b, b, last)

    def hats(every):
        b = {st: HAT for st in range(0, 16, every)}
        return bars(L, b, b, b, b)

    crash = bars(L, {0: CRASH})

    lead_a = bars(L,
                  {0: 'G5', 3: 'E5', 6: 'G5', 8: 'C6', 10: 'G5', 12: 'E5', 14: 'D5'},
                  {0: 'F5', 3: 'D5', 6: 'F5', 8: 'Bb5', 10: 'A5', 12: 'F5', 14: 'D5'},
                  {0: 'A5', 3: 'F5', 6: 'A5', 8: 'C6', 11: 'A5', 12: 'G5', 14: 'F5'},
                  {0: 'G5', 4: 'B5', 6: 'D6', 8: 'B5', 10: 'G5', 12: 'A5', 14: 'B5'})
    roots_a = ['C2', 'Bb1', 'F2', 'G2']
    s.pattern("Verse", L, [lead_a, shift(lead_a, 3, L),
                           chords(['C4', 'Bb3', 'F3', 'G3']),
                           bass(roots_a), kick(), snare(), hats(2), crash])

    lead_b = bars(L,
                  {0: 'C6', 6: 'Bb5', 8: 'C6', 10: 'Eb6', 12: 'C6'},
                  {0: 'D6', 6: 'C6', 8: 'D6', 10: 'F6', 12: 'D6'},
                  {0: 'E6', 4: 'D6', 6: 'C6', 8: 'G5', 10: 'C6', 12: 'E6'},
                  {0: 'G6', 6: 'E6', 8: 'C6', 12: 'G5', 14: 'B5'})
    roots_b = ['Ab1', 'Bb1', 'C2', 'C2']
    s.pattern("Chorus", L, [lead_b, shift(lead_b, 3, L),
                            chords(['Ab3', 'Bb3', 'C4', 'C4']),
                            bass(roots_b), kick(fill=True), snare(fill=True), hats(1), crash])
    verse, chorus = s.patterns
    s.section(verse); s.section(chorus); s.section(verse); s.section(chorus)
    return s


# --- Rainy Waltz ------------------------------------------------------------
# A minor in 3/4: a beat is 4 steps, a bar 12, a pattern four bars (48).
# Oom on the triangle, pah-pah on Pulse 2 with the Fifths arpeggio (a fifth
# fits minor and major chords alike), the tune and the pad held.

def rainy_waltz():
    s = Song("Rainy Waltz", 100)
    s.track(PU1, inst(1, 0.55, 0.35, sustain=True), "Melody")
    s.track(PU1, inst(3, 0.25, 1.2, sustain=True), "Pad")
    s.track(PU2, inst(1, 0.45, 0.2, arpeggio=[0, 7]), "Pah")
    s.track(TRI, inst(2, 0.9, 1.5), "Bass")             # Bass
    s.track(NOI, inst(2, 0.25, 0.12), "Brush")

    L, BAR = 48, 12

    def w(*per_bar):
        return bars(L, *per_bar, bar=BAR)

    def pah(roots):
        return w(*[{4: r, 8: r} for r in roots])

    def oom(roots, walk=None):
        out = [{0: r} for r in roots]
        for b, note in (walk or {}).items():
            out[b][8] = note
        return w(*out)

    brush = w(*[{4: 90, 8: 90}] * 4)

    melody_a = w({0: 'E5', 8: 'A5'},
                 {0: 'F5', 6: 'E5', 8: 'D5'},
                 {0: 'E5', 4: 'G#5', 8: 'B5'},
                 {0: 'A5', 10: OFF})
    pad_a = w({0: 'C4'}, {0: 'D4'}, {0: 'B3'}, {0: 'C4'})
    roots_a = ['A3', 'D4', 'E4', 'A3']
    a = s.pattern("Rain", L, [melody_a, pad_a, pah(roots_a),
                              oom(['A2', 'D2', 'E2', 'A2'], {2: 'G#2'}), brush])

    melody_b = w({0: 'A5', 8: 'C6'},
                 {0: 'B5', 4: 'D6', 8: 'B5'},
                 {0: 'C6', 8: 'G5'},
                 {0: 'B5', 4: 'G#5', 8: 'E5', 11: OFF})
    pad_b = w({0: 'A3'}, {0: 'B3'}, {0: 'C4'}, {0: 'G#3'})
    roots_b = ['F3', 'G3', 'C4', 'E3']
    b = s.pattern("Puddle", L, [melody_b, pad_b, pah(roots_b),
                                oom(['F2', 'G2', 'C2', 'E2'], {1: 'B1', 3: 'E2'}), brush])

    end = s.pattern("End", BAR, [
        bars(BAR, {0: 'A5', 10: OFF}),
        bars(BAR, {0: 'A3', 10: OFF}),
        bars(BAR, {4: 'A3'}),
        bars(BAR, {0: 'A2'}),
        bars(BAR, {4: 90}),
    ])
    s.section(a, 2); s.section(b, 2); s.section(a); s.section(end)
    return s


# --- Tower Climb ------------------------------------------------------------
# D minor, then the chorus a tone up in E minor. Four tracks, the classic
# channel set, so the arrangement is the thing to look at.

def tower_climb():
    s = Song("Tower Climb", 140)
    s.track(PU1, inst(2, 0.8, 0.35))                    # Lead
    s.track(PU2, inst(1, 0.6, 0.5))                     # Harmony
    s.track(TRI, inst(2, 0.9, 0.22))                    # Pluck bass
    s.track(NOI, inst(2, 0.6, 0.12))                    # one track, three drums

    def gallop(roots, length):
        per = [{st: n(r) + (12 if st == 6 else 0)
                for st in (0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15)} for r in roots]
        return bars(length, *per)

    def beat(count, length):
        b = {0: KICK, 8: KICK, 4: SNARE, 12: SNARE, 2: HAT, 6: HAT, 10: HAT, 14: HAT}
        return bars(length, *[b] * count)

    silent = lambda length: [E] * length

    intro = s.pattern("Intro", 16, [silent(16), silent(16),
                                    gallop(['D2'], 16), beat(1, 16)])

    verse = s.pattern("Verse", 64, [
        bars(64,
             {0: 'D5', 3: 'F5', 6: 'A5', 8: 'G5', 10: 'F5', 12: 'E5', 14: 'F5'},
             {0: 'D5', 3: 'F5', 6: 'Bb5', 8: 'A5', 10: 'G5', 12: 'F5', 14: 'G5'},
             {0: 'E5', 3: 'G5', 6: 'C6', 8: 'Bb5', 10: 'A5', 12: 'G5', 14: 'A5'},
             {0: 'A5', 4: 'C#6', 8: 'E6', 12: 'G6'}),
        bars(64,
             {2: 'F4', 6: 'A4', 10: 'F4', 14: 'A4'},
             {2: 'D4', 6: 'F4', 10: 'D4', 14: 'F4'},
             {2: 'E4', 6: 'G4', 10: 'E4', 14: 'G4'},
             {2: 'C#4', 6: 'E4', 10: 'C#4', 14: 'E4'}),
        gallop(['D2', 'Bb1', 'C2', 'A1'], 64),
        beat(4, 64)])

    chorus_lead = bars(64,
                       {0: 'F5', 4: 'Bb5', 8: 'D6', 12: 'C6'},
                       {0: 'G5', 4: 'C6', 8: 'E6', 12: 'D6'},
                       {0: 'F6', 6: 'E6', 8: 'D6', 12: 'A5'},
                       {0: 'D6', 12: 'A5', 14: 'C6'})
    chorus_harm = bars(64,
                       {0: 'D5', 8: 'F5'}, {0: 'E5', 8: 'G5'},
                       {0: 'A5', 8: 'F5'}, {0: 'F5', 8: 'D5'})
    chorus_bass = gallop(['Bb1', 'C2', 'D2', 'D2'], 64)
    chorus_drums = beat(4, 64)
    chorus = s.pattern("Chorus", 64, [chorus_lead, chorus_harm, chorus_bass, chorus_drums])

    fill = s.pattern("Fill", 8, [
        bars(8, {0: 'A5', 2: 'B5', 4: 'C#6', 6: 'D#6'}),
        silent(8),
        bars(8, {0: 'A2', 2: 'B2', 4: 'C#3', 6: 'D#3'}),
        bars(8, {st: SNARE + st for st in range(8)})])

    high = s.pattern("Up", 64, [up(chorus_lead, 2), up(chorus_harm, 2),
                                up(chorus_bass, 2), chorus_drums])

    outro = s.pattern("Outro", 16, [
        bars(16, {0: 'E6'}), bars(16, {0: 'B5'}),
        bars(16, {0: 'E2', 4: 'E3'}), bars(16, {0: KICK, 1: CRASH})])

    s.section(intro, 2); s.section(verse); s.section(chorus)
    s.section(fill); s.section(high, 2); s.section(outro)
    return s


SONGS = {"sky-arcade": sky_arcade, "rainy-waltz": rainy_waltz,
         "tower-climb": tower_climb}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "Sources", "Resources", "Samples")
    os.makedirs(out, exist_ok=True)
    for slug, make in SONGS.items():
        with open(os.path.join(out, f"sample-{slug}.chipsong"), "w") as f:
            json.dump(make().json(), f, indent=2)
            f.write("\n")
        print(slug)


if __name__ == "__main__":
    main()

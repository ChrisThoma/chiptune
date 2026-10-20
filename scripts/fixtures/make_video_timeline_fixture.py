#!/usr/bin/env python3
"""Writes Tests/Fixtures/video-timeline.json from a reference computation
written straight from the spec, independent of the Swift and Kotlin code.

    python3 scripts/fixtures/make_video_timeline_fixture.py Tests/Fixtures/video-timeline.json
"""
import json, math, sys

SR = 44100
FPS = 30
SPF = SR // FPS
LOOPS = 2

# 120 BPM is 5512.5 samples a step: the exact half, which rounds away from
# zero to 5513 (a round-half-to-even port would get 5512).
#
# Track 0 has the longest decay that rings. Tracks 2-4 each have a longer
# one the tail must ignore: 2 is muted, 3 sustains (it releases at once and
# rings nothing), 4 only has notes in pattern C, which the arrangement never
# plays.
# 120 BPM is 5512.5 samples a step: the exact half, which rounds away from
# zero to 5513 (a round-half-to-even port would get 5512).
#
# Track 0 has the longest decay that rings. Tracks 2-4 each have a longer
# one the tail must ignore: 2 is muted, 3 sustains (it releases at once and
# rings nothing), 4 only has notes in pattern C, which the arrangement never
# plays.
song = {
    "id": "5A1D0E7E-0000-4000-8000-000000000001",
    "name": "Timeline Fixture",
    "tempo": 120,
    "modified": 780000000.0,
    "tracks": [
        {"id": "5A1D0E7E-0000-4000-8000-0000000000A1", "kind": 0, "muted": False,
         "instrument": {"duty": 2, "volume": 0.8, "decay": 0.8, "sustain": False, "arpeggio": []}},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000A2", "kind": 2, "muted": False,
         "instrument": {"duty": 2, "volume": 0.9, "decay": 0.3, "sustain": False, "arpeggio": []}},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000A3", "kind": 1, "muted": True,
         "instrument": {"duty": 1, "volume": 0.7, "decay": 4.0, "sustain": False, "arpeggio": []}},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000A4", "kind": 3, "muted": False,
         "instrument": {"duty": 2, "volume": 0.6, "decay": 3.0, "sustain": True, "arpeggio": []}},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000A5", "kind": 2, "muted": False,
         "instrument": {"duty": 2, "volume": 0.9, "decay": 2.5, "sustain": False, "arpeggio": []}},
    ],
    "patterns": [
        {"id": "5A1D0E7E-0000-4000-8000-0000000000B1", "name": "A", "length": 4,
         "rows": [[72, -1, 76, -1], [48, -1, -1, -2], [60, -1, 62, -1],
                  [36, -2, 36, -1], [-1, -1, -1, -1]]},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000B2", "name": "B", "length": 6,
         "rows": [[79, -1, -1, 77, -1, -2], [43, -1, -1, -1, 45, -1], [-1, -1, -1, -1, -1, -1],
                  [-1, 40, -1, -1, 40, -1], [-1, -1, -1, -1, -1, -1]]},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000B3", "name": "C", "length": 4,
         "rows": [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1],
                  [-1, -1, -1, -1], [50, -1, -1, -1]]},
    ],
    "arrangement": [
        {"id": "5A1D0E7E-0000-4000-8000-0000000000C1",
         "patternID": "5A1D0E7E-0000-4000-8000-0000000000B1", "repeats": 2},
        {"id": "5A1D0E7E-0000-4000-8000-0000000000C2",
         "patternID": "5A1D0E7E-0000-4000-8000-0000000000B2", "repeats": 1},
    ],
}

# Chip.samplesPerStep: round-half-away-from-zero of sr*60/(bpm*4).
def round_half_away(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)

sps = int(round_half_away(SR * 60.0 / (song["tempo"] * 4)))
pid = {p["id"]: i for i, p in enumerate(song["patterns"])}
chain = []
for sec in song["arrangement"]:
    chain += [pid[sec["patternID"]]] * sec["repeats"]
lengths = [song["patterns"][i]["length"] for i in chain]
steps = sum(lengths)
body = sps * steps * LOOPS
# WavExport.tailSeconds: clamp(1.5 * Song.maxAudibleDecay, 1, 6); then
# Int(44100 * seconds), truncating, as Kotlin's toInt() does.
# maxAudibleDecay: the longest decay among tracks that are not muted, not
# sustaining, have a decay above 0, and have a note (0...127) within the
# length of a pattern the arrangement plays. 0 when none qualifies.
def plays(index):
    for p in set(chain):
        pat = song["patterns"][p]
        if any(0 <= n <= 127 for n in pat["rows"][index][:pat["length"]]):
            return True
    return False

decay = max([t["instrument"]["decay"] for i, t in enumerate(song["tracks"])
             if not t["muted"] and not t["instrument"].get("sustain", False)
             and t["instrument"]["decay"] > 0 and plays(i)] or [0.0])
tail_seconds = min(max(1.5 * decay, 1.0), 6.0)
tail = int(SR * tail_seconds)
total = body + tail
frames = -(-total // SPF)

def position(frame):
    s = frame * SPF
    if s >= body:
        return None
    g = (s % (sps * steps)) // sps
    for slot, n in enumerate(lengths):
        if g < n:
            return {"chainSlot": slot, "pattern": chain[slot], "step": g}
        g -= n

# ChannelPulse: a note-on lights a track's bar fully on the frame its sound
# starts and it fades in a straight line to dark over DECAY_FRAMES; a
# note-off cuts it. A muted track, or one whose round(volume * 127) is 0,
# never lights. Past the body the last step is still the latest played.
DECAY_FRAMES = 10

def silent(track):
    v = track["instrument"]["volume"] * 127
    return track["muted"] or round_half_away(v) == 0

def pattern_at(g):
    g %= steps
    for slot, n in enumerate(lengths):
        if g < n:
            return song["patterns"][chain[slot]], g
        g -= n

def levels(frame):
    now = frame * SPF
    last = steps * LOOPS - 1
    out = []
    for i, track in enumerate(song["tracks"]):
        level = 0.0
        if not silent(track):
            step = min(now // sps, last)
            while step >= 0:
                since = float(now - step * sps) / float(SPF)
                if since >= DECAY_FRAMES:
                    break
                pat, at = pattern_at(step)
                note = pat["rows"][i][at]
                if note >= 0:
                    level = 1 - since / float(DECAY_FRAMES)
                    break
                if note == -2:
                    break
                step -= 1
        out.append(level)
    return out

rows = []
for f in range(frames):
    p = position(f)
    rows.append({"frame": f, **(p or {"chainSlot": None, "pattern": None, "step": None}),
                 "levels": levels(f)})

fixture = {
    "about": ("Shared by the iOS VideoTimelineTests and ChannelPulseTests and the Android VideoTimelineTest. "
              "Render `song` as a video with `loopCount` passes: frame f shows the audio "
              "at sample f * samplesPerFrame. `frames` gives, for every frame, the chain slot "
              "(index into the arrangement expanded by repeats), the pattern index and the step "
              "inside that pattern; all three are null once the body has ended and the "
              "ring-out tail is playing. `levels` is each track's ChannelPulse bar level (0...1) "
              "on that frame. Generated by a reference script, not by either app."),
    "sampleRate": SR,
    "fps": FPS,
    "samplesPerFrame": SPF,
    "loopCount": LOOPS,
    "song": song,
    "expected": {
        "samplesPerStep": sps,
        "chain": chain,
        "arrangementSteps": steps,
        "bodySamples": body,
        "tailSeconds": tail_seconds,
        "tailSamples": tail,
        "totalSamples": total,
        "totalFrames": frames,
    },
    "checkpoints": {
        "firstFrame": 0,
        "lastFrameOfStep0": max(f for f in range(frames) if f * SPF < sps),
        "firstFrameOfStep1": min(f for f in range(frames) if f * SPF >= sps),
        "secondPlayOfARepeatedSection": min(f for f in range(frames) if rows[f]["chainSlot"] == 1),
        "firstFrameOfSecondPass": min(f for f in range(frames) if f * SPF >= sps * steps),
        "lastFrameOfBody": max(f for f in range(frames) if f * SPF < body),
        "firstFrameOfTail": min(f for f in range(frames) if f * SPF >= body),
        "lastFrame": frames - 1,
    },
    "frames": rows,
}

out = sys.argv[1]
with open(out, "w") as fh:
    json.dump(fixture, fh, indent=1)
    fh.write("\n")
print(json.dumps(fixture["expected"]), json.dumps(fixture["checkpoints"]))

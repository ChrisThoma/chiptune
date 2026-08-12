import XCTest
@testable import Chiptune

/// The named sounds behind the editor's preset menu.
///
/// Dragging four raw parameters was the only route to a usable sound, which is
/// a lot to ask of someone who just wants a snare. These are also the honest
/// documentation for what those parameters do.
final class InstrumentPresetTests: XCTestCase {

    func testEveryKindHasPresets() {
        for kind in ChannelKind.allCases {
            XCTAssertFalse(InstrumentPreset.presets(for: kind).isEmpty,
                           "\(kind.fullName) has nothing to choose from")
        }
    }

    func testPresetsAreListedUnderTheirOwnKind() {
        for kind in ChannelKind.allCases {
            for preset in InstrumentPreset.presets(for: kind) {
                XCTAssertEqual(preset.kind, kind)
            }
        }
    }

    func testPresetNamesAreUniqueWithinAKind() {
        for kind in ChannelKind.allCases {
            let names = InstrumentPreset.presets(for: kind).map(\.name)
            XCTAssertEqual(Set(names).count, names.count,
                           "\(kind.fullName) lists a name twice")
        }
    }

    /// A hand-tuned value outside the engine's range would be silently rewritten
    /// the moment the song normalised, so the preset you picked isn't the sound
    /// you'd keep.
    func testEveryPresetSurvivesNormalisationUnchanged() {
        for preset in InstrumentPreset.all {
            var normalised = preset.instrument
            normalised.normalize()
            XCTAssertEqual(normalised, preset.instrument,
                           "preset \"\(preset.name)\" is outside what the engine can play")
        }
    }

    /// One source of truth: adding a track and picking that track's first
    /// preset have to give the same sound.
    func testTheDefaultInstrumentIsTheFirstPresetForItsKind() {
        for kind in ChannelKind.allCases {
            XCTAssertEqual(Instrument.default(for: kind),
                           InstrumentPreset.presets(for: kind).first?.instrument,
                           "\(kind.fullName)'s default and its first preset disagree")
        }
    }

    /// The whole point of the round of work these arrived in: nothing you can
    /// pick from the menu drones on its own.
    func testNoPresetHoldsWithoutSayingSo() {
        for preset in InstrumentPreset.all where preset.instrument.sustain {
            XCTAssertTrue(preset.name.lowercased().contains("hold")
                          || preset.name.lowercased().contains("pad")
                          || preset.name.lowercased().contains("drone"),
                          "preset \"\(preset.name)\" holds but its name gives no warning")
        }
    }

    /// What the menu shows when the sound has been edited away from every
    /// preset — and that it recognises one that hasn't been.
    func testAPresetIsRecognisedAndAnEditedSoundIsNot() {
        let bass = try? XCTUnwrap(InstrumentPreset.presets(for: .triangle).first)
        let preset = try! XCTUnwrap(bass)

        XCTAssertEqual(InstrumentPreset.matching(preset.instrument, kind: .triangle)?.name,
                       preset.name)

        var edited = preset.instrument
        edited.volume = 0.13
        XCTAssertNil(InstrumentPreset.matching(edited, kind: .triangle))
    }

    /// Every preset must actually make a sound, and end.
    func testEveryPresetSoundsAndThenStops() {
        for preset in InstrumentPreset.all where !preset.instrument.sustain {
            var song = TestSongs.empty(tempo: 40)
            song.tracks = [Track(kind: preset.kind)]
            song.tracks[0].instrument = preset.instrument
            song.patterns[0].rows = [Pattern.emptyRow]
            song.patterns[0].rows[0][0] = 48
            let samples = RenderHarness.render(song: song, seconds: 3.0)

            XCTAssertGreaterThan(RenderHarness.rms(samples[0..<8820]), 0.001,
                                 "preset \"\(preset.name)\" is silent")
            XCTAssertLessThan(RenderHarness.rms(samples[(samples.count - 4410)...]), 0.005,
                              "preset \"\(preset.name)\" was still sounding 3 s later")
        }
    }
}

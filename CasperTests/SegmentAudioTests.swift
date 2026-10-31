import Foundation
import Testing

struct SegmentAudioTests {
  private static let sampleRate = 16_000.0

  /// A 4-second pause before the segment is shortened, so the context before the segment reaches the words before the
  /// pause instead of holding only silence.
  @Test func reachesPastALongPauseForContext() throws {
    let audio = Self.speech(3) + Self.background(4) + Self.speech(3)
    let segment = Self.index(5)..<audio.count
    let segmentAudio = Self.segmentAudio(audio, segment: segment, trimmer: SilenceTrimmer())
    let firstSpan = try #require(segmentAudio.spans.first)
    #expect(firstSpan.recordingStart < Self.index(3))
    #expect(Double(segmentAudio.samples.count) / Self.sampleRate < 7)
    #expect(segmentAudio.recordingIndex(of: segmentAudio.samples.count - 1) == audio.count - 1)
  }

  @Test func keepsTheContextAsItIsWithoutTrimming() {
    let audio = Self.speech(3) + Self.background(4) + Self.speech(3)
    let segment = Self.index(5)..<Self.index(9)
    let segmentAudio = Self.segmentAudio(audio, segment: segment, trimmer: nil)
    #expect(segmentAudio.samples == Array(audio[Self.index(2)..<Self.index(10)]))
    #expect(segmentAudio.spans == [.init(start: 0, recordingStart: Self.index(2), count: Self.index(8))])
  }

  /// A cut forced through speech has no silence to shorten, so the audio around it is heard as it is.
  @Test func leavesSpeechAroundAForcedCutAlone() {
    let audio = Self.background(1) + Self.speech(13)
    let segment = Self.index(6)..<Self.index(11)
    let segmentAudio = Self.segmentAudio(audio, segment: segment, trimmer: SilenceTrimmer())
    #expect(segmentAudio.samples == Array(audio[Self.index(3)..<Self.index(12)]))
  }

  /// Spans overlap where they crossfade, so each is checked from its start up to the next.
  @Test func mapsSamplesBackToTheRecording() {
    let audio = Self.speech(3) + Self.background(4) + Self.speech(3)
    let segmentAudio = Self.segmentAudio(audio, segment: Self.index(5)..<audio.count, trimmer: SilenceTrimmer())
    #expect(segmentAudio.spans.count == 2)
    for span in segmentAudio.spans {
      #expect(segmentAudio.recordingIndex(of: span.start) == span.recordingStart)
      #expect(segmentAudio.recordingIndex(of: span.start + span.count / 2) == span.recordingStart + span.count / 2)
    }
  }

  /// A word placed in the silence before a shortened pause is the word after it, placed early.
  @Test func mapsAWordPlacedEarlyInAShortenedPausePastIt() throws {
    let audio = Self.speech(3) + Self.background(4) + Self.speech(3)
    let segmentAudio = Self.segmentAudio(audio, segment: Self.index(5)..<audio.count, trimmer: SilenceTrimmer())
    let afterPause = try #require(segmentAudio.spans.last)
    #expect(segmentAudio.recordingIndex(of: afterPause.start - Self.index(0.1)) == afterPause.recordingStart)
  }

  @Test func readsTheSegmentAlone() {
    let audio = Self.background(1) + Self.speech(13)
    let segment = Self.index(6)..<Self.index(11)
    let segmentAudio = Self.segmentAudio(audio, segment: segment, trimmer: nil)
    #expect(Array(segmentAudio.segmentSamples) == Array(audio[segment]))
  }

  private static func segmentAudio(_ audio: [Float], segment: Range<Int>, trimmer: SilenceTrimmer?) -> SegmentAudio {
    SegmentAudio(
      audio,
      from: 0,
      segment: segment,
      lookback: 3,
      lookahead: 1,
      trimmer: trimmer,
      sampleRate: sampleRate
    )
  }

  private static func index(_ seconds: Double) -> Int {
    Int(seconds * sampleRate)
  }

  /// A tone that rises and falls four times a second, like syllables.
  private static func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * sampleRate))
      .map { index in
        let time = Float(Double(index) / sampleRate)
        let syllables = 0.75 + 0.25 * sin(2 * .pi * 4 * time)
        return 0.1 * syllables * sin(2 * .pi * 220 * time)
      }
  }

  /// Steady noise, the same on every run.
  private static func background(_ seconds: Double) -> [Float] {
    var state: UInt32 = 1
    return (0..<Int(seconds * sampleRate))
      .map { _ in
        state = state &* 1_664_525 &+ 1_013_904_223
        return 0.001 * (Float(state) / Float(UInt32.max) * 2 - 1)
      }
  }
}

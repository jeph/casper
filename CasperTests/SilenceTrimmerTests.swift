import Foundation
import Testing

struct SilenceTrimmerTests {
  private static let sampleRate = 16_000.0
  private let trimmer = SilenceTrimmer()

  @Test func shortensSilenceAtTheEdges() {
    let recording = Self.background(2) + Self.speech(1) + Self.background(2)
    let trimmed = trimmer.trim(recording, sampleRate: Self.sampleRate)
    #expect(Self.seconds(trimmed) == 1 + 2 * trimmer.edgeSilence)
  }

  @Test func shortensLongPausesToTheLongestPause() {
    let firstWords = Self.speech(1)
    let lastWords = Self.speech(1)
    let recording = firstWords + Self.background(3) + lastWords
    let trimmed = trimmer.trim(recording, sampleRate: Self.sampleRate)
    #expect(Self.seconds(trimmed) == 2 + trimmer.longestPause)
    // The speech on either side of the cut comes through untouched.
    #expect(Array(trimmed.prefix(firstWords.count)) == firstWords)
    #expect(Array(trimmed.suffix(lastWords.count)) == lastWords)
  }

  @Test func keepsPausesUpToTheLongestPause() {
    let recording = Self.speech(1) + Self.background(trimmer.longestPause) + Self.speech(1)
    #expect(trimmer.trim(recording, sampleRate: Self.sampleRate) == recording)
  }

  /// Speech from start to finish has nothing to cut.
  @Test func keepsSpeechWithoutPauses() {
    let recording = Self.speech(3)
    #expect(trimmer.trim(recording, sampleRate: Self.sampleRate) == recording)
  }

  /// Without speech well above the background, loudness can't tell where speech is, so nothing is cut.
  @Test func keepsRecordingsWhereSpeechIsNotLouderThanTheBackground() {
    let recording = Self.background(2, level: 0.05) + Self.speech(1) + Self.background(2, level: 0.05)
    #expect(trimmer.trim(recording, sampleRate: Self.sampleRate) == recording)
  }

  @Test func keepsRecordingsOfOnlyBackground() {
    let recording = Self.background(3)
    #expect(trimmer.trim(recording, sampleRate: Self.sampleRate) == recording)
  }

  @Test func keepsEmptyRecordings() {
    #expect(trimmer.trim([], sampleRate: Self.sampleRate).isEmpty)
  }

  /// A tone whose loudness rises and falls like syllables, never dropping near the background.
  private static func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * sampleRate))
      .map { index in
        let time = Float(Double(index) / sampleRate)
        let syllables = 0.75 + 0.25 * sin(2 * .pi * 4 * time)
        return 0.1 * syllables * sin(2 * .pi * 220 * time)
      }
  }

  /// Steady noise, the same on every run.
  private static func background(_ seconds: Double, level: Float = 0.001) -> [Float] {
    var state: UInt32 = 1
    return (0..<Int(seconds * sampleRate))
      .map { _ in
        state = state &* 1_664_525 &+ 1_013_904_223
        return level * (Float(state) / Float(UInt32.max) * 2 - 1)
      }
  }

  private static func seconds(_ samples: [Float]) -> Double {
    Double(samples.count) / sampleRate
  }
}

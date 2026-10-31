import Testing

struct LiveSegmenterTests {
  private let segmenter = LiveSegmenter()

  @Test func cutsInTheMiddleOfThePauseAfterTheShortestSegment() {
    let levels = Self.speech(4) + Self.pause(1) + Self.speech(2)
    #expect(segmenter.cut(levels: levels, from: 0) == 450)
  }

  @Test func waitsForAudioAfterTheCut() {
    let levels = Self.speech(4) + Self.pause(1) + Self.speech(0.4)
    #expect(segmenter.cut(levels: levels, from: 0) == nil)
    #expect(segmenter.cut(levels: levels + Self.speech(1.1), from: 0) == 450)
  }

  @Test func skipsPausesThatEndBeforeTheShortestSegment() {
    let levels = Self.speech(1) + Self.pause(1) + Self.speech(3) + Self.pause(1) + Self.speech(2)
    #expect(segmenter.cut(levels: levels, from: 0) == 550)
  }

  /// A pause that reaches past the shortest segment is cut there if the cut stays clear of the speech after it.
  @Test func cutsAPauseThatReachesPastTheShortestSegment() {
    let levels = Self.speech(2) + Self.pause(1.5) + Self.speech(3)
    #expect(segmenter.cut(levels: levels, from: 0) == 300)
  }

  /// A cut right before the next word could give that word to both segments.
  @Test func skipsAPauseThatEndsRightAfterTheShortestSegment() {
    let levels = Self.speech(2.25) + Self.pause(0.8) + Self.speech(4) + Self.pause(1) + Self.speech(2)
    #expect(segmenter.cut(levels: levels, from: 0) == 755)
  }

  @Test func measuresSegmentsFromTheirStart() {
    let levels = Self.speech(4) + Self.pause(1) + Self.speech(4) + Self.pause(1) + Self.speech(2)
    #expect(segmenter.cut(levels: levels, from: 450) == 950)
  }

  /// Speech without a pause is cut in its quietest stretch in the second half of the longest segment, rather than at
  /// a single quiet slice, which can fall inside a word.
  @Test func cutsSpeechWithoutPausesInItsQuietestStretch() {
    var levels = Self.speech(13)
    levels[700] = -60
    for index in 793...807 {
      levels[index] = -30
    }
    #expect(segmenter.cut(levels: Self.pause(0.1) + levels, from: 10) == 810)
  }

  @Test func waitsForTheLongestSegmentWithoutPauses() {
    let levels = Self.pause(0.1) + Self.speech(10)
    #expect(segmenter.cut(levels: levels, from: 10) == nil)
  }

  private static func speech(_ seconds: Double) -> [Double] {
    [Double](repeating: -20, count: Int(seconds * 100))
  }

  private static func pause(_ seconds: Double) -> [Double] {
    [Double](repeating: -60, count: Int(seconds * 100))
  }
}

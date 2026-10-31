/// Decides where to cut a recording in progress into segments that can be transcribed while the user keeps speaking.
///
/// Cuts go in pauses, found the way `SilenceTrimmer` finds silence: slices that stay near the recording's quietest
/// level. A pause is cut once some audio after it has been heard, so the words before it are transcribed knowing what
/// comes next, or once it has gone on long enough that the user may have stopped. Without a pause, a segment is cut at
/// its quietest moment once it reaches `longestSegment`, so it fits in Parakeet's 15-second window along with the
/// audio around it that the transcriber reads for context.
struct LiveSegmenter: Sendable {
  /// The shortest a segment can be, in seconds, so pauses between phrases don't cut speech into scraps.
  var shortestSegment = 3.0
  /// The longest a segment can be, in seconds.
  var longestSegment = 10.0
  /// The shortest pause a segment is cut in, in seconds.
  var shortestPause = 0.4
  /// How much audio after a pause is waited for before cutting in it, in seconds.
  var audioAfterPause = 1.0
  /// How long a pause can go on, in seconds from its start, before it's cut without waiting for audio after it.
  ///
  /// The user may have stopped speaking, and if the recording ends during the pause, the segment before it would
  /// otherwise be left to transcribe after it ends.
  var longestPauseWait = 1.9
  /// How much audio must follow a cut through speech before it's made, in seconds, so the words before it are
  /// transcribed knowing what comes next.
  var lookahead = 1.5
  /// How far above the quietest tenth of the recording a slice can be, in decibels, and still be silence.
  var silenceMargin = 6.0
  /// How much louder than silence the loudest sounds must be, in decibels, for pauses to be told apart from speech.
  var minimumContrast = 20.0

  /// Finds where to end the segment that starts at slice `start`.
  ///
  /// - Parameters:
  ///   - levels: The loudness of every slice recorded so far, in decibels, each `SilenceTrimmer.sliceDuration` long.
  ///   - start: The slice the segment starts at.
  /// - Returns: The slice to cut at, or `nil` if the segment should grow.
  func cut(levels: [Double], from start: Int) -> Int? {
    switch firstPause(in: levels, from: start + Self.slices(shortestSegment)) {
    case .cut(let cut): return cut
    case .waiting: return nil
    case .none: break
    }
    let forcedCut = start + Self.slices(longestSegment)
    guard levels.count - Self.slices(lookahead) >= forcedCut else { return nil }
    // The second half of the longest segment, where a cut leaves neither side short. The quietest stretch rather than
    // the quietest slice, since a single quiet slice can fall inside a word, and a cut there splits it.
    let candidates = (start + Self.slices(longestSegment / 2))...forcedCut
    let halfGap = Self.slices(Self.wordGap) / 2
    return candidates.min { first, second in
      Self.meanLevel(of: levels[(first - halfGap)...(first + halfGap)])
        < Self.meanLevel(of: levels[(second - halfGap)...(second + halfGap)])
    }
  }

  private enum PauseCut {
    case cut(Int)
    /// A pause to cut in hasn't been heard for long enough yet.
    case waiting
    case none
  }

  /// The cut in the first pause long enough that has room for one from `earliestCut` on.
  ///
  /// A pause is cut in its middle, as far as it has been heard, so the cut stays clear of the words on both sides even
  /// though the model's timings for them can be a frame or two off. Every cut leaves at least half the shortest pause
  /// on either side.
  private func firstPause(in levels: [Double], from earliestCut: Int) -> PauseCut {
    guard levels.count > earliestCut else { return .none }
    let sorted = levels.sorted()
    let quietest = sorted[sorted.count / 10]
    let loudest = sorted[sorted.count * 99 / 100]
    guard loudest - quietest >= minimumContrast else { return .none }
    let pauseSlices = Self.slices(shortestPause)
    let isSilent = levels.map { $0 < quietest + silenceMargin }
    var searchStart = 0
    while let pauseStart = isSilent[searchStart...].firstIndex(of: true) {
      let pauseEnd = isSilent[pauseStart...].firstIndex(of: false) ?? levels.count
      searchStart = pauseEnd
      guard pauseEnd - pauseStart >= pauseSlices else { continue }
      let cut = max(pauseStart + (pauseEnd - pauseStart) / 2, earliestCut)
      guard cut >= pauseStart + pauseSlices / 2, cut + pauseSlices / 2 <= pauseEnd else {
        // A pause still going on may yet leave room.
        if pauseEnd == levels.count { return .waiting }
        continue
      }
      let waitedOut = levels.count - pauseStart >= Self.slices(longestPauseWait)
      return levels.count - pauseEnd >= Self.slices(audioAfterPause) || waitedOut ? .cut(cut) : .waiting
    }
    return .none
  }

  /// About how long the gaps between words in continuous speech last, in seconds.
  private static let wordGap = 0.15

  private static func meanLevel(of levels: ArraySlice<Double>) -> Double {
    levels.reduce(0, +) / Double(levels.count)
  }

  private static func slices(_ seconds: Double) -> Int {
    Int((seconds / SilenceTrimmer.sliceDuration).rounded())
  }
}

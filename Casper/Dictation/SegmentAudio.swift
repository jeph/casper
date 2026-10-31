/// The audio a segment of a recording in progress is transcribed from: the segment, with some of the audio before and
/// after it for context, and its silence shortened if trimming is on.
///
/// Context is measured after trimming, so a long pause at a cut doesn't fill it with silence: the model hears the words
/// on the other side of the pause, as it would in the whole recording trimmed at once. Trimming shortens only what
/// `SilenceTrimmer` finds to be silence, so a cut forced through speech is heard as it is.
struct SegmentAudio: Sendable {
  /// A stretch of the recording within `samples`.
  struct Span: Sendable, Equatable {
    /// Where the stretch starts in `samples`.
    let start: Int
    /// Where the stretch starts in the recording.
    let recordingStart: Int
    let count: Int
  }

  let samples: [Float]
  /// The stretches of the recording that `samples` is made of, in order.
  let spans: [Span]
  /// The segment, as indices in the recording.
  let segment: Range<Int>
  /// How much of the silence before a shortened pause is kept at the end of the span before it, in samples.
  private let pauseSide: Int

  /// Takes the segment and its context from audio of the recording.
  ///
  /// - Parameters:
  ///   - audio: The recording from index `offset` on, holding the segment and the audio around it.
  ///   - offset: The index in the recording of the first of `audio`.
  ///   - segment: The segment, as indices in the recording.
  ///   - lookback: How much audio before the segment is kept, in seconds after trimming.
  ///   - lookahead: How much audio after the segment is kept, in seconds after trimming.
  ///   - trimmer: Shortens the silence, or `nil` to keep it.
  ///   - sampleRate: The recording's sample rate, in hertz.
  init(
    _ audio: [Float],
    from offset: Int,
    segment: Range<Int>,
    lookback: Double,
    lookahead: Double,
    trimmer: SilenceTrimmer?,
    sampleRate: Double
  ) {
    self.segment = segment
    pauseSide = trimmer.map { Int($0.longestPause / 2 * sampleRate) } ?? 0
    let kept = trimmer?.keptRanges(of: audio, sampleRate: sampleRate) ?? [audio.indices]
    let segmentStart = segment.lowerBound - offset
    let segmentEnd = segment.upperBound - offset
    var before: [Range<Int>] = []
    var lookbackLeft = Int(lookback * sampleRate)
    for range in kept.reversed() where lookbackLeft > 0 {
      let clipped = range.clamped(to: 0..<segmentStart)
      guard !clipped.isEmpty else { continue }
      let taken = max(clipped.lowerBound, clipped.upperBound - lookbackLeft)..<clipped.upperBound
      before.insert(taken, at: 0)
      lookbackLeft -= taken.count
    }
    var after: [Range<Int>] = []
    var lookaheadLeft = Int(lookahead * sampleRate)
    for range in kept where lookaheadLeft > 0 {
      let clipped = range.clamped(to: segmentEnd..<audio.count)
      guard !clipped.isEmpty else { continue }
      let taken = clipped.lowerBound..<min(clipped.upperBound, clipped.lowerBound + lookaheadLeft)
      after.append(taken)
      lookaheadLeft -= taken.count
    }
    let within = kept.map { $0.clamped(to: segmentStart..<segmentEnd) }
    // Clipping splits ranges at the segment's edges, so neighbors are joined again, leaving only real cuts to crossfade.
    // A range no longer than the crossfade can't be crossfaded, and is too short to hear anyway.
    let crossfadeLength = Int(SilenceTrimmer.crossfadeDuration * sampleRate)
    let ranges = (before + within + after)
      .reduce(into: [Range<Int>]()) { joined, range in
        guard !range.isEmpty else { return }
        if let last = joined.last, last.upperBound == range.lowerBound {
          joined[joined.count - 1] = last.lowerBound..<range.upperBound
        } else {
          joined.append(range)
        }
      }
      .filter { $0.count > crossfadeLength }
    let spliced = SilenceTrimmer.splice(ranges, of: audio, sampleRate: sampleRate)
    samples = spliced.samples
    spans = zip(ranges, spliced.starts)
      .map { range, start in Span(start: start, recordingStart: offset + range.lowerBound, count: range.count) }
  }

  /// The index in the recording of the sample at `index` in `samples`.
  ///
  /// An index in the silence kept at the end of a span before a shortened pause maps to the start of the next span,
  /// since a speech model places the first word after a pause early, but not late: in the recording, the word comes
  /// after the part of the pause that was cut, and it belongs to whichever segment that is in.
  func recordingIndex(of index: Int) -> Int {
    guard let position = spans.lastIndex(where: { $0.start <= index }) ?? spans.indices.first else {
      return segment.lowerBound
    }
    if position + 1 < spans.count, index >= spans[position + 1].start - pauseSide {
      return spans[position + 1].recordingStart
    }
    return spans[position].recordingStart + index - spans[position].start
  }

  /// The samples of the segment alone, its silence shortened if the rest is.
  var segmentSamples: ArraySlice<Float> {
    let bounds = spans.compactMap { span -> Range<Int>? in
      let recording = span.recordingStart..<(span.recordingStart + span.count)
      let overlap = recording.clamped(to: segment)
      guard !overlap.isEmpty else { return nil }
      return
        (span.start + overlap.lowerBound - span.recordingStart)..<(span.start + overlap.upperBound - span.recordingStart)
    }
    guard let first = bounds.first, let last = bounds.last else { return [] }
    return samples[first.lowerBound..<last.upperBound]
  }
}

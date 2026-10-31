import Foundation
import OSLog

/// Transcribes, and refines with a built-in persona, a recording while it's still in progress, so only its last few
/// seconds are left when it ends.
///
/// The recording is cut into segments in pauses. Each segment is transcribed with a few seconds of the audio before
/// and after it, keeping only its own words, so words at a cut are heard in context. Refining follows sentence by
/// sentence, keeping the last refined sentences open so the next refine can still change them, as `LiveRefinement`
/// describes. Whatever isn't refined by the time the recording ends is refined together at the end.
@MainActor
final class LiveDictation {
  /// The `UserDefaults` key for whether recordings are transcribed while they're in progress, on unless turned off.
  static let enabledStorageKey = "transcribesWhileRecording"
  /// The `UserDefaults` key for the fewest words of refined text kept open to change while recording.
  static let openWordsStorageKey = "liveRefineOpenWords"
  /// The choices for the fewest words kept open.
  static let openWordsChoices = Array(stride(from: 0, through: 100, by: 5))
  /// The fewest words kept open unless changed: usually a sentence or two, the furthest back the user commonly takes
  /// something back.
  static let defaultOpenWords = 25

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  /// The stored fewest words kept open, or the default if it's missing or not one of the choices.
  static var storedOpenWords: Int {
    guard let stored = UserDefaults.standard.object(forKey: openWordsStorageKey) as? Int,
      openWordsChoices.contains(stored)
    else { return defaultOpenWords }
    return stored
  }

  /// Transcribes a segment, returning only its words not among the words kept before, with Sounds Like spellings
  /// swapped, along with the words kept.
  typealias Transcribe = @MainActor (SegmentAudio, [SpokenWord]) async throws -> (text: String, words: [SpokenWord])
  /// Refines text, returning it unchanged if refining fails.
  typealias Refine = @MainActor (String) async -> String

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "LiveDictation")
  /// How often the recording is checked for a segment to transcribe.
  private static let pollInterval = Duration.milliseconds(250)
  /// How much audio before a segment is transcribed with it, in seconds after its silence is shortened.
  nonisolated private static let lookback = 3.0
  /// How much audio after a segment is transcribed with it, in seconds after its silence is shortened.
  private static let lookahead = 1.5
  /// How much of the recording before a segment is searched for `lookback` seconds of audio, in seconds, so a long
  /// pause before the segment is passed over.
  private static let searchedLookback = 15.0

  private let samples: @MainActor (Int) -> [Float]?
  private let sampleRate: Double
  private let transcribe: Transcribe
  private let refine: Refine?
  private let trimmer: SilenceTrimmer?
  private let segmenter = LiveSegmenter()
  private let sliceLength: Int
  private let searchedLookbackSamples: Int

  /// The loudness of each slice recorded so far.
  private var levels: [Double] = []
  /// The transcripts of the segments so far.
  private var segments: [String] = []
  /// Where the next segment starts, in samples.
  private var segmentStart = 0
  /// The words of the last segment, which a word at the start of the next mustn't repeat.
  private var lastWords: [SpokenWord] = []
  private var refinement: LiveRefinement
  private var transcribing: Task<Void, Never>?
  private var refining: Task<Void, Never>?
  private var isFinishing = false

  /// Starts transcribing the recording.
  ///
  /// - Parameters:
  ///   - samples: Reads the recording from a sample on, returning `nil` once it has ended.
  ///   - sampleRate: The recording's sample rate, in hertz.
  ///   - transcribe: Transcribes a segment of the recording.
  ///   - refine: Refines text, or `nil` if the recording isn't refined while it's in progress.
  init(
    samples: @escaping @MainActor (Int) -> [Float]?,
    sampleRate: Double,
    transcribe: @escaping Transcribe,
    refine: Refine?
  ) {
    self.samples = samples
    self.sampleRate = sampleRate
    self.transcribe = transcribe
    self.refine = refine
    trimmer = SilenceTrimmer.isEnabled ? SilenceTrimmer() : nil
    refinement = LiveRefinement(openWords: Self.storedOpenWords)
    sliceLength = Int(SilenceTrimmer.sliceDuration * sampleRate)
    searchedLookbackSamples = Int(Self.searchedLookback * sampleRate)
    transcribing = Task { await transcribeWhileRecording() }
  }

  /// Stops working on the recording, which ended without anything to transcribe.
  func cancel() {
    isFinishing = true
    transcribing?.cancel()
  }

  /// Transcribes the rest of the recording once it has ended, and refines what isn't refined yet if it's refined.
  ///
  /// If transcribing the rest fails, the segments transcribed while recording are kept without it.
  ///
  /// - Returns: The transcript, and the refined text, or `nil` if the recording isn't refined while in progress.
  /// - Throws: The error transcribing the rest, if nothing was transcribed while recording.
  func finish(_ recording: [Float]) async throws -> (transcript: String, refined: String?) {
    isFinishing = true
    // Ends the wait for the next check. A segment cancelled while it's transcribed is transcribed with the rest.
    transcribing?.cancel()
    await transcribing?.value
    let start = ContinuousClock.now
    do {
      let searchStart = max(0, segmentStart - searchedLookbackSamples)
      let audio = await Self.segmentAudio(
        Array(recording[searchStart...]),
        from: searchStart,
        segment: segmentStart..<recording.count,
        lookahead: 0,
        trimmer: trimmer,
        sampleRate: sampleRate
      )
      let last = try await transcribe(audio, lastWords)
      segments.append(last.text)
      refinement.append(transcript: last.text)
      Self.logger.info(
        """
        Transcribed the last \(Double(recording.count - self.segmentStart) / self.sampleRate, format: .fixed(precision: 1)) \
        s in \(ContinuousClock.now - start, privacy: .public), after \(self.segments.count - 1) segments while recording
        """
      )
    } catch {
      guard segments.contains(where: { !$0.isEmpty }) else { throw error }
      Self.logger.error("Couldn't transcribe the end of the recording, so it's left out: \(error)")
    }
    let transcript = Self.joined(segments)
    guard let refine else { return (transcript, nil) }
    await refining?.value
    let text = refinement.takeLastText()
    let refined = text.isEmpty ? "" : await refine(text)
    return (transcript, refinement.finished(lastRefined: refined))
  }

  private func transcribeWhileRecording() async {
    while !isFinishing {
      try? await Task.sleep(for: Self.pollInterval)
      guard !isFinishing, measureNewAudio() else { return }
      guard let cut = segmenter.cut(levels: levels, from: segmentStart / sliceLength) else { continue }
      guard await transcribeSegment(endingAt: cut * sliceLength) else { return }
    }
  }

  /// Measures the loudness of the audio recorded since the last call, returning `false` once the recording has ended.
  private func measureNewAudio() -> Bool {
    let measured = levels.count * sliceLength
    guard let new = samples(measured) else { return false }
    let wholeSlices = new.count / sliceLength
    levels += SilenceTrimmer.sliceLevels(of: Array(new.prefix(wholeSlices * sliceLength)), sliceLength: sliceLength)
    return true
  }

  /// Transcribes the segment from `segmentStart` to `end`, returning `false` if that failed or the recording ended.
  private func transcribeSegment(endingAt end: Int) async -> Bool {
    let searchStart = max(0, segmentStart - searchedLookbackSamples)
    guard let recorded = samples(searchStart) else { return false }
    let start = ContinuousClock.now
    do {
      let audio = await Self.segmentAudio(
        Array(recorded.prefix(levels.count * sliceLength - searchStart)),
        from: searchStart,
        segment: segmentStart..<end,
        lookahead: Self.lookahead,
        trimmer: trimmer,
        sampleRate: sampleRate
      )
      let transcribed = try await transcribe(audio, lastWords)
      Self.logger.info(
        """
        Transcribed a segment of \(Double(end - self.segmentStart) / self.sampleRate, format: .fixed(precision: 1)) s \
        while recording in \(ContinuousClock.now - start, privacy: .public)
        """
      )
      segments.append(transcribed.text)
      refinement.append(transcript: transcribed.text)
      if !transcribed.words.isEmpty {
        lastWords = transcribed.words
      }
      segmentStart = end
      refineWhatIsReady()
      return true
    } catch {
      // The rest of the recording is transcribed once it ends.
      Self.logger.error("Couldn't transcribe a segment while recording: \(error)")
      return false
    }
  }

  /// Refines the open text and the sentences transcribed since, if there are any and nothing else is refining.
  private func refineWhatIsReady() {
    guard let refine, refining == nil, !isFinishing, let text = refinement.takeText() else { return }
    refining = Task {
      let start = ContinuousClock.now
      let refined = await refine(text)
      Self.logger.info("Refined sentences while recording in \(ContinuousClock.now - start, privacy: .public)")
      refinement.refined(refined)
      refining = nil
      refineWhatIsReady()
    }
  }

  /// Runs off the main actor, since shortening the silence grows with the audio searched.
  @concurrent
  nonisolated private static func segmentAudio(
    _ audio: [Float],
    from offset: Int,
    segment: Range<Int>,
    lookahead: Double,
    trimmer: SilenceTrimmer?,
    sampleRate: Double
  ) async -> SegmentAudio {
    SegmentAudio(
      audio,
      from: offset,
      segment: segment,
      lookback: lookback,
      lookahead: lookahead,
      trimmer: trimmer,
      sampleRate: sampleRate
    )
  }

  private static func joined(_ texts: some Sequence<String>) -> String {
    texts.filter { !$0.isEmpty }.joined(separator: " ")
  }
}

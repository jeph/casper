import Foundation
import OSLog

/// Transcribes, and refines with a built-in persona, a recording while it's still in progress, so only its last few
/// seconds are left when it ends.
///
/// The recording is cut into segments in pauses. Each segment is transcribed with a few seconds of the audio before
/// and after it, keeping only its own words, so words at a cut are heard in context. Refining goes in blocks of
/// segments, each refined once two newer segments have been transcribed, so taking something back in the next sentence
/// or two still reaches the words it replaces. Whatever isn't refined by the time the recording ends is refined
/// together at the end.
@MainActor
final class LiveDictation {
  /// The `UserDefaults` key for whether recordings are transcribed while they're in progress, on unless turned off.
  static let enabledStorageKey = "transcribesWhileRecording"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  /// Transcribes samples starting at an index in the recording, returning only the words spoken in a range of them
  /// and not among the words kept before, with Sounds Like spellings swapped, along with the words kept.
  typealias Transcribe =
    @MainActor ([Float], Int, Range<Int>, [ParakeetTranscriber.SpokenWord]) async throws -> (
      text: String, words: [ParakeetTranscriber.SpokenWord]
    )
  /// Refines text, returning it unchanged if refining fails.
  typealias Refine = @MainActor (String) async -> String

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "LiveDictation")
  /// How often the recording is checked for a segment to transcribe.
  private static let pollInterval = Duration.milliseconds(250)
  /// How much audio before a segment is transcribed with it, in seconds.
  private static let lookback = 3.0
  /// How many words a block needs before it's refined, so blocks aren't cut at every short segment.
  private static let shortestBlock = 20
  /// How many transcribed segments must follow a block before it's refined.
  private static let segmentsAfterBlock = 2

  private let samples: @MainActor (Int) -> [Float]?
  private let sampleRate: Double
  private let transcribe: Transcribe
  private let refine: Refine?
  private let segmenter = LiveSegmenter()
  private let sliceLength: Int
  private let lookbackSamples: Int
  private let lookaheadSamples: Int

  /// The loudness of each slice recorded so far.
  private var levels: [Double] = []
  /// The transcripts of the segments so far.
  private var segments: [String] = []
  /// Where the next segment starts, in samples.
  private var segmentStart = 0
  /// The words of the last segment, which a word at the start of the next mustn't repeat.
  private var lastWords: [ParakeetTranscriber.SpokenWord] = []
  /// The refined text of each block refined so far.
  private var refinedBlocks: [String] = []
  /// How many segments the refined blocks hold.
  private var refinedSegments = 0
  private var transcribing: Task<Void, Never>?
  private var refining: Task<Void, Never>?
  private var isFinishing = false

  /// Starts transcribing the recording.
  ///
  /// - Parameters:
  ///   - samples: Reads the recording from a sample on, returning `nil` once it has ended.
  ///   - sampleRate: The recording's sample rate, in hertz.
  ///   - transcribe: Transcribes part of the recording.
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
    sliceLength = Int(SilenceTrimmer.sliceDuration * sampleRate)
    lookbackSamples = Int(Self.lookback * sampleRate)
    lookaheadSamples = Int(segmenter.lookahead * sampleRate)
    transcribing = Task { await transcribeWhileRecording() }
  }

  /// Stops working on the recording, which ended without anything to transcribe.
  func cancel() {
    isFinishing = true
    transcribing?.cancel()
  }

  /// Transcribes the rest of the recording once it has ended, and refines what isn't refined yet if it's refined.
  ///
  /// - Returns: The transcript, and the refined text, or `nil` if the recording isn't refined while in progress.
  func finish(_ recording: [Float]) async throws -> (transcript: String, refined: String?) {
    isFinishing = true
    // Ends the wait for the next check. A segment cancelled while it's transcribed is transcribed with the rest.
    transcribing?.cancel()
    await transcribing?.value
    let start = ContinuousClock.now
    let contextStart = max(0, segmentStart - lookbackSamples)
    let last = try await transcribe(
      Array(recording[contextStart...]),
      contextStart,
      (segmentStart - contextStart)..<(recording.count - contextStart),
      lastWords
    )
    segments.append(last.text)
    Self.logger.info(
      """
      Transcribed the last \(Double(recording.count - self.segmentStart) / self.sampleRate, format: .fixed(precision: 1)) \
      s in \(ContinuousClock.now - start, privacy: .public), after \(self.segments.count - 1) segments while recording
      """
    )
    let transcript = Self.joined(segments)
    guard let refine else { return (transcript, nil) }
    await refining?.value
    let rest = Self.joined(segments[refinedSegments...])
    let refined = rest.isEmpty ? "" : await refine(rest)
    return (transcript, Self.joined(refinedBlocks + [refined]))
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
    let contextStart = max(0, segmentStart - lookbackSamples)
    let contextEnd = min(end + lookaheadSamples, levels.count * sliceLength)
    guard let audio = samples(contextStart) else { return false }
    let start = ContinuousClock.now
    do {
      let transcribed = try await transcribe(
        Array(audio.prefix(contextEnd - contextStart)),
        contextStart,
        (segmentStart - contextStart)..<(end - contextStart),
        lastWords
      )
      Self.logger.info(
        """
        Transcribed a segment of \(Double(end - self.segmentStart) / self.sampleRate, format: .fixed(precision: 1)) s \
        while recording in \(ContinuousClock.now - start, privacy: .public)
        """
      )
      segments.append(transcribed.text)
      if !transcribed.words.isEmpty {
        lastWords = transcribed.words
      }
      segmentStart = end
      refineSettledBlock()
      return true
    } catch {
      // The rest of the recording is transcribed once it ends.
      Self.logger.error("Couldn't transcribe a segment while recording: \(error)")
      return false
    }
  }

  /// Refines the segments before the last two not refined yet, if they're long enough and nothing else is refining.
  private func refineSettledBlock() {
    guard let refine, refining == nil, !isFinishing else { return }
    let end = segments.count - Self.segmentsAfterBlock
    guard end > refinedSegments else { return }
    let block = Self.joined(segments[refinedSegments..<end])
    guard RefinePersona.wordCount(of: block) >= Self.shortestBlock else { return }
    refining = Task {
      let start = ContinuousClock.now
      let refined = await refine(block)
      Self.logger.info("Refined a block while recording in \(ContinuousClock.now - start, privacy: .public)")
      refinedBlocks.append(refined)
      refinedSegments = end
      refining = nil
      refineSettledBlock()
    }
  }

  private static func joined(_ texts: some Sequence<String>) -> String {
    texts.filter { !$0.isEmpty }.joined(separator: " ")
  }
}

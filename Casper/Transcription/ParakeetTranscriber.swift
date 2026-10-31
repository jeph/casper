import FluidAudio
import Foundation
import OSLog

/// Transcribes with a Parakeet TDT model through FluidAudio, correcting misheard dictionary words with FluidAudio's
/// word spotter.
///
/// Parakeet writes each token at a point in the audio and can't go past its end, and FluidAudio caps the tokens in
/// each 15-second window, so its transcripts are already bounded by the length of the audio.
actor ParakeetTranscriber: Transcriber {
  enum TranscriptionError: Error {
    case unloaded
  }

  /// The word spotter, which downloads after Parakeet for models installed before Casper had one.
  private enum WordSpotterState {
    case notInstalled
    case loading(Task<WordSpotter?, Never>)
    case loaded(WordSpotter)
    case failed
  }

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Parakeet")

  private var manager: AsrManager?
  private let decoderLayers: Int
  private let wordSpotterDirectory: URL
  private var wordSpotter: WordSpotterState
  /// Each dictionary word's token IDs by spelling, so a changed dictionary only tokenizes the words that changed.
  private var tokenIDs: [String: [Int]] = [:]
  /// The dictionary as the word spotter's terms, rebuilt when the dictionary changes.
  private var vocabulary: WordSpotter.Vocabulary?

  /// Loads Parakeet and, if it's installed, the word spotter alongside it, so turning the dictionary on or adding a
  /// word never waits on a model load.
  init(models: AsrModels, wordSpotterDirectory: URL) async throws {
    let isWordSpotterInstalled = FileManager.default.fileExists(
      atPath: wordSpotterDirectory.path(percentEncoded: false)
    )
    async let wordSpotter = Self.loadWordSpotter(from: wordSpotterDirectory)
    let manager = AsrManager()
    try await manager.loadModels(models)
    self.manager = manager
    decoderLayers = models.version.decoderLayers
    self.wordSpotterDirectory = wordSpotterDirectory
    let spotter = await wordSpotter
    self.wordSpotter = spotter.map(WordSpotterState.loaded) ?? (isWordSpotterInstalled ? .failed : .notInstalled)
  }

  /// FluidAudio takes samples at 16 kHz only, which `SpeechModel.sampleRate` records at.
  func transcribe(_ samples: [Float], sampleRate: Double, dictionary: [DictionaryWord]) async throws -> String {
    guard let manager else { throw TranscriptionError.unloaded }
    // Each recording is transcribed on its own, so the decoder starts fresh rather than continuing the last one.
    var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
    let result = try await manager.transcribe(samples, decoderState: &decoderState)
    let replacements = await replacements(
      in: result.text,
      tokenTimings: result.tokenTimings,
      samples: samples,
      dictionary: dictionary
    )
    return DictionaryCorrection.replace(replacements, in: result.text).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A word Parakeet heard, and when it starts, in seconds from the start of the recording.
  struct SpokenWord: Sendable, Equatable {
    let text: String
    let start: TimeInterval
  }

  /// How far apart two transcriptions of the same audio can place a word, in seconds.
  ///
  /// Parakeet's timing for a word after a pause can come early by a few frames, and by different amounts depending on
  /// the audio around it.
  static let timingTolerance = 0.35

  /// Transcribes part of a recording, `samples`, but returns only the words spoken in `kept`, a range of its indices.
  ///
  /// The audio on either side gives the model context, so the words at the edges of `kept` are heard, capitalized and
  /// punctuated as they are within the whole recording. A word belongs to `kept` if it starts there. Since timings
  /// shift between transcriptions, a word up to `timingTolerance` before `kept` counts too, unless it's one of the
  /// `previous` words, the last ones kept from the audio before.
  ///
  /// - Parameters:
  ///   - samples: The part of the recording to transcribe.
  ///   - offset: The index in the recording of the first of `samples`.
  ///   - kept: The indices in `samples` whose words to return.
  ///   - previous: The last words kept from the audio before `kept`.
  ///   - sampleRate: The recording's sample rate, in hertz.
  ///   - dictionary: The dictionary's words.
  /// - Returns: The text of the words in `kept`, and the words as Parakeet heard them.
  /// - Throws: `TranscriptionError.unloaded` once the model is unloaded, or FluidAudio's error if transcribing fails.
  func transcribe(
    _ samples: [Float],
    from offset: Int,
    keeping kept: Range<Int>,
    after previous: [SpokenWord],
    sampleRate: Double,
    dictionary: [DictionaryWord]
  ) async throws -> (text: String, words: [SpokenWord]) {
    guard let manager else { throw TranscriptionError.unloaded }
    var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
    let result = try await manager.transcribe(samples, decoderState: &decoderState)
    guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
      // Without timings the words can't be placed, and repeating a few words beats losing them.
      return (result.text.trimmingCharacters(in: .whitespacesAndNewlines), [])
    }
    let offsetSeconds = Double(offset) / sampleRate
    let start = Double(kept.lowerBound) / sampleRate
    let end = Double(kept.upperBound) / sampleRate
    var words = Self.words(in: tokenTimings).filter { $0.start >= start - Self.timingTolerance && $0.start < end }
    let spoken = { (word: (tokens: ArraySlice<TokenTiming>, start: TimeInterval)) in
      SpokenWord(text: word.tokens.map(\.token).joined(), start: offsetSeconds + word.start)
    }
    words.removeFirst(Self.repeatedCount(of: words.map(spoken), after: previous))
    guard let first = words.first, let last = words.last else { return ("", []) }
    let keptTokens = words.flatMap(\.tokens)
    // The kept words are found in the transcript by the length of the tokens before them, which needs the transcript
    // to be its tokens.
    guard result.text == tokenTimings.map(\.token).joined().trimmingCharacters(in: .whitespaces) else {
      Self.logger.error("Parakeet's transcript isn't its tokens, so the word spotter doesn't check it")
      return (keptTokens.map(\.token).joined().trimmingCharacters(in: .whitespaces), words.map(spoken))
    }
    // The word spotter checks the whole transcript against all the audio, as it does a whole recording, since a word
    // it finds in the audio around the kept words would otherwise be matched to a kept one.
    let replacements = await replacements(
      in: result.text,
      tokenTimings: tokenTimings,
      samples: samples,
      dictionary: dictionary
    )
    // The kept words' place in the transcript, which leaves out the space the first token starts with.
    let leadingSpace = tokenTimings[0].token.utf8.prefix { $0 == UInt8(ascii: " ") }.count
    func length(_ tokens: ArraySlice<TokenTiming>) -> Int { tokens.reduce(0) { $0 + $1.token.utf8.count } }
    let utf8 = result.text.utf8
    let keptStart = max(0, length(tokenTimings[..<first.tokens.startIndex]) - leadingSpace)
    let keptEnd = min(utf8.count, length(tokenTimings[..<last.tokens.endIndex]) - leadingSpace)
    let lower = utf8.index(utf8.startIndex, offsetBy: keptStart)
    let upper = utf8.index(utf8.startIndex, offsetBy: keptEnd)
    let keptText = String(result.text[lower..<upper])
    let keptUTF8 = keptText.utf8
    let keptReplacements = replacements.compactMap { replacement -> DictionaryCorrection.Replacement? in
      guard replacement.range.lowerBound >= lower, replacement.range.upperBound <= upper else { return nil }
      let start = keptUTF8.index(
        keptUTF8.startIndex,
        offsetBy: utf8.distance(from: lower, to: replacement.range.lowerBound)
      )
      let end = keptUTF8.index(
        keptUTF8.startIndex,
        offsetBy: utf8.distance(from: lower, to: replacement.range.upperBound)
      )
      return DictionaryCorrection.Replacement(range: start..<end, word: replacement.word)
    }
    let text = DictionaryCorrection.replace(keptReplacements, in: keptText)
    return (text.trimmingCharacters(in: .whitespacesAndNewlines), words.map(spoken))
  }

  /// The tokens of each word, along with the punctuation after it, and when the word starts.
  ///
  /// FluidAudio writes a space in place of SentencePiece's word boundary, so a token that starts a word starts with one.
  static func words(in timings: [TokenTiming]) -> [(tokens: ArraySlice<TokenTiming>, start: TimeInterval)] {
    let starts = timings.indices.filter { $0 == timings.startIndex || timings[$0].token.hasPrefix(" ") }
    return starts.indices.map { index in
      let end = index + 1 < starts.count ? starts[index + 1] : timings.endIndex
      return (timings[starts[index]..<end], timings[starts[index]].startTime)
    }
  }

  /// How many of the first `words` repeat the last of `previous`: the same words, ignoring case and punctuation, at
  /// about the same time.
  static func repeatedCount(of words: [SpokenWord], after previous: [SpokenWord]) -> Int {
    func matches(_ word: SpokenWord, _ earlier: SpokenWord) -> Bool {
      normalized(word.text) == normalized(earlier.text) && abs(word.start - earlier.start) <= timingTolerance
    }
    let longest = min(words.count, previous.count)
    return (0...longest)
      .last { count in
        zip(words.prefix(count), previous.suffix(count)).allSatisfy(matches)
      } ?? 0
  }

  private static func normalized(_ word: String) -> String {
    String(word.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  func prepare(for dictionary: [DictionaryWord]) async {
    guard manager != nil else { return }
    if case .loading(let load) = startLoadingInstalledWordSpotter() {
      _ = await load.value
    }
    guard case .loaded(let spotter) = wordSpotter else { return }
    _ = await vocabulary(for: dictionary, spotter: spotter)
  }

  func unload() async {
    await manager?.cleanup()
    manager = nil
    vocabulary = nil
    wordSpotter = .failed
  }

  /// The dictionary words the audio supports in place of words in Parakeet's transcript.
  ///
  /// Without the word spotter, or if checking fails, there are none, so the dictionary can never stop a dictation.
  private func replacements(
    in text: String,
    tokenTimings: [TokenTiming]?,
    samples: [Float],
    dictionary: [DictionaryWord]
  ) async -> [DictionaryCorrection.Replacement] {
    guard !dictionary.isEmpty, case .loaded(let spotter) = startLoadingInstalledWordSpotter(),
      let tokenTimings, !tokenTimings.isEmpty,
      let vocabulary = await vocabulary(for: dictionary, spotter: spotter)
    else { return [] }
    do {
      let replacements = try await spotter.replacements(
        in: text,
        tokenTimings: tokenTimings,
        samples: samples,
        vocabulary: vocabulary
      )
      Self.logger.info("The word spotter replaced \(replacements.count) words")
      return replacements
    } catch {
      Self.logger.error("Couldn't check the transcript with the word spotter: \(error)")
      return []
    }
  }

  /// The word spotter's terms for a dictionary, reusing the last ones while the dictionary is unchanged.
  private func vocabulary(for dictionary: [DictionaryWord], spotter: WordSpotter) async -> WordSpotter.Vocabulary? {
    if let vocabulary, vocabulary.words == dictionary { return vocabulary }
    var tokenIDs: [String: [Int]] = [:]
    for word in dictionary {
      tokenIDs[word.text] = self.tokenIDs[word.text] ?? spotter.tokenIDs(of: word.text)
    }
    // Only the current words' tokens are kept, so deleted words don't pile up.
    self.tokenIDs = tokenIDs
    do {
      let start = ContinuousClock.now
      vocabulary = try await spotter.vocabulary(for: dictionary, tokenIDs: tokenIDs)
      Self.logger.info(
        "Built the word spotter's terms for \(dictionary.count) words in \(ContinuousClock.now - start, privacy: .public)"
      )
    } catch {
      Self.logger.error("Couldn't build the word spotter's terms: \(error)")
      vocabulary = nil
    }
    return vocabulary
  }

  /// Starts loading the word spotter if it was installed since Parakeet loaded, and returns its state.
  ///
  /// It loads in the background, and dictations go without it until it's ready.
  private func startLoadingInstalledWordSpotter() -> WordSpotterState {
    guard case .notInstalled = wordSpotter,
      FileManager.default.fileExists(atPath: wordSpotterDirectory.path(percentEncoded: false))
    else { return wordSpotter }
    let directory = wordSpotterDirectory
    let load = Task { await Self.loadWordSpotter(from: directory) }
    wordSpotter = .loading(load)
    Task {
      let spotter = await load.value
      finishLoading(spotter)
    }
    return wordSpotter
  }

  private func finishLoading(_ spotter: WordSpotter?) {
    // An unload while it loaded leaves the transcriber unusable, so the word spotter is dropped.
    guard case .loading = wordSpotter else { return }
    wordSpotter = spotter.map(WordSpotterState.loaded) ?? .failed
  }

  /// Loads the word spotter, or returns `nil` if it isn't installed or can't load.
  private static func loadWordSpotter(from directory: URL) async -> WordSpotter? {
    guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return nil }
    do {
      let start = ContinuousClock.now
      let spotter = try await WordSpotter.load(from: directory)
      logger.info("Loaded the word spotter in \(ContinuousClock.now - start, privacy: .public)")
      return spotter
    } catch {
      logger.error("Couldn't load the word spotter, so dictations go without it: \(error)")
      return nil
    }
  }
}

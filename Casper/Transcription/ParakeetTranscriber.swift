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
    let text = await corrected(result, samples: samples, dictionary: dictionary)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

  /// Parakeet's transcript with dictionary words in place of the words the audio says they were.
  ///
  /// Without the word spotter, or if correcting fails, the transcript is returned as Parakeet wrote it, so the
  /// dictionary can never stop a dictation.
  private func corrected(_ result: ASRResult, samples: [Float], dictionary: [DictionaryWord]) async -> String {
    guard !dictionary.isEmpty, case .loaded(let spotter) = startLoadingInstalledWordSpotter(),
      let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty,
      let vocabulary = await vocabulary(for: dictionary, spotter: spotter)
    else { return result.text }
    do {
      let replacements = try await spotter.replacements(
        in: result.text,
        tokenTimings: tokenTimings,
        samples: samples,
        vocabulary: vocabulary
      )
      Self.logger.info("The word spotter replaced \(replacements.count) words")
      return DictionaryCorrection.replace(replacements, in: result.text)
    } catch {
      Self.logger.error("Couldn't check the transcript with the word spotter: \(error)")
      return result.text
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

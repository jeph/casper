import FluidAudio
import Foundation

/// FluidAudio's CTC word spotter: a second, smaller model that checks Parakeet's transcript against the audio and finds
/// where a dictionary word fits better than what Parakeet wrote.
///
/// Parakeet's decoder can't be steered toward words, so its transcript is corrected afterward, with NeMo's CTC-WS
/// method as FluidAudio implements it (FluidAudio's `Documentation/ASR/CustomVocabulary.md`). This repeats the steps of
/// FluidAudio's `VocabularyBoostingSession`, which reads its files from FluidAudio's own folder, so the model can live
/// with Casper's other models. The model is English only.
struct WordSpotter: Sendable {
  /// The dictionary as terms the word spotter checks transcripts against.
  struct Vocabulary: Sendable {
    /// The words the terms were built from.
    let words: [DictionaryWord]
    fileprivate let context: CustomVocabularyContext
    fileprivate let rescorer: VocabularyRescorer
    fileprivate let thresholds: ContextBiasingConstants.VocabSizeConfig
  }

  private let spotter: CtcKeywordSpotter
  private let tokenizer: CtcTokenizer
  private let directory: URL

  /// The word spotter's model, which downloads, installs and deletes with Casper's Parakeet models.
  static let files = ModelRepository(
    id: "parakeet-ctc-110m-coreml",
    repository: "FluidInference/parakeet-ctc-110m-coreml",
    revision: "accdafd8cf8a2ff1cabe3c11e54416b405d409aa",
    files: ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "vocab.json", "tokenizer.json"],
    downloadSize: 102_802_455
  )

  /// FluidAudio's settings for dictionaries of short words that sound like ordinary English, which its
  /// `CustomVocabulary.md` recommends.
  ///
  /// Every value is set, since the library's defaults read `FLUID_*` environment variables.
  private static let rescorerConfig = VocabularyRescorer.Config(
    useAdaptiveThresholds: true,
    referenceTokenCount: 3,
    // Words under 5 tokens get a boost scaled by (tokens ÷ 5)², so short words can't win too easily.
    shortTermCbwTaperPivot: 5,
    shortTermCbwTaperExponent: 2,
    // The rescue pass, which swaps in a word wherever the audio sounds like it, only replaces text spelled at least
    // 30% like the word, or 50% for several words.
    spotterRescueMinSimilarity: 0.30,
    spotterRescueMultiWordMinSimilarity: 0.50,
    spotterRescueEnabled: true
  )

  /// How alike a transcript word and a dictionary word must be spelled before the audio is checked, at least.
  ///
  /// FluidAudio uses 0.50 for dictionaries of up to 100 words, which lets 4-letter words with two letters changed
  /// through, so in testing "milk" became "MLX", "joined" became "Aoife" and "send" became "Zed". 0.55, FluidAudio's
  /// value for larger dictionaries, stopped all three and kept every other fix. It also stops "Jeff" becoming "Jeph",
  /// which a Sounds Like spelling still does.
  private static let minimumSimilarity: Float = 0.55

  static func load(from directory: URL) async throws -> WordSpotter {
    async let models = CtcModels.loadDirect(from: directory, variant: .ctc110m)
    async let tokenizer = CtcTokenizer.load(from: directory)
    let loadedModels = try await models
    return WordSpotter(
      spotter: CtcKeywordSpotter(models: loadedModels, blankId: loadedModels.vocabulary.count),
      tokenizer: try await tokenizer,
      directory: directory
    )
  }

  /// The model's token IDs for a word's spelling.
  func tokenIDs(of text: String) -> [Int] {
    tokenizer.encode(text)
  }

  /// Builds the terms for a dictionary, from each word's token IDs by spelling, or `nil` if no word has any.
  ///
  /// A word's Sounds Like spellings decide which of Parakeet's words it's compared with; the audio is then checked
  /// against the word's own tokens. Words under 3 characters are left out.
  func vocabulary(for words: [DictionaryWord], tokenIDs: [String: [Int]]) async throws -> Vocabulary? {
    let terms = words.compactMap { word -> CustomVocabularyTerm? in
      guard let ids = tokenIDs[word.text], !ids.isEmpty else { return nil }
      return CustomVocabularyTerm(
        text: word.text,
        aliases: word.soundsLike.isEmpty ? nil : word.soundsLike,
        ctcTokenIds: ids
      )
    }
    guard !terms.isEmpty else { return nil }
    let context = CustomVocabularyContext(terms: terms, minTermLength: 3)
    let rescorer = try await VocabularyRescorer.create(
      spotter: spotter,
      vocabulary: context,
      config: Self.rescorerConfig,
      ctcModelDirectory: directory
    )
    return Vocabulary(
      words: words,
      context: context,
      rescorer: rescorer,
      thresholds: ContextBiasingConstants.rescorerConfig(forVocabSize: terms.count)
    )
  }

  /// The dictionary words the audio supports in place of words in Parakeet's transcript.
  ///
  /// The transcript itself is left alone, rather than taking the text FluidAudio rebuilds from word timings, which
  /// loses punctuation next to a replaced word. Replacements whose place in the transcript FluidAudio couldn't find
  /// are skipped.
  func replacements(
    in transcript: String,
    tokenTimings: [TokenTiming],
    samples: [Float],
    vocabulary: Vocabulary
  ) async throws -> [DictionaryCorrection.Replacement] {
    guard !samples.isEmpty else { return [] }
    let (padded, lastWindowSamples) = Self.paddedToWholeWindows(samples)
    let spotted = try await spotter.spotKeywordsWithLogProbs(
      audioSamples: padded,
      customVocabulary: vocabulary.context,
      minScore: nil
    )
    guard spotted.frameDuration > 0, !spotted.logProbs.isEmpty else { return [] }
    let (logProbs, frameDuration) = Self.trimmedToAudio(
      spotted.logProbs,
      frameDuration: spotted.frameDuration,
      sampleCount: samples.count,
      lastWindowSamples: lastWindowSamples
    )
    let evidence = vocabulary.rescorer.ctcTokenEvaluateCandidates(
      transcript: transcript,
      tokenTimings: tokenTimings,
      logProbs: logProbs,
      frameDuration: frameDuration,
      cbw: vocabulary.thresholds.cbw,
      marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
      minSimilarity: max(vocabulary.thresholds.minSimilarity, Self.minimumSimilarity)
    )
    let utf8 = transcript.utf8
    return evidence.candidates.compactMap { candidate in
      guard candidate.legacyOutcome == .applied, let offsets = candidate.baseTextUTF8Range,
        offsets.lowerBound >= 0, offsets.upperBound <= utf8.count,
        let start = String.Index(utf8.index(utf8.startIndex, offsetBy: offsets.lowerBound), within: transcript),
        let end = String.Index(utf8.index(utf8.startIndex, offsetBy: offsets.upperBound), within: transcript)
      else { return nil }
      return DictionaryCorrection.Replacement(range: start..<end, word: candidate.canonicalTerm)
    }
  }

  /// The word spotter's model reads 15-second windows, overlapping by 2 seconds for longer audio.
  private static let window = ASRConstants.maxModelSamples
  /// FluidAudio's `CtcKeywordSpotter.chunkOverlapSamples`, which isn't public.
  private static let windowStride = window - 32_000

  /// The samples followed by silence up to the end of their last window, and how many samples of that window are audio.
  ///
  /// FluidAudio 0.17.5 and earlier copy a shorter window into a new `MLMultiArray` and treat the rest as silence, but
  /// Core ML doesn't zero new arrays, so leftover memory reaches the model and changes which words get replaced from one
  /// dictation to the next. The model ignores the length it's given, so silence written here gives the result
  /// FluidAudio intends, with the windows starting where they would.
  static func paddedToWholeWindows(_ samples: [Float]) -> (samples: [Float], lastWindowSamples: Int) {
    let laterWindows =
      samples.count > window ? (samples.count - window + windowStride - 1) / windowStride : 0
    let paddedCount = window + laterWindows * windowStride
    return (samples + repeatElement(0, count: paddedCount - samples.count), samples.count - laterWindows * windowStride)
  }

  /// The log-probabilities FluidAudio would return for the unpadded samples: it keeps only the last window's frames
  /// that cover audio, and for audio shorter than one window, spreads the audio over those frames.
  static func trimmedToAudio(
    _ logProbs: [[Float]],
    frameDuration: Double,
    sampleCount: Int,
    lastWindowSamples: Int
  ) -> (logProbs: [[Float]], frameDuration: Double) {
    let sampleRate = Double(ASRConstants.sampleRate)
    let windowFrames = Int((Double(window) / (frameDuration * sampleRate)).rounded())
    let audioFrames = Int(ceil(Double(lastWindowSamples) / (Double(window) / Double(windowFrames))))
    let keptFrames = max(1, min(audioFrames, windowFrames))
    let trimmed = Array(logProbs.dropLast(windowFrames - keptFrames))
    guard sampleCount < window else { return (trimmed, frameDuration) }
    return (trimmed, Double(sampleCount) / Double(keptFrames) / sampleRate)
  }
}

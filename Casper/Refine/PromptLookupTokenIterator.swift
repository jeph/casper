import Foundation
import MLX
import MLXLMCommon

/// Generates tokens with prompt lookup decoding, which guesses the next tokens and has the model check them together.
///
/// The guess is whatever followed the latest few tokens where they last appeared in the transcript or output, and the
/// start of the transcript before anything is written. A refined transcript mostly repeats the transcript, so guesses
/// are often right, and each right guess saves a pass through the model. The rest of the prompt isn't searched: its
/// examples matched the latest tokens more recently than the transcript did and led guesses astray, and the end of the
/// last example's answer was always the first guess. The model checks every guess and writes its own token where one
/// is wrong, so the output is what it writes without guessing, except where two tokens score within rounding of each
/// other: reading several tokens in one pass rounds a little differently than reading them one at a time, which can
/// pick the other token. Rejected guesses are dropped from the cache, which only caches that can be trimmed support.
struct PromptLookupTokenIterator: TokenIteratorProtocol {
  /// The longest run of latest tokens looked up, since longer matches make better guesses.
  private static let longestMatch = 3
  /// The `UserDefaults` key for whether refining guesses ahead with models that support it, on unless turned off.
  static let enabledStorageKey = "promptLookupDecoding"
  /// The `UserDefaults` key for the most tokens guessed at once.
  static let mostGuessesStorageKey = "promptLookupMostGuesses"
  /// The choices for the most tokens guessed at once.
  static let mostGuessesRange = 1...5
  /// The most tokens guessed at once unless changed.
  ///
  /// Each guessed token makes a pass slower, and on an M5 refines were fastest with one or two, since longer guesses
  /// are more often wrong past their first tokens.
  static let defaultMostGuesses = 2

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  /// The stored most tokens guessed at once, or the default if it's missing or out of range.
  static var storedMostGuesses: Int {
    guard let stored = UserDefaults.standard.object(forKey: mostGuessesStorageKey) as? Int,
      mostGuessesRange.contains(stored)
    else { return defaultMostGuesses }
    return stored
  }

  /// The most tokens guessed at once.
  private let mostGuesses: Int

  private let model: any MLXLMCommon.LanguageModel
  private let cache: [KVCache]
  private var state: LMOutput.State?
  private let sampler: LogitSampler
  /// The transcript followed by the tokens written so far, where guesses are looked up.
  private var searched: [Int]
  /// How many tokens of `searched` are the transcript's.
  private let transcriptLength: Int
  /// Tokens the model reads next: what's left of the prompt at first, then the last token it wrote.
  private var unread: [Int] = []
  /// Tokens the model wrote in its latest pass that haven't been returned yet.
  private var written: ArraySlice<Int> = []

  let maxTokens: Int?
  private(set) var tokenCount = 0
  private(set) var promptPrefillTime: TimeInterval = 0

  /// Creates an iterator that continues a prompt, of which the model reads `input` and `cache` holds the rest, and
  /// takes its guesses from `transcript`, the transcript's tokens.
  init(
    input: LMInput,
    transcript: [Int],
    model: any MLXLMCommon.LanguageModel,
    cache: [KVCache],
    sampler: LogitSampler,
    maxTokens: Int?,
    mostGuesses: Int
  ) throws {
    guard canTrimPromptCache(cache) else { throw UntrimmableCache() }
    self.model = model
    self.cache = cache
    self.sampler = sampler
    self.maxTokens = maxTokens
    self.mostGuesses = mostGuesses
    searched = transcript
    transcriptLength = transcript.count
    let start = Date.timeIntervalSinceReferenceDate
    switch try model.prepare(input, cache: cache, windowSize: nil) {
    case .tokens(let rest):
      unread = rest.tokens.asArray(Int.self)
    case .logits(let result):
      state = result.state
      let token = sampler.sample(logits: result.logits[0..., -1, 0...]).item(Int.self)
      unread = [token]
      written = [token]
      searched.append(token)
    }
    promptPrefillTime = Date.timeIntervalSinceReferenceDate - start
  }

  mutating func next() -> Int? {
    if let maxTokens, tokenCount >= maxTokens {
      return nil
    }
    if written.isEmpty {
      writeTokens()
    }
    guard let token = written.popFirst() else { return nil }
    tokenCount += 1
    return token
  }

  /// Runs the model once over the unread tokens and a guess of the ones after them, keeping the guesses it agrees with
  /// and its own next token.
  private mutating func writeTokens() {
    // Each pass writes the right guesses plus one token, which mustn't pass the limit.
    let room = maxTokens.map { $0 - tokenCount - 1 } ?? mostGuesses
    let guesses = Array(guess().prefix(Swift.max(0, Swift.min(room, mostGuesses))))
    let input = unread + guesses
    let result = model(LMInput.Text(tokens: MLXArray(input))[text: .newAxis], cache: cache, state: state)
    state = result.state
    // The logits at the last unread token and at each guess predict the token after it.
    let logits = result.logits[0, (unread.count - 1)..., 0...]
    let predicted = sampler.sample(logits: logits).asArray(Int.self)
    let agreed = zip(guesses, predicted).prefix { $0 == $1 }.count
    trimPromptCache(cache, numTokens: guesses.count - agreed)
    let tokens = guesses[..<agreed] + [predicted[agreed]]
    written = tokens
    searched += tokens
    unread = [predicted[agreed]]
  }

  /// The tokens that followed the latest written tokens where they last appeared before, trying the longest match
  /// first, or the start of the transcript before anything is written.
  private func guess() -> ArraySlice<Int> {
    let writtenCount = searched.count - transcriptLength
    guard writtenCount > 0 else { return searched.prefix(mostGuesses) }
    for length in stride(from: Swift.min(Self.longestMatch, writtenCount), through: 1, by: -1) {
      let latest = searched.suffix(length)
      for start in stride(from: searched.count - length - 1, through: 0, by: -1)
      where searched[start..<(start + length)].elementsEqual(latest) {
        let next = start + length
        return searched[next..<Swift.min(next + mostGuesses, searched.count)]
      }
    }
    return []
  }

  /// Thrown for a cache that can't drop rejected guesses.
  struct UntrimmableCache: Error {}
}

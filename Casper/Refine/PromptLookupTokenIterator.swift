import Foundation
import MLX
import MLXLMCommon

/// Generates tokens with prompt lookup decoding, which guesses the next tokens and has the model check them together.
///
/// The guess is whatever followed the latest few tokens where they last appeared in the prompt or output. A refined
/// transcript mostly repeats the transcript, so guesses are often right, and each right guess saves a pass through the
/// model. The model checks every guess and writes its own token where one is wrong, so greedy output is the same as
/// without guessing. Rejected guesses are dropped from the cache, which only caches that can be trimmed support.
struct PromptLookupTokenIterator: TokenIteratorProtocol {
  /// The longest run of latest tokens looked up, since longer matches make better guesses.
  private static let longestMatch = 3
  /// The most tokens guessed at once.
  ///
  /// Each guessed token makes a pass slower, and on an M5 refines were fastest with one or two, since longer guesses
  /// are more often wrong past their first tokens.
  private static let mostGuesses = 2

  private let model: any LanguageModel
  private let cache: [KVCache]
  private var state: LMOutput.State?
  private let sampler: LogitSampler
  /// The prompt and the tokens written so far, where guesses are looked up.
  private var history: [Int]
  /// Tokens the model reads next: what's left of the prompt at first, then the last token it wrote.
  private var unread: [Int] = []
  /// Tokens the model wrote in its latest pass that haven't been returned yet.
  private var written: ArraySlice<Int> = []

  let maxTokens: Int?
  private(set) var tokenCount = 0
  private(set) var promptPrefillTime: TimeInterval = 0

  /// Creates an iterator that continues `prompt`, of which the model reads `input` and `cache` holds the rest.
  init(
    input: LMInput,
    prompt: [Int],
    model: any LanguageModel,
    cache: [KVCache],
    sampler: LogitSampler,
    maxTokens: Int?
  ) throws {
    guard canTrimPromptCache(cache) else { throw UntrimmableCache() }
    self.model = model
    self.cache = cache
    self.sampler = sampler
    self.maxTokens = maxTokens
    history = prompt
    let start = Date.timeIntervalSinceReferenceDate
    switch try model.prepare(input, cache: cache, windowSize: nil) {
    case .tokens(let rest):
      unread = rest.tokens.asArray(Int.self)
    case .logits(let result):
      state = result.state
      let token = sampler.sample(logits: result.logits[0..., -1, 0...]).item(Int.self)
      unread = [token]
      written = [token]
      history.append(token)
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
    let room = maxTokens.map { $0 - tokenCount - 1 } ?? Self.mostGuesses
    let guesses = Array(guess().prefix(Swift.max(0, Swift.min(room, Self.mostGuesses))))
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
    history += tokens
    unread = [predicted[agreed]]
  }

  /// The tokens that followed the latest tokens where they last appeared before, trying the longest match first.
  private func guess() -> ArraySlice<Int> {
    for length in stride(from: Swift.min(Self.longestMatch, history.count - 1), through: 1, by: -1) {
      let latest = history.suffix(length)
      for start in stride(from: history.count - length - 1, through: 0, by: -1)
      where history[start..<(start + length)].elementsEqual(latest) {
        let next = start + length
        return history[next..<Swift.min(next + Self.mostGuesses, history.count)]
      }
    }
    return []
  }

  /// Thrown for a cache that can't drop rejected guesses.
  struct UntrimmableCache: Error {}
}

import Foundation
import MLX
import MLXLMCommon

/// Cleans up transcripts with a language model, following `RefinePrompt`.
///
/// Every prompt starts with the same system prompt, so the model reads it once as it loads, and each transcript
/// continues from a copy of that state instead of reading the system prompt again.
actor TranscriptRefiner {
  enum RefineError: Error {
    case unloaded
    /// The model reached its token limit, so its output would be cut off.
    case incomplete
  }

  private struct Loaded {
    let context: ModelContext
    /// The start of the prompt, which every transcript's prompt shares.
    let promptTokens: [Int]
    /// The model's state after reading `promptTokens`, copied for each transcript.
    let promptCache: [KVCache]
  }

  /// The `UserDefaults` key for whether transcripts are refined, on unless turned off.
  static let enabledStorageKey = "refinesTranscripts"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  private var loaded: Loaded?

  /// Reads the system prompt with a loaded model.
  init(context: sending ModelContext) throws {
    let tokenizer = context.tokenizer
    // Prompts for two different transcripts share everything before the transcript.
    let first = try Self.promptTokens(for: "a", tokenizer: tokenizer)
    let second = try Self.promptTokens(for: "b", tokenizer: tokenizer)
    let shared = zip(first, second).prefix { $0 == $1 }.count
    // A transcript's first characters can merge with the text before them into different tokens, but never with a
    // special token, so the cached start ends at the last special token before the transcript.
    let end = first[..<shared].lastIndex { Self.isSpecial($0, tokenizer: tokenizer) }.map { $0 + 1 } ?? 0
    let tokens = Array(first[..<end])
    let cache = context.model.newCache(parameters: nil)
    if !tokens.isEmpty {
      _ = context.model(LMInput.Text(tokens: MLXArray(tokens).expandedDimensions(axis: 0)), cache: cache, state: nil)
      eval(cache)
    }
    loaded = Loaded(context: context, promptTokens: tokens, promptCache: cache)
  }

  /// Returns the cleaned-up transcript, which is empty if the transcript was only filler words.
  func refine(_ transcript: String) async throws -> String {
    guard let loaded else { throw RefineError.unloaded }
    let context = loaded.context
    let tokens = try Self.promptTokens(for: transcript, tokenizer: context.tokenizer)
    // A chat template could render the start differently for some transcripts, and then the whole prompt is read.
    let continuesPrompt = tokens.starts(with: loaded.promptTokens)
    let unread = continuesPrompt ? tokens[loaded.promptTokens.count...] : tokens[...]
    // A cleaned-up transcript is rarely longer than the transcript, so a model still writing past twice its length has
    // started answering it or repeating itself.
    let transcriptLength = context.tokenizer.encode(text: transcript, addSpecialTokens: false).count
    let maxTokens = max(64, 2 * transcriptLength)
    let input = LMInput(tokens: MLXArray(Array(unread)))
    let cache = continuesPrompt ? loaded.promptCache.map { $0.copy() } : context.model.newCache(parameters: nil)
    let stream: AsyncStream<Generation>
    // Guessing ahead needs a cache that can drop wrong guesses, which caches of models that mix in other layers than
    // attention, like Qwen3.5's, can't, so those models write one token per pass.
    if canTrimPromptCache(cache) {
      let iterator = try PromptLookupTokenIterator(
        input: input,
        prompt: tokens,
        model: context.model,
        cache: cache,
        sampler: ArgMaxSampler(),
        maxTokens: maxTokens
      )
      (stream, _) = generateTask(
        promptTokenCount: unread.count,
        modelConfiguration: context.configuration,
        tokenizer: context.tokenizer,
        iterator: iterator
      )
    } else {
      stream = try generate(
        input: input,
        cache: cache,
        parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
        context: context
      )
    }
    let initial = (output: "", stopReason: GenerateStopReason?.none)
    let (output, stopReason) = await stream.reduce(into: initial) { result, generation in
      switch generation {
      case .chunk(let text): result.output += text
      case .info(let info): result.stopReason = info.stopReason
      case .toolCall: break
      }
    }
    guard stopReason == .stop else { throw RefineError.incomplete }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Frees the memory the model uses, after which the refiner can't be used.
  func unload() {
    loaded = nil
    // Arrays an MLX model held besides its weights return to MLX's cache when it's released, rather than to macOS.
    MLX.Memory.clearCache()
  }

  private static func promptTokens(for transcript: String, tokenizer: any MLXLMCommon.Tokenizer) throws -> [Int] {
    try tokenizer.applyChatTemplate(
      messages: [
        ["role": "system", "content": RefinePrompt.system],
        ["role": "user", "content": RefinePrompt.message(for: transcript)],
      ],
      tools: nil,
      // Models that can reason before answering, such as Qwen3.5, would otherwise do so by default, which makes
      // refining much slower. Templates without a thinking mode ignore it.
      additionalContext: ["enable_thinking": false]
    )
  }

  /// Whether a token is a special token, such as one that starts or ends a message, which decoding can leave out.
  private static func isSpecial(_ token: Int, tokenizer: any MLXLMCommon.Tokenizer) -> Bool {
    tokenizer.decode(tokenIds: [token], skipSpecialTokens: true).isEmpty
      && !tokenizer.decode(tokenIds: [token], skipSpecialTokens: false).isEmpty
  }
}

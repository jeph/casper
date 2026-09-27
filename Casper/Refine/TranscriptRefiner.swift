import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Cleans up transcripts with the language model bundled into Casper, following `RefinePrompt`.
///
/// Every prompt starts with the same system prompt, so the model reads it once as it loads, and each transcript
/// continues from a copy of that state instead of reading the system prompt again.
actor TranscriptRefiner {
  enum RefineError: Error {
    case missingModel
    case unloaded
    /// The model reached its token limit, so its output would be cut off.
    case incomplete
  }

  private struct Loaded {
    let context: ModelContext
    /// The prompt for an empty transcript, which every prompt shares up to where the transcript goes.
    let promptTokens: [Int]
    /// The model's state after reading `promptTokens`.
    let promptCache: [KVCache]
  }

  /// The `UserDefaults` key for whether transcripts are refined, on unless turned off.
  static let enabledStorageKey = "refinesTranscripts"
  private static let modelName = "Qwen3-4B-Instruct-2507-4bit"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  private var loaded: Loaded?

  private init(context: sending ModelContext) throws {
    let tokens = try Self.promptTokens(for: "", tokenizer: context.tokenizer)
    let cache = context.model.newCache(parameters: nil)
    _ = context.model(LMInput.Text(tokens: MLXArray(tokens).expandedDimensions(axis: 0)), cache: cache, state: nil)
    eval(cache)
    loaded = Loaded(context: context, promptTokens: tokens, promptCache: cache)
  }

  /// Loads the bundled model and reads the system prompt.
  static func load() async throws -> TranscriptRefiner {
    guard let url = Bundle.main.url(forResource: modelName, withExtension: nil) else { throw RefineError.missingModel }
    let context = try await LLMModelFactory.shared.load(from: url, using: TransformersTokenizerLoader())
    return try TranscriptRefiner(context: context)
  }

  /// Returns the cleaned-up transcript, which is empty if the transcript was only filler words.
  func refine(_ transcript: String) async throws -> String {
    guard let loaded else { throw RefineError.unloaded }
    let context = loaded.context
    let tokens = try Self.promptTokens(for: transcript, tokenizer: context.tokenizer)
    // The tokens where the transcript starts can differ from the empty transcript's, so only the matching start of the
    // cached prompt is kept. At least one token is left for the model to read, since reading produces the next token.
    let matching = min(zip(loaded.promptTokens, tokens).prefix { $0 == $1 }.count, tokens.count - 1)
    let cache = loaded.promptCache.map { $0.copy() }
    let unread: ArraySlice<Int>
    if matching == loaded.promptTokens.count || canTrimPromptCache(cache) {
      trimPromptCache(cache, numTokens: loaded.promptTokens.count - matching)
      unread = tokens[matching...]
    } else {
      unread = tokens[...]
    }
    let reusesCache = unread.count < tokens.count
    // A cleaned-up transcript is rarely longer than the transcript, so a model still writing past twice its length has
    // started answering it or repeating itself.
    let transcriptLength = context.tokenizer.encode(text: transcript, addSpecialTokens: false).count
    let parameters = GenerateParameters(maxTokens: max(64, 2 * transcriptLength), temperature: 0)
    let stream = try generate(
      input: LMInput(tokens: MLXArray(Array(unread))),
      cache: reusesCache ? cache : nil,
      parameters: parameters,
      context: context
    )
    var output = ""
    var stopReason: GenerateStopReason?
    for await generation in stream {
      switch generation {
      case .chunk(let text): output += text
      case .info(let info): stopReason = info.stopReason
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
}

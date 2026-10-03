import AudioCommon
import MLX
import Qwen3ASR

/// Transcribes with a Qwen3-ASR model through speech-swift.
actor Qwen3Transcriber: Transcriber {
  enum TranscriptionError: Error {
    case unloaded
  }

  private var model: Qwen3ASRModel?

  init(model: sending Qwen3ASRModel) {
    self.model = model
  }

  /// Puts the dictionary's words in the system prompt, one per line, which Qwen3-ASR was trained to read as background
  /// knowledge.
  ///
  /// Sounds Like spellings stay out: with them in the prompt, the model writes them.
  ///
  /// speech-swift builds the prompt afresh for every call, with no cache carried over, so a changed dictionary applies
  /// to the next dictation without reloading the model.
  ///
  /// Cancelling the task stops the transcription between tokens, so a dictation doesn't wait for a replay of an
  /// earlier one.
  func transcribe(_ samples: [Float], sampleRate: Double, dictionary: [DictionaryWord]) async throws -> String {
    guard let model else { throw TranscriptionError.unloaded }
    defer { BufferCache.releaseIfEnabled() }
    let seconds = Double(samples.count) / sampleRate
    // A nil language lets the model detect it.
    let text = try model.transcribeCheckingCancellation(
      audio: samples,
      sampleRate: Int(sampleRate),
      options: Qwen3DecodingOptions(
        maxTokens: Self.maximumTokens(forSeconds: seconds),
        context: dictionary.isEmpty ? nil : dictionary.map(\.text).joined(separator: "\n")
      )
    )
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func unload() async {
    model?.unload()
    model = nil
    // Arrays an MLX model held besides its weights return to MLX's cache when it's released, rather than to macOS.
    MLX.Memory.clearCache()
  }
}

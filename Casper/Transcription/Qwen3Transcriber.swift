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

  func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
    guard let model else { throw TranscriptionError.unloaded }
    let seconds = Double(samples.count) / sampleRate
    // A nil language lets the model detect it.
    let text = model.transcribe(
      audio: samples,
      sampleRate: Int(sampleRate),
      language: nil,
      maxTokens: Self.maximumTokens(forSeconds: seconds)
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

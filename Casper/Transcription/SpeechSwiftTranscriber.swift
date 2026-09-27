import AudioCommon
import MLX

/// Transcribes with a speech-swift model.
actor SpeechSwiftTranscriber: Transcriber {
  enum TranscriptionError: Error {
    case unloaded
  }

  private var model: (any SpeechRecognitionModel & ModelMemoryManageable)?

  init(model: sending any SpeechRecognitionModel & ModelMemoryManageable) {
    self.model = model
  }

  func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
    guard let model else { throw TranscriptionError.unloaded }
    // A nil language lets the model detect it.
    return model.transcribe(audio: samples, sampleRate: Int(sampleRate), language: nil)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func unload() async {
    model?.unload()
    model = nil
    // Arrays an MLX model held besides its weights return to MLX's cache when it's released, rather than to macOS.
    MLX.Memory.clearCache()
  }
}

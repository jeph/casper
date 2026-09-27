import AudioCommon
import MLX

/// Runs any speech-to-text model from the speech-swift library, which all conform to its `SpeechRecognitionModel`.
///
/// The model runs on this actor, off the main thread, and handles one transcription at a time.
actor SpeechSwiftTranscriber: Transcriber {
  enum TranscriptionError: Error {
    case unloaded
  }

  /// The model, or `nil` once it's unloaded.
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

  /// Releases the model's weights, then the model itself, then the GPU buffers MLX cached for reuse.
  func unload() async {
    model?.unload()
    model = nil
    // Arrays the model held besides its weights return to MLX's cache when it's released, rather than to macOS.
    MLX.Memory.clearCache()
  }
}

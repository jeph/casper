import Foundation
import Qwen3ASR

/// The speech-to-text models Casper can run.
///
/// Only one model is bundled with the app for now. Downloadable models will add cases and a place to load them from.
enum SpeechModel {
  case qwen3ASR17B

  enum LoadError: Error {
    case missingFromBundle(String)
  }

  /// The sample rate, in hertz, the model was trained on, which Casper records at.
  var sampleRate: Double {
    switch self {
    case .qwen3ASR17B: 16_000
    }
  }

  /// The folder in the app's resources that holds the model, as downloaded by `scripts/download-model.sh`.
  private var bundleDirectoryName: String {
    switch self {
    case .qwen3ASR17B: "Qwen3-ASR-1.7B-MLX-8bit"
    }
  }

  /// Loads the model's weights, which takes a few seconds, and returns a transcriber that runs it.
  func loadTranscriber() async throws -> any Transcriber {
    guard let directory = Bundle.main.url(forResource: bundleDirectoryName, withExtension: nil) else {
      throw LoadError.missingFromBundle(bundleDirectoryName)
    }
    switch self {
    case .qwen3ASR17B:
      // speech-swift reads the model size and bit width from the Hugging Face ID. Offline mode only reads the folder.
      let model = try await Qwen3ASRModel.fromPretrained(
        modelId: "aufklarer/\(bundleDirectoryName)",
        cacheDir: directory,
        offlineMode: true
      )
      return SpeechSwiftTranscriber(model: model)
    }
  }
}

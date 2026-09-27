import AudioCommon
import Foundation
import ParakeetASR
import Qwen3ASR

/// A speech recognition model Casper can download and run, in one size and precision.
struct SpeechModel: LoadableModel {
  /// The processor a model runs on.
  enum Accelerator: CaseIterable, Identifiable, Sendable {
    case neuralEngine
    case gpu

    var id: Self { self }

    var title: LocalizedStringResource {
      switch self {
      case .neuralEngine:
        LocalizedStringResource(
          "Neural Engine",
          comment: "Heading on the Voice Models page for the models that run on the Neural Engine."
        )
      case .gpu:
        LocalizedStringResource(
          "MLX",
          comment: """
            Heading on the Voice Models page for the models that run on the GPU with MLX, Apple's machine learning \
            framework. A name, usually left untranslated.
            """
        )
      }
    }

    var models: [SpeechModel] { SpeechModel.all.filter { $0.family.accelerator == self } }
  }

  /// A model architecture, which speech-swift runs with code of its own.
  enum Family: Sendable {
    case parakeetTDT
    case qwen3ASR

    /// The model's name, which isn't translated.
    var name: String {
      switch self {
      case .parakeetTDT: "Parakeet TDT v3"
      case .qwen3ASR: "Qwen3-ASR"
      }
    }

    var accelerator: Accelerator {
      switch self {
      case .parakeetTDT: .neuralEngine
      case .qwen3ASR: .gpu
      }
    }

    /// The languages the model transcribes.
    var languages: LocalizedStringResource {
      switch self {
      case .parakeetTDT:
        LocalizedStringResource(
          "25 European languages",
          comment: "The languages the Parakeet speech model transcribes, shown on the Voice Models page."
        )
      case .qwen3ASR:
        LocalizedStringResource(
          "30 languages and 22 Chinese dialects",
          comment: "The languages the Qwen3-ASR speech models transcribe, shown on the Voice Models page."
        )
      }
    }
  }

  let id: String
  let family: Family
  let parameters: String
  let bits: Int
  let downloadSize: Int64
  let revision: String
  var isRecommended = false

  /// The sample rate every model takes audio at.
  ///
  /// Each one resamples audio at any other rate.
  static let sampleRate = 16_000.0
  static let activeStorageKey = "activeSpeechModel"
  @MainActor static let store = ModelStore<SpeechModel>()

  var name: String { family.name }

  var languages: LocalizedStringResource { family.languages }

  /// The Hugging Face repository, from the account that publishes speech-swift's converted models.
  var repository: String { "aufklarer/\(id)" }

  func load() async throws -> any Transcriber {
    let model: any SpeechRecognitionModel & ModelMemoryManageable
    switch family {
    case .parakeetTDT:
      model = try await ParakeetASRModel.fromPretrained(modelId: repository, cacheDir: directory, offlineMode: true)
    case .qwen3ASR:
      // speech-swift reads the model size and bit width from the Hugging Face ID. Offline mode only reads the folder.
      model = try await Qwen3ASRModel.fromPretrained(modelId: repository, cacheDir: directory, offlineMode: true)
    }
    return SpeechSwiftTranscriber(model: model)
  }

  static func unload(_ transcriber: any Transcriber) async {
    await transcriber.unload()
  }
}

extension SpeechModel {
  static let all = [
    SpeechModel(
      id: "Parakeet-TDT-v3-CoreML-INT8-30s",
      family: .parakeetTDT,
      parameters: "0.6B",
      bits: 8,
      downloadSize: 640_656_886,
      revision: "8054d9f680cfa4c0012876ed71e854fb20dd563b",
      isRecommended: true
    ),
    SpeechModel(
      id: "Qwen3-ASR-0.6B-MLX-5bit",
      family: .qwen3ASR,
      parameters: "0.6B",
      bits: 5,
      downloadSize: 1_098_362_508,
      revision: "6583c8be06b5ae19aff9d7ca3c65139306162eda",
      isRecommended: true
    ),
    SpeechModel(
      id: "Qwen3-ASR-0.6B-MLX-8bit",
      family: .qwen3ASR,
      parameters: "0.6B",
      bits: 8,
      downloadSize: 1_010_771_234,
      revision: "0bfa1071b35e137d32e5beba0ee42e2ca917b878"
    ),
    SpeechModel(
      id: "Qwen3-ASR-1.7B-MLX-5bit",
      family: .qwen3ASR,
      parameters: "1.7B",
      bits: 5,
      downloadSize: 2_444_929_813,
      revision: "1645ca9ce8767dac9a4a047e9de835950c42596e"
    ),
    SpeechModel(
      id: "Qwen3-ASR-1.7B-MLX-8bit",
      family: .qwen3ASR,
      parameters: "1.7B",
      bits: 8,
      downloadSize: 2_467_854_870,
      revision: "e5450a26d1fd417c45fc9c405651ddc3180a27a6"
    ),
  ]
}

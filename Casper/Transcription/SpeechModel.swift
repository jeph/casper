import AudioCommon
import Foundation
import ParakeetASR
import Qwen3ASR

/// A speech recognition model Casper can download and run, in one size and precision.
struct SpeechModel: Identifiable, Sendable {
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

  /// The model's Hugging Face repository name, which is also the name of the folder it's installed in.
  let id: String
  let family: Family
  /// The number of parameters, such as "0.6B".
  let parameters: String
  let bits: Int
  /// The total size of the model's files.
  let downloadSize: Int64
  /// The Hugging Face commit to download, fixed so the files can't change.
  let revision: String
  /// Whether the Voice Models page recommends the model, for its balance of speed and accuracy.
  var isRecommended = false

  /// The sample rate every model takes audio at.
  ///
  /// Each one resamples audio at any other rate.
  static let sampleRate = 16_000.0
  /// The `UserDefaults` key for the ID of the model dictation uses.
  static let activeStorageKey = "activeSpeechModel"
  static let installDirectory = URL.applicationSupportDirectory.appending(
    path: "Casper/Models",
    directoryHint: .isDirectory
  )

  /// The model dictation uses, or `nil` if none is chosen.
  static var active: SpeechModel? {
    UserDefaults.standard.string(forKey: activeStorageKey).flatMap { id in all.first { $0.id == id } }
  }

  /// The model's name, size and precision, such as "Qwen3-ASR 0.6B, 5-bit".
  var title: LocalizedStringResource {
    LocalizedStringResource(
      "\(family.name) \(parameters), \(bits)-bit",
      comment: """
        A speech model's name, its size in parameters, such as 0.6B, and the precision of its weights in bits. For \
        example, "Qwen3-ASR 0.6B, 5-bit".
        """
    )
  }

  /// The Hugging Face repository, from the account that publishes speech-swift's converted models.
  var repository: String { "aufklarer/\(id)" }

  var directory: URL { Self.installDirectory.appending(path: id, directoryHint: .isDirectory) }

  var isInstalled: Bool { FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) }

  func loadTranscriber() async throws -> any Transcriber {
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

import AudioCommon
import FluidAudio
import Foundation
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

  /// A model architecture, which FluidAudio or speech-swift runs with code of its own.
  enum Family: Sendable {
    case parakeetTDT
    case parakeetUltra
    case qwen3ASR

    /// The model's name, which isn't translated.
    var name: String {
      switch self {
      case .parakeetTDT: "Parakeet TDT v3"
      case .parakeetUltra: "Parakeet Ultra"
      case .qwen3ASR: "Qwen3-ASR"
      }
    }

    var accelerator: Accelerator {
      switch self {
      case .parakeetTDT, .parakeetUltra: .neuralEngine
      case .qwen3ASR: .gpu
      }
    }

    /// The languages the model transcribes.
    var languages: LocalizedStringResource {
      switch self {
      case .parakeetTDT, .parakeetUltra:
        LocalizedStringResource(
          "25 European languages",
          comment: "The languages the Parakeet speech models transcribe, shown on the Voice Models page."
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

  /// The sample rate every model takes audio at, which Casper records at.
  ///
  /// FluidAudio's Parakeet only takes audio at this rate.
  static let sampleRate = 16_000.0
  static let activeStorageKey = "activeSpeechModel"
  @MainActor static let store = ModelStore<SpeechModel>()

  var name: String { family.name }

  var languages: LocalizedStringResource { family.languages }

  /// The Hugging Face repository, from the account that publishes the converted models its library runs.
  var repository: String {
    switch family {
    case .parakeetTDT, .parakeetUltra: "FluidInference/\(id)"
    case .qwen3ASR: "aufklarer/\(id)"
    }
  }

  /// The files FluidAudio loads, from Parakeet repositories that also have files it doesn't, such as other encoders.
  var files: [String]? {
    let encoder: String
    switch family {
    case .parakeetTDT: encoder = Self.parakeetEncoderPrecision.encoderFileName
    // Parakeet Ultra has only an 8-bit encoder.
    case .parakeetUltra: encoder = ModelNames.ASR.encoderFile
    case .qwen3ASR: return nil
    }
    return [
      ModelNames.ASR.preprocessorFile, encoder, ModelNames.ASR.decoderFile, ModelNames.ASR.jointV3File,
      ModelNames.ASR.vocabularyFile,
    ]
  }

  func load() async throws -> any Transcriber {
    switch family {
    case .parakeetTDT:
      return try await ParakeetTranscriber(
        models: AsrModels.loadLocal(from: directory, version: .v3, encoderPrecision: Self.parakeetEncoderPrecision)
      )
    case .parakeetUltra:
      return try await ParakeetTranscriber(models: AsrModels.loadLocal(from: directory, version: .ultra))
    case .qwen3ASR:
      // speech-swift reads the model size and bit width from the Hugging Face ID. Offline mode only reads the folder.
      return SpeechSwiftTranscriber(
        model: try await Qwen3ASRModel.fromPretrained(modelId: repository, cacheDir: directory, offlineMode: true)
      )
    }
  }

  static func unload(_ transcriber: any Transcriber) async {
    await transcriber.unload()
  }

  /// The 8-bit encoder, rather than FluidAudio's default 6-bit one, which garbles some words (FluidAudio issue #760).
  private static let parakeetEncoderPrecision = ParakeetEncoderPrecision.int8V2
}

extension SpeechModel {
  static let all = [
    SpeechModel(
      id: "parakeet-ultra-coreml",
      family: .parakeetUltra,
      parameters: "0.6B",
      // The encoder's weights, which are almost all of the model's.
      bits: 8,
      downloadSize: 632_162_964,
      revision: "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
      isRecommended: true
    ),
    SpeechModel(
      id: "parakeet-tdt-0.6b-v3-coreml",
      family: .parakeetTDT,
      parameters: "0.6B",
      // The encoder's weights, which are almost all of the model's.
      bits: 8,
      downloadSize: 632_169_729,
      revision: "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"
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

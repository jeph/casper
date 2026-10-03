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
  }

  let id: String
  let family: Family
  // Optional to match `DownloadableModel`: a non-optional property wouldn't satisfy it, and its `nil` default would be
  // shown instead.
  let summary: LocalizedStringResource?
  let parameters: String
  let bits: Int
  let downloadSize: Int64
  let memoryUsage: Int64
  let revision: String
  let isRecommended: Bool

  /// The sample rate every model takes audio at, which Casper records at.
  ///
  /// FluidAudio's Parakeet only takes audio at this rate.
  static let sampleRate = 16_000.0
  static let activeStorageKey = "activeSpeechModel"
  @MainActor static let store = ModelStore<SpeechModel>()

  var name: String { family.name }

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

  /// FluidAudio's word spotter for Parakeet, whose decoder can't be steered toward dictionary words.
  ///
  /// Qwen3-ASR reads the words in its prompt and needs nothing more.
  var companions: [ModelRepository] {
    switch family {
    case .parakeetTDT, .parakeetUltra: [WordSpotter.files]
    case .qwen3ASR: []
    }
  }

  func load() async throws -> any Transcriber {
    switch family {
    case .parakeetTDT:
      return try await ParakeetTranscriber(
        models: AsrModels.loadLocal(from: directory, version: .v3, encoderPrecision: Self.parakeetEncoderPrecision),
        wordSpotterDirectory: WordSpotter.files.directory
      )
    case .parakeetUltra:
      return try await ParakeetTranscriber(
        models: AsrModels.loadLocal(from: directory, version: .ultra),
        wordSpotterDirectory: WordSpotter.files.directory
      )
    case .qwen3ASR:
      // speech-swift reads the model size and bit width from the Hugging Face ID. Offline mode only reads the folder.
      return Qwen3Transcriber(
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
  // `memoryUsage` is what `footprint` reported for a model and its companions, Neural Engine memory included, after
  // it transcribed 26 seconds of speech twice. Most of Qwen3-ASR's is buffers from transcribing, which MLX keeps in
  // its cache.
  static let all = [
    SpeechModel(
      id: "parakeet-ultra-coreml",
      family: .parakeetUltra,
      summary: LocalizedStringResource(
        "Tuned Parakeet with better accuracy at the same speed.",
        comment: "Description of Parakeet Ultra, a version of the Parakeet speech model, on the Voice Models page."
      ),
      parameters: "0.6B",
      // The encoder's weights, which are almost all of the model's.
      bits: 8,
      downloadSize: 632_162_964,
      memoryUsage: 807_403_520,
      revision: "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
      isRecommended: true
    ),
    SpeechModel(
      id: "parakeet-tdt-0.6b-v3-coreml",
      family: .parakeetTDT,
      summary: LocalizedStringResource(
        "The original Parakeet. Ultra is usually more accurate at the same speed.",
        comment: """
          Description of Parakeet TDT v3, the speech model Parakeet Ultra was tuned from, on the Voice Models page.
          """
      ),
      parameters: "0.6B",
      // The encoder's weights, which are almost all of the model's.
      bits: 8,
      downloadSize: 632_169_729,
      memoryUsage: 786_432_000,
      revision: "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe",
      isRecommended: false
    ),
    SpeechModel(
      id: "Qwen3-ASR-0.6B-MLX-5bit",
      family: .qwen3ASR,
      summary: LocalizedStringResource(
        "More languages than Parakeet, but slower. Faster than 8-bit, similar accuracy.",
        comment: """
          Description of the 0.6B, 5-bit Qwen3-ASR speech model on the Voice Models page, compared with Parakeet, \
          another speech model, and with the 8-bit version.
          """
      ),
      parameters: "0.6B",
      bits: 5,
      downloadSize: 1_098_362_508,
      memoryUsage: 3_500_000_000,
      revision: "6583c8be06b5ae19aff9d7ca3c65139306162eda",
      isRecommended: true
    ),
    SpeechModel(
      id: "Qwen3-ASR-0.6B-MLX-8bit",
      family: .qwen3ASR,
      summary: LocalizedStringResource(
        "More languages than Parakeet, but slower. Marginally more accurate than 5-bit, but slower.",
        comment: """
          Description of the 0.6B, 8-bit Qwen3-ASR speech model on the Voice Models page, compared with Parakeet, \
          another speech model, and with the 5-bit version.
          """
      ),
      parameters: "0.6B",
      bits: 8,
      downloadSize: 1_010_771_234,
      memoryUsage: 3_700_000_000,
      revision: "0bfa1071b35e137d32e5beba0ee42e2ca917b878",
      isRecommended: false
    ),
    SpeechModel(
      id: "Qwen3-ASR-1.7B-MLX-5bit",
      family: .qwen3ASR,
      summary: LocalizedStringResource(
        "More accurate than 0.6B, but slower. Faster than 8-bit, similar accuracy.",
        comment: """
          Description of the 1.7B, 5-bit Qwen3-ASR speech model on the Voice Models page, compared with the 0.6B \
          models and with the 8-bit version.
          """
      ),
      parameters: "1.7B",
      bits: 5,
      downloadSize: 2_444_929_813,
      memoryUsage: 5_100_000_000,
      revision: "1645ca9ce8767dac9a4a047e9de835950c42596e",
      isRecommended: false
    ),
    SpeechModel(
      id: "Qwen3-ASR-1.7B-MLX-8bit",
      family: .qwen3ASR,
      summary: LocalizedStringResource(
        "More accurate than 0.6B, but slower. Marginally more accurate than 5-bit, but slower.",
        comment: """
          Description of the 1.7B, 8-bit Qwen3-ASR speech model on the Voice Models page, compared with the 0.6B \
          models and with the 5-bit version.
          """
      ),
      parameters: "1.7B",
      bits: 8,
      downloadSize: 2_467_854_870,
      memoryUsage: 5_550_000_000,
      revision: "e5450a26d1fd417c45fc9c405651ddc3180a27a6",
      isRecommended: false
    ),
  ]
}

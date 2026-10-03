import Foundation
import MLXLLM

/// A language model Casper can download and refine transcripts with, in one size and precision.
struct LanguageModel: LoadableModel {
  /// A generation of models, grouped under its name on the Language Models page.
  enum Family: CaseIterable, Identifiable, Sendable {
    case qwen3
    case qwen35
    case qwen38

    var id: Self { self }

    /// The family's name, which isn't translated.
    var name: String {
      switch self {
      case .qwen3: "Qwen3"
      case .qwen35: "Qwen3.5"
      case .qwen38: "Qwen3.8"
      }
    }

    var models: [LanguageModel] { LanguageModel.all.filter { $0.family == self } }
  }

  let id: String
  let family: Family
  let parameters: String
  let bits = 4
  let downloadSize: Int64
  let revision: String
  let isRecommended: Bool

  static let activeStorageKey = "activeLanguageModel"
  @MainActor static let store = ModelStore<LanguageModel>()

  var name: String { family.name }

  /// The Hugging Face repository, from the MLX community's conversions of the models.
  var repository: String { "mlx-community/\(id)" }

  func load() async throws -> TranscriptRefiner {
    let context = try await LLMModelFactory.shared.load(from: directory, using: TransformersTokenizerLoader())
    return TranscriptRefiner(context: context)
  }

  static func unload(_ refiner: TranscriptRefiner) async {
    await refiner.unload()
  }
}

extension LanguageModel {
  static let all = [
    LanguageModel(
      id: "Qwen3-0.6B-4bit",
      family: .qwen3,
      parameters: "0.6B",
      downloadSize: 351_383_618,
      revision: "73e3e38d981303bc594367cd910ea6eb48349da8",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3-1.7B-4bit",
      family: .qwen3,
      parameters: "1.7B",
      downloadSize: 984_013_244,
      revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3-4B-Instruct-2507-4bit",
      family: .qwen3,
      parameters: "4B 2507",
      downloadSize: 2_278_969_697,
      revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
      isRecommended: true
    ),
    LanguageModel(
      id: "Qwen3-8B-4bit",
      family: .qwen3,
      parameters: "8B",
      downloadSize: 4_623_782_544,
      revision: "545dc4251c05440727734bcd94334791f6ab0192",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3-14B-4bit",
      family: .qwen3,
      parameters: "14B",
      downloadSize: 8_323_868_085,
      revision: "a4d9b2df59d2c150bef02fcbe0d91046b7ca33a4",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3.5-0.8B-4bit",
      family: .qwen35,
      parameters: "0.8B",
      downloadSize: 652_027_143,
      revision: "da28692b5f139cb0ec58a356b437486b7dac7462",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3.5-2B-4bit",
      family: .qwen35,
      parameters: "2B",
      downloadSize: 1_749_079_691,
      revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3.5-4B-4bit",
      family: .qwen35,
      parameters: "4B",
      downloadSize: 3_061_129_077,
      revision: "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3.5-9B-4bit",
      family: .qwen35,
      parameters: "9B",
      downloadSize: 5_977_071_067,
      revision: "8b2b98c00a6b4d291155e4890773ca8f769aee53",
      isRecommended: false
    ),
    LanguageModel(
      id: "Qwen3.8-27B-4bit",
      family: .qwen38,
      parameters: "27B",
      downloadSize: 16_081_488_731,
      revision: "10c35caafbb80f7dc6a7a432cdd11af10a6d4818",
      isRecommended: false
    ),
  ]
}

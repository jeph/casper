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
  let summary: LocalizedStringResource
  let parameters: String
  let bits = 4
  let downloadSize: Int64
  let memoryUsage: Int64
  let revision: String

  static let activeStorageKey = "activeLanguageModel"
  @MainActor static let store = ModelStore<LanguageModel>()

  /// The model the Language Models page recommends for this Mac.
  ///
  /// Qwen3 4B 2507 follows instructions as well as the larger Qwen3 models while refining faster. Qwen3 1.7B takes
  /// about 1.3 GB less memory.
  private static let recommendedID = isMemoryLimited ? "Qwen3-1.7B-4bit" : "Qwen3-4B-Instruct-2507-4bit"

  var name: String { family.name }

  var isRecommended: Bool { id == Self.recommendedID }

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
  // `memoryUsage` is what a model's process footprint grew by once it read the Formal persona's prompt and refined a
  // 26-second dictation twice. About 1 GB of it, and up to 3 GB for the largest model, is buffers from refining,
  // which MLX keeps in its cache.
  //
  // `summary` compares instruction following by the IFEval and IFBench scores on Qwen's model cards and in the Qwen3
  // technical report, in non-thinking mode where Qwen publishes it. Qwen3.5 4B and 9B only have thinking-mode scores.
  // Speeds are how long each model took to refine the same 26-second dictation in Casper.
  static let all = [
    LanguageModel(
      id: "Qwen3-0.6B-4bit",
      family: .qwen3,
      summary: LocalizedStringResource(
        "Least memory, but often ignores instructions.",
        comment: "Description of the Qwen3 0.6B language model on the Language Models page."
      ),
      parameters: "0.6B",
      downloadSize: 351_383_618,
      memoryUsage: 1_562_378_240,
      revision: "73e3e38d981303bc594367cd910ea6eb48349da8"
    ),
    LanguageModel(
      id: "Qwen3-1.7B-4bit",
      family: .qwen3,
      summary: LocalizedStringResource(
        "Faster than 4B 2507, but follows instructions less reliably.",
        comment: """
          Description of the Qwen3 1.7B language model on the Language Models page. 4B 2507 is the Qwen3 4B 2507 \
          model.
          """
      ),
      parameters: "1.7B",
      downloadSize: 984_013_244,
      memoryUsage: 2_243_952_640,
      revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e"
    ),
    LanguageModel(
      id: "Qwen3-4B-Instruct-2507-4bit",
      family: .qwen3,
      summary: LocalizedStringResource(
        "Updated Qwen3 4B. Follows instructions as well as 8B, but faster.",
        comment: """
          Description of the Qwen3 4B 2507 language model, a July 2025 update of Qwen3 4B, on the Language Models \
          page. 8B is the Qwen3 8B model.
          """
      ),
      parameters: "4B 2507",
      downloadSize: 2_278_969_697,
      memoryUsage: 3_670_016_000,
      revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
    ),
    LanguageModel(
      id: "Qwen3-8B-4bit",
      family: .qwen3,
      summary: LocalizedStringResource(
        "Slower than 4B 2507, with similar instruction following.",
        comment: """
          Description of the Qwen3 8B language model on the Language Models page. 4B 2507 is the Qwen3 4B 2507 model.
          """
      ),
      parameters: "8B",
      downloadSize: 4_623_782_544,
      memoryUsage: 5_872_025_600,
      revision: "545dc4251c05440727734bcd94334791f6ab0192"
    ),
    LanguageModel(
      id: "Qwen3-14B-4bit",
      family: .qwen3,
      summary: LocalizedStringResource(
        "Slightly better at instructions than 4B 2507, but much slower.",
        comment: """
          Description of the Qwen3 14B language model on the Language Models page. 4B 2507 is the Qwen3 4B 2507 model.
          """
      ),
      parameters: "14B",
      downloadSize: 8_323_868_085,
      memoryUsage: 9_678_356_480,
      revision: "a4d9b2df59d2c150bef02fcbe0d91046b7ca33a4"
    ),
    LanguageModel(
      id: "Qwen3.5-0.8B-4bit",
      family: .qwen35,
      summary: LocalizedStringResource(
        "Fastest, but often ignores instructions.",
        comment: "Description of the Qwen3.5 0.8B language model on the Language Models page."
      ),
      parameters: "0.8B",
      downloadSize: 652_027_143,
      memoryUsage: 2_034_237_440,
      revision: "da28692b5f139cb0ec58a356b437486b7dac7462"
    ),
    LanguageModel(
      id: "Qwen3.5-2B-4bit",
      family: .qwen35,
      summary: LocalizedStringResource(
        "More languages than Qwen3 1.7B, but follows instructions less reliably.",
        comment: "Description of the Qwen3.5 2B language model on the Language Models page."
      ),
      parameters: "2B",
      downloadSize: 1_749_079_691,
      memoryUsage: 2_684_354_560,
      revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
    ),
    LanguageModel(
      id: "Qwen3.5-4B-4bit",
      family: .qwen35,
      summary: LocalizedStringResource(
        "Better at instructions than Qwen3 4B 2507, but slightly slower.",
        comment: "Description of the Qwen3.5 4B language model on the Language Models page."
      ),
      parameters: "4B",
      downloadSize: 3_061_129_077,
      memoryUsage: 4_456_448_000,
      revision: "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"
    ),
    LanguageModel(
      id: "Qwen3.5-9B-4bit",
      family: .qwen35,
      summary: LocalizedStringResource(
        "Better at instructions than Qwen3.5 4B, but slower.",
        comment: "Description of the Qwen3.5 9B language model on the Language Models page."
      ),
      parameters: "9B",
      downloadSize: 5_977_071_067,
      memoryUsage: 7_035_944_960,
      revision: "8b2b98c00a6b4d291155e4890773ca8f769aee53"
    ),
    LanguageModel(
      id: "Qwen3.8-27B-4bit",
      family: .qwen38,
      summary: LocalizedStringResource(
        "Best at instructions, but very slow and needs a lot of memory.",
        comment: "Description of the Qwen3.8 27B language model on the Language Models page."
      ),
      parameters: "27B",
      downloadSize: 16_081_488_731,
      memoryUsage: 18_517_852_160,
      revision: "10c35caafbb80f7dc6a7a432cdd11af10a6d4818"
    ),
  ]
}

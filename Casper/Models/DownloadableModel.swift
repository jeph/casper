import Foundation

/// A model Casper downloads from Hugging Face and runs on this Mac, in one size and precision.
protocol DownloadableModel: Identifiable, Sendable where ID == String {
  /// The model's Hugging Face repository name, which is also the name of the folder it's installed in.
  var id: String { get }
  /// The name of the model's family, which isn't translated.
  var name: String { get }
  /// The number of parameters, such as "0.6B".
  var parameters: String { get }
  var bits: Int { get }
  /// The languages the model works in.
  var languages: LocalizedStringResource { get }
  /// The total size of the model's files.
  var downloadSize: Int64 { get }
  /// The Hugging Face repository, including the account that publishes it.
  var repository: String { get }
  /// The Hugging Face commit to download, fixed so the files can't change.
  var revision: String { get }
  /// Whether the model's page recommends it, for its balance of speed and quality.
  var isRecommended: Bool { get }

  /// Every model of this kind Casper offers.
  static var all: [Self] { get }
  /// The `UserDefaults` key for the ID of the model of this kind dictation uses.
  static var activeStorageKey: String { get }
  /// The models of this kind installed on this Mac, and the ones downloading.
  @MainActor static var store: ModelStore<Self> { get }
}

extension DownloadableModel {
  /// The model of this kind dictation uses, or `nil` if none is chosen.
  static var active: Self? {
    UserDefaults.standard.string(forKey: activeStorageKey).flatMap { id in all.first { $0.id == id } }
  }

  /// The model's name, size and precision, such as "Qwen3-ASR 0.6B, 5-bit".
  var title: LocalizedStringResource {
    LocalizedStringResource(
      "\(name) \(parameters), \(bits)-bit",
      comment: """
        A model's name, its size in parameters, such as 0.6B, and the precision of its weights in bits. For example, \
        "Qwen3-ASR 0.6B, 5-bit".
        """
    )
  }

  var directory: URL {
    URL.applicationSupportDirectory.appending(path: "Casper/Models/\(id)", directoryHint: .isDirectory)
  }

  var isInstalled: Bool { FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) }
}

import Foundation

/// Files Casper downloads from one Hugging Face repository at a fixed revision, into a folder of their own.
struct ModelRepository: Hashable, Sendable {
  /// The repository's name, which is also the name of the folder it's installed in.
  let id: String
  /// The Hugging Face repository, including the account that publishes it.
  let repository: String
  /// The Hugging Face commit to download, fixed so the files can't change.
  let revision: String
  /// The files and folders needed from the repository, or `nil` if all of them are.
  let files: [String]?
  /// The total size of the files.
  let downloadSize: Int64

  var directory: URL {
    URL.applicationSupportDirectory.appending(path: "Casper/Models/\(id)", directoryHint: .isDirectory)
  }

  /// Whether the files are installed, which they are only once all of them are.
  var isInstalled: Bool { FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) }
}

/// A model Casper downloads from Hugging Face and runs on this Mac, in one size and precision.
protocol DownloadableModel: Identifiable, Sendable where ID == String {
  /// The model's Hugging Face repository name, which is also the name of the folder it's installed in.
  var id: String { get }
  /// The name of the model's family, which isn't translated.
  var name: String { get }
  /// The number of parameters, such as "0.6B".
  var parameters: String { get }
  var bits: Int { get }
  /// A sentence telling the model apart from the others on its page, or `nil` if the page doesn't describe its models.
  var summary: LocalizedStringResource? { get }
  /// The total size of the model's own files, without its companions.
  var downloadSize: Int64 { get }
  /// The memory the model and its companions take once they've loaded and been used.
  var memoryUsage: Int64 { get }
  /// The Hugging Face repository, including the account that publishes it.
  var repository: String { get }
  /// The Hugging Face commit to download, fixed so the files can't change.
  var revision: String { get }
  /// The files and folders the model needs from its repository, or `nil` if it needs all of them.
  var files: [String]? { get }
  /// Other models this one needs, which download with it, and are deleted with the last model that needs them.
  ///
  /// To the user they're part of the model: its download covers them and its size includes them.
  var companions: [ModelRepository] { get }
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

  var summary: LocalizedStringResource? { nil }

  var files: [String]? { nil }

  var companions: [ModelRepository] { [] }

  /// The model's own files, as a repository to download.
  var ownFiles: ModelRepository {
    ModelRepository(id: id, repository: repository, revision: revision, files: files, downloadSize: downloadSize)
  }

  /// The size of the model's files and its companions', which is what downloading it takes.
  var totalDownloadSize: Int64 {
    companions.reduce(downloadSize) { $0 + $1.downloadSize }
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

  var directory: URL { ownFiles.directory }

  /// Whether the model is installed.
  ///
  /// Its own files are installed after its companions', so a model downloaded with them only counts as installed once
  /// all are. A model installed before it had companions counts as installed without them.
  var isInstalled: Bool { ownFiles.isInstalled }
}

import Foundation
import OSLog
import Observation

/// The models of one kind installed on this Mac, and the ones downloading.
@MainActor
@Observable
final class ModelStore<Model: DownloadableModel> {
  enum DownloadState {
    case downloading(progress: Double)
    case failed
  }

  private(set) var installed: Set<Model.ID>
  /// Models downloading or whose last download failed.
  ///
  /// Cancelled downloads aren't listed.
  private(set) var downloads: [Model.ID: DownloadState] = [:]
  /// The model a `use(_:)` call is downloading to make it the active model once it's installed, including after its
  /// download failed, until the user chooses another model or cancels the download.
  ///
  /// It's saved, so a download Casper quits during resumes at the next launch.
  private(set) var awaitingUse: Model.ID?
  /// Each model's download, with the generation that tells it apart from an earlier download of the model it replaced.
  @ObservationIgnored private var tasks: [Model.ID: (generation: UUID, task: Task<Void, Never>)] = [:]
  /// Companions downloading for models installed before they had them, by ID.
  @ObservationIgnored private var companionTasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private let logger = Logger(subsystem: "io.jeph.Casper", category: "ModelStore")
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let installer: Installer

  /// Downloads and installs a model, calling the closure it's given with the fraction downloaded so far.
  typealias Installer = @Sendable (Model, @escaping @Sendable (Double) -> Void) async throws -> Void

  init(
    defaults: UserDefaults = .standard,
    installer: @escaping Installer = { model, progress in try await ModelDownloader.install(model, progress: progress) }
  ) {
    self.defaults = defaults
    self.installer = installer
    installed = Set(Model.all.filter(\.isInstalled).map(\.id))
    awaitingUse = defaults.string(forKey: Self.awaitingUseStorageKey)
  }

  /// The `UserDefaults` key for `awaitingUse`.
  private static var awaitingUseStorageKey: String { "\(Model.activeStorageKey)AwaitingDownload" }

  /// The ID of the model of this kind dictation uses, or `nil` if none is chosen.
  private var activeID: Model.ID? {
    defaults.string(forKey: Model.activeStorageKey).flatMap { id in Model.all.first { $0.id == id }?.id }
  }

  private func setActive(_ id: Model.ID) {
    defaults.set(id, forKey: Model.activeStorageKey)
  }

  private func setAwaitingUse(_ id: Model.ID?) {
    awaitingUse = id
    defaults.set(id, forKey: Self.awaitingUseStorageKey)
  }

  /// Starts again the download of the model `use(_:)` was downloading when Casper last quit, so that choice still takes
  /// effect.
  ///
  /// Only safe once the unfinished download's folder is removed.
  func resumeAwaitedDownload() {
    guard let awaitingUse else { return }
    guard let model = Model.all.first(where: { $0.id == awaitingUse }) else {
      setAwaitingUse(nil)
      return
    }
    use(model)
  }

  /// Makes `model` the active model, at once if it's installed or else once it's downloaded, which this starts.
  ///
  /// This replaces the choice of an earlier call that's still downloading, whose download is cancelled, so changing
  /// one's mind doesn't leave a model downloading that nobody chose.
  func use(_ model: Model) {
    if let awaitingUse, awaitingUse != model.id {
      tasks[awaitingUse]?.task.cancel()
    }
    guard !installed.contains(model.id) else {
      setAwaitingUse(nil)
      setActive(model.id)
      return
    }
    setAwaitingUse(model.id)
    download(model)
  }

  /// The model the user chose: the one `use(_:)` is downloading, or else the active model, whose ID the caller passes
  /// from `UserDefaults` so a view follows it changing, if it's installed.
  func chosenID(activeID: Model.ID) -> Model.ID? {
    awaitingUse ?? (installed.contains(activeID) ? activeID : nil)
  }

  /// Downloads and installs `model`, making it the active model if none is chosen yet or `use(_:)` is waiting for it.
  ///
  /// A download of the model that's cancelled but hasn't ended yet is replaced by a new one, so choosing a model again
  /// right after choosing another still downloads it.
  func download(_ model: Model) {
    guard !installed.contains(model.id), tasks[model.id]?.task.isCancelled ?? true else { return }
    let generation = UUID()
    downloads[model.id] = .downloading(progress: 0)
    let task = Task {
      do {
        try await installer(model) { fraction in
          Task { @MainActor in self.updateProgress(of: model, generation: generation, to: fraction) }
        }
        downloadEnded(model, generation: generation, error: nil)
      } catch {
        downloadEnded(model, generation: generation, error: error)
      }
    }
    tasks[model.id] = (generation, task)
  }

  func cancelDownload(of model: Model) {
    tasks[model.id]?.task.cancel()
  }

  /// Records how a download ended, unless a later download of the same model replaced it, which then decides.
  private func downloadEnded(_ model: Model, generation: UUID, error: (any Error)?) {
    guard let download = tasks[model.id], download.generation == generation else { return }
    tasks[model.id] = nil
    guard let error else {
      logger.info("Installed \(model.id, privacy: .public)")
      downloads[model.id] = nil
      installed.insert(model.id)
      if awaitingUse == model.id {
        setAwaitingUse(nil)
        setActive(model.id)
      } else if activeID == nil {
        setActive(model.id)
      }
      return
    }
    if download.task.isCancelled {
      downloads[model.id] = nil
      if awaitingUse == model.id {
        setAwaitingUse(nil)
      }
    } else {
      logger.error("Couldn't download \(model.id, privacy: .public): \(error)")
      downloads[model.id] = .failed
    }
    // Companions that finished before the model's own files did are kept only if another model needs them.
    deleteUnusedCompanions()
  }

  /// Downloads, in the background, the companions installed models don't have, such as Parakeet's word spotter for a
  /// Parakeet model installed before Casper used one.
  ///
  /// A model works without its companions until they arrive. One that fails to download is tried again at the next
  /// launch.
  func installMissingCompanions() {
    let missing = Set(Model.all.filter { installed.contains($0.id) }.flatMap(\.companions))
      .filter { !$0.isInstalled && companionTasks[$0.id] == nil }
    for companion in missing {
      companionTasks[companion.id] = Task {
        defer { companionTasks[companion.id] = nil }
        do {
          try await ModelDownloader.install([companion]) { _ in }
          logger.info("Installed \(companion.id, privacy: .public)")
        } catch {
          logger.error("Couldn't download \(companion.id, privacy: .public): \(error)")
        }
        // The model that needed it may have been deleted while it downloaded.
        deleteUnusedCompanions()
      }
    }
  }

  /// Deletes an installed model's files, unless it's the active model, along with companions no other model needs.
  func delete(_ model: Model) {
    guard installed.contains(model.id), activeID != model.id else { return }
    do {
      try FileManager.default.removeItem(at: model.directory)
    } catch {
      logger.error("Couldn't delete \(model.id, privacy: .public): \(error)")
      return
    }
    logger.info("Deleted \(model.id, privacy: .public)")
    installed.remove(model.id)
    deleteUnusedCompanions()
  }

  /// Deletes companions that no installed model needs, nor any model downloading.
  private func deleteUnusedCompanions() {
    let needed = Set(Model.all.filter { installed.contains($0.id) || tasks[$0.id] != nil }.flatMap(\.companions))
    let unused = Set(Model.all.flatMap(\.companions)).subtracting(needed).filter(\.isInstalled)
    for companion in unused {
      do {
        try FileManager.default.removeItem(at: companion.directory)
        logger.info("Deleted \(companion.id, privacy: .public), which no installed model needs")
      } catch {
        logger.error("Couldn't delete \(companion.id, privacy: .public): \(error)")
      }
    }
  }

  private func updateProgress(of model: Model, generation: UUID, to fraction: Double) {
    // Updates can arrive out of order, after the download finished or was cancelled, and from a download replaced since.
    guard tasks[model.id]?.generation == generation, case .downloading(let progress) = downloads[model.id],
      fraction > progress
    else { return }
    downloads[model.id] = .downloading(progress: fraction)
  }
}

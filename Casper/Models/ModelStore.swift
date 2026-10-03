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
  @ObservationIgnored private var tasks: [Model.ID: Task<Void, Never>] = [:]
  /// Companions downloading for models installed before they had them, by ID.
  @ObservationIgnored private var companionTasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private let logger = Logger(subsystem: "io.jeph.Casper", category: "ModelStore")

  init() {
    installed = Set(Model.all.filter(\.isInstalled).map(\.id))
  }

  /// Downloads and installs `model`, making it the active model if none is chosen yet.
  func download(_ model: Model) {
    guard tasks[model.id] == nil, !installed.contains(model.id) else { return }
    downloads[model.id] = .downloading(progress: 0)
    tasks[model.id] = Task {
      defer { tasks[model.id] = nil }
      do {
        try await ModelDownloader.install(model) { fraction in
          Task { @MainActor in self.updateProgress(of: model, to: fraction) }
        }
      } catch {
        if Task.isCancelled {
          downloads[model.id] = nil
        } else {
          logger.error("Couldn't download \(model.id, privacy: .public): \(error)")
          downloads[model.id] = .failed
        }
        // Companions that finished before the model's own files did are kept only if another model needs them.
        tasks[model.id] = nil
        deleteUnusedCompanions()
        return
      }
      logger.info("Installed \(model.id, privacy: .public)")
      downloads[model.id] = nil
      installed.insert(model.id)
      if Model.active == nil {
        UserDefaults.standard.set(model.id, forKey: Model.activeStorageKey)
      }
    }
  }

  func cancelDownload(of model: Model) {
    tasks[model.id]?.cancel()
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
    guard installed.contains(model.id), Model.active?.id != model.id else { return }
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

  private func updateProgress(of model: Model, to fraction: Double) {
    // Updates can arrive out of order, and after the download finished or was cancelled.
    guard case .downloading(let progress) = downloads[model.id], fraction > progress else { return }
    downloads[model.id] = .downloading(progress: fraction)
  }
}

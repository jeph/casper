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

  /// Deletes an installed model's files, unless it's the active model.
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
  }

  private func updateProgress(of model: Model, to fraction: Double) {
    // Updates can arrive out of order, and after the download finished or was cancelled.
    guard case .downloading(let progress) = downloads[model.id], fraction > progress else { return }
    downloads[model.id] = .downloading(progress: fraction)
  }
}

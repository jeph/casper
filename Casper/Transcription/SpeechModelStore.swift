import Foundation
import OSLog
import Observation

/// The speech models installed on this Mac, and the ones downloading.
@MainActor
@Observable
final class SpeechModelStore {
  enum DownloadState {
    case downloading(progress: Double)
    case failed
  }

  static let shared = SpeechModelStore()

  private(set) var installed: Set<SpeechModel.ID>
  /// Models downloading or whose last download failed.
  ///
  /// Cancelled downloads aren't listed.
  private(set) var downloads: [SpeechModel.ID: DownloadState] = [:]
  @ObservationIgnored private var tasks: [SpeechModel.ID: Task<Void, Never>] = [:]

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "SpeechModelStore")

  private init() {
    installed = Set(SpeechModel.all.filter(\.isInstalled).map(\.id))
  }

  /// Downloads and installs `model`, making it the active model if none is chosen yet.
  func download(_ model: SpeechModel) {
    guard tasks[model.id] == nil, !installed.contains(model.id) else { return }
    downloads[model.id] = .downloading(progress: 0)
    tasks[model.id] = Task {
      defer { tasks[model.id] = nil }
      do {
        try await SpeechModelDownloader.install(model) { fraction in
          Task { @MainActor in SpeechModelStore.shared.updateProgress(of: model, to: fraction) }
        }
      } catch {
        if Task.isCancelled {
          downloads[model.id] = nil
        } else {
          Self.logger.error("Couldn't download \(model.id, privacy: .public): \(error)")
          downloads[model.id] = .failed
        }
        return
      }
      Self.logger.info("Installed \(model.id, privacy: .public)")
      downloads[model.id] = nil
      installed.insert(model.id)
      if SpeechModel.active == nil {
        UserDefaults.standard.set(model.id, forKey: SpeechModel.activeStorageKey)
      }
    }
  }

  func cancelDownload(of model: SpeechModel) {
    tasks[model.id]?.cancel()
  }

  /// Deletes an installed model's files, unless it's the active model.
  func delete(_ model: SpeechModel) {
    guard installed.contains(model.id), SpeechModel.active?.id != model.id else { return }
    do {
      try FileManager.default.removeItem(at: model.directory)
    } catch {
      Self.logger.error("Couldn't delete \(model.id, privacy: .public): \(error)")
      return
    }
    Self.logger.info("Deleted \(model.id, privacy: .public)")
    installed.remove(model.id)
  }

  private func updateProgress(of model: SpeechModel, to fraction: Double) {
    // Updates can arrive out of order, and after the download finished or was cancelled.
    guard case .downloading(let progress) = downloads[model.id], fraction > progress else { return }
    downloads[model.id] = .downloading(progress: fraction)
  }
}

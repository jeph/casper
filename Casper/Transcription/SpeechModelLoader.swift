import Foundation
import OSLog

/// Loads the speech model when dictation needs it and unloads it to free memory, as the Speech Model Keep Alive
/// setting says.
///
/// The model counts as in use from when a recording starts until its transcription finishes. The keep-alive time is
/// counted from when it was last in use.
@MainActor
final class SpeechModelLoader {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "SpeechModelLoader")

  private let model: SpeechModel
  /// The loaded model, or the load in progress; `nil` while unloaded.
  private var loading: Task<any Transcriber, any Error>?
  /// How many dictations are using the model.
  private var users = 0
  /// The keep-alive setting in effect, compared against the stored one when settings change.
  private var keepAlive = KeepAlive.stored(forKey: KeepAlive.speechModelStorageKey)
  /// Unloads the model once the keep-alive time has passed since it was last in use.
  private var scheduledUnload: Task<Void, Never>?

  init(model: SpeechModel) {
    self.model = model
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.keepAliveSettingMayHaveChanged() }
    }
    applyKeepAlive()
  }

  /// Marks the model as in use and starts loading it if needed, so it loads while the user is still speaking.
  func beginUse() {
    users += 1
    scheduledUnload?.cancel()
    scheduledUnload = nil
    _ = load()
  }

  /// Marks one use of the model as finished, starting the keep-alive time once nothing is using it.
  func endUse() {
    users -= 1
    applyKeepAlive()
  }

  /// The model, loading it if needed.
  ///
  /// Only valid between `beginUse()` and `endUse()`, which keep the model from unloading.
  func transcriber() -> Task<any Transcriber, any Error> {
    load()
  }

  private func load() -> Task<any Transcriber, any Error> {
    if let loading {
      return loading
    }
    let model = model
    let task = Task.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let transcriber = try await model.loadTranscriber()
      Self.logger.info("Loaded the speech model in \(ContinuousClock.now - start, privacy: .public)")
      return transcriber
    }
    loading = task
    return task
  }

  private func unload() {
    guard let loading else { return }
    self.loading = nil
    Task {
      // A load that failed has nothing to unload.
      guard let transcriber = try? await loading.value else { return }
      await transcriber.unload()
      Self.logger.info("Unloaded the speech model")
    }
  }

  private func keepAliveSettingMayHaveChanged() {
    let stored = KeepAlive.stored(forKey: KeepAlive.speechModelStorageKey)
    guard stored != keepAlive else { return }
    keepAlive = stored
    applyKeepAlive()
  }

  /// Loads or unloads the model, or schedules it to unload, as the keep-alive setting says.
  ///
  /// Runs at launch, whenever the model stops being in use, and when the setting changes. A timed setting counts from
  /// when this runs.
  private func applyKeepAlive() {
    scheduledUnload?.cancel()
    scheduledUnload = nil
    guard users == 0 else { return }
    switch keepAlive {
    case .never:
      unload()
    case .always:
      _ = load()
    case .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes:
      guard loading != nil, let timeout = keepAlive.timeout else { return }
      scheduledUnload = Task {
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        // The sleep can finish just before a dictation cancels the task, in which case it doesn't throw.
        guard !Task.isCancelled else { return }
        scheduledUnload = nil
        unload()
      }
    }
  }
}

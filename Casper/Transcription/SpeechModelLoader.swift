import Foundation
import OSLog

/// Loads the speech model when dictation needs it, and unloads it to free memory.
///
/// The model counts as in use from when a recording starts until its transcription finishes. When to unload it is up
/// to a `KeepAliveSchedule`.
@MainActor
final class SpeechModelLoader {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "SpeechModelLoader")

  private let model: SpeechModel
  /// The loaded model, or the load in progress; `nil` while unloaded.
  private var loading: Task<any Transcriber, any Error>?
  /// How many dictations are using the model.
  private var users = 0

  init(model: SpeechModel) {
    self.model = model
  }

  var isInUse: Bool { users > 0 }
  var isLoaded: Bool { loading != nil }

  /// Marks the model as in use and starts loading it if needed, so it loads while the user is still speaking.
  func beginUse() {
    users += 1
    load()
  }

  /// Marks one use of the model as finished.
  func endUse() {
    users -= 1
  }

  /// The model, loading it if needed.
  ///
  /// Only valid between `beginUse()` and `endUse()`, which keep the model from unloading.
  func transcriber() -> Task<any Transcriber, any Error> {
    load()
  }

  /// Starts loading the model, if it isn't loaded or loading already.
  @discardableResult
  func load() -> Task<any Transcriber, any Error> {
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

  /// Unloads the model, after any load in progress finishes.
  ///
  /// Only call while the model isn't in use.
  func unload() {
    guard let loading else { return }
    self.loading = nil
    Task {
      // A load that failed has nothing to unload.
      guard let transcriber = try? await loading.value else { return }
      await transcriber.unload()
      Self.logger.info("Unloaded the speech model")
    }
  }
}

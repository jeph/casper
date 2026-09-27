import Foundation
import OSLog

/// Loads the active speech model when dictation needs it, and unloads it to free memory.
///
/// A model counts as in use from when a recording starts until its transcription finishes. When to unload it is up to
/// a `KeepAliveSchedule`. When the active model changes, the previous one unloads as soon as nothing is using it.
@MainActor
final class SpeechModelLoader {
  enum LoadError: Error {
    case noActiveModel
  }

  typealias Loading = Task<any Transcriber, any Error>
  private typealias Loaded = (model: SpeechModel, loading: Loading)

  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "SpeechModelLoader")

  /// The loaded model, or the load in progress; `nil` while unloaded.
  private var loaded: Loaded?
  /// Models the active model replaced while dictations were using them, unloaded once nothing is.
  private var replaced: [Loaded] = []
  /// How many dictations are using a model.
  private var users = 0

  var isInUse: Bool { users > 0 }
  var isLoaded: Bool { loaded != nil }

  /// Marks the model as in use and starts loading it if needed, so it loads while the user is still speaking.
  func beginUse() {
    // Loading first lets a model the active one replaced unload right away, if no other dictation is using it.
    load()
    users += 1
  }

  /// Marks one use of the model as finished, unloading models that are no longer active once nothing is in use.
  func endUse() {
    users -= 1
    guard users == 0 else { return }
    replaced.forEach(Self.unload)
    replaced = []
    unloadIfInactive()
  }

  /// The active model, loading it if needed.
  ///
  /// Only valid between `beginUse()` and `endUse()`, which keep the model from unloading.
  func transcriber() throws -> Loading {
    guard let loading = load() else { throw LoadError.noActiveModel }
    return loading
  }

  /// Starts loading the active model, if it isn't loaded or loading already, and returns it.
  @discardableResult
  func load() -> Loading? {
    guard let model = SpeechModel.active else { return nil }
    if let loaded, loaded.model.id == model.id {
      return loaded.loading
    }
    unload()
    let loading = Loading.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let transcriber = try await model.loadTranscriber()
      Self.logger.info("Loaded \(model.id, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
      return transcriber
    }
    loaded = (model, loading)
    // A load that fails is forgotten, so the next dictation tries again rather than reusing the failure.
    Task {
      guard case .failure(let error) = await loading.result else { return }
      Self.logger.error("Couldn't load \(model.id, privacy: .public): \(error)")
      if loaded?.loading == loading {
        loaded = nil
      }
    }
    return loading
  }

  /// Unloads the loaded model, or once nothing is using it if a dictation is.
  func unload() {
    guard let loaded else { return }
    self.loaded = nil
    if users == 0 {
      Self.unload(loaded)
    } else {
      replaced.append(loaded)
    }
  }

  /// Unloads the loaded model if it's no longer the active one and nothing is using it.
  func unloadIfInactive() {
    guard users == 0, let loaded, loaded.model.id != SpeechModel.active?.id else { return }
    unload()
  }

  /// Unloads a model after its load finishes.
  private static func unload(_ loaded: Loaded) {
    Task {
      // A load that failed has nothing to unload.
      guard let transcriber = try? await loaded.loading.value else { return }
      await transcriber.unload()
      logger.info("Unloaded \(loaded.model.id, privacy: .public)")
    }
  }
}

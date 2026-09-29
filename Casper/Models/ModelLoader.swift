import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "io.jeph.Casper", category: "ModelLoader")

/// A model Casper can load into memory once it's installed.
protocol LoadableModel: DownloadableModel {
  /// The model loaded into memory, ready to use.
  associatedtype Loaded: Sendable

  func load() async throws -> Loaded

  /// Frees the memory a loaded model uses, after which it can't be used.
  static func unload(_ loaded: Loaded) async
}

/// Loads the active model of one kind and keeps it in memory, so dictations don't wait for it.
///
/// A model stays loaded until the active model changes, or until `release()` says it's no longer needed. A model
/// counts as in use from when a recording starts until dictation is done with it, and one that's replaced or released
/// while in use unloads once nothing is using it.
@MainActor
final class ModelLoader<Model: LoadableModel> {
  enum LoadError: Error {
    case noActiveModel
  }

  typealias Loading = Task<Model.Loaded, any Error>
  private typealias Loaded = (model: Model, loading: Loading)

  /// The active model, or its load in progress; `nil` while nothing is loaded.
  private var loaded: Loaded?
  /// Models the active model replaced while dictations were using them, unloaded once nothing is.
  private var replaced: [Loaded] = []
  /// How many dictations are using a model.
  private var users = 0
  /// Whether the model stays loaded once no dictation is using it.
  private var staysLoaded = false

  /// Loads the active model, replacing a model that's no longer active, and keeps it loaded.
  func keepLoaded() {
    staysLoaded = true
    load()
  }

  /// Unloads the model, once nothing is using it, because nothing needs it anymore.
  func release() {
    staysLoaded = false
    if users == 0 {
      retireLoaded()
    }
  }

  /// Marks the model as in use and starts loading it if needed, so it loads while the user is still speaking.
  func beginUse() {
    users += 1
    load()
  }

  /// Marks one use of the model as finished, unloading models nothing needs once nothing is using them.
  func endUse() {
    users -= 1
    guard users == 0 else { return }
    replaced.forEach(Self.unload)
    replaced = []
    if !staysLoaded {
      retireLoaded()
    }
  }

  /// The active model, loading it if needed.
  ///
  /// Only valid between `beginUse()` and `endUse()`, which keep the model from unloading.
  func model() throws -> Loading {
    guard let loading = load() else { throw LoadError.noActiveModel }
    return loading
  }

  /// Starts loading the active model, unless it's loaded or loading already, and returns it.
  @discardableResult
  private func load() -> Loading? {
    guard let model = Model.active else {
      retireLoaded()
      return nil
    }
    if let loaded, loaded.model.id == model.id {
      return loaded.loading
    }
    retireLoaded()
    let loading = Loading.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let instance = try await model.load()
      logger.info("Loaded \(model.id, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
      return instance
    }
    loaded = (model, loading)
    // A load that fails is forgotten, so the next dictation tries again rather than reusing the failure.
    Task {
      guard case .failure(let error) = await loading.result else { return }
      logger.error("Couldn't load \(model.id, privacy: .public): \(error)")
      if loaded?.loading == loading {
        loaded = nil
      }
    }
    return loading
  }

  /// Unloads the loaded model, or once nothing is using it if a dictation is.
  private func retireLoaded() {
    guard let loaded else { return }
    self.loaded = nil
    if users == 0 {
      Self.unload(loaded)
    } else {
      replaced.append(loaded)
    }
  }

  /// Unloads a model after its load finishes.
  private static func unload(_ loaded: Loaded) {
    Task {
      // A load that failed has nothing to unload.
      guard let instance = try? await loaded.loading.value else { return }
      await Model.unload(instance)
      logger.info("Unloaded \(loaded.model.id, privacy: .public)")
    }
  }
}

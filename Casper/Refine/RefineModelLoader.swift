import OSLog

/// Loads the refine model when dictation needs it, and unloads it to free memory.
///
/// The model counts as in use from when a recording starts until its transcript is refined. When to unload it is up to
/// the speech model's `KeepAliveSchedule`, and to the refine setting.
@MainActor
final class RefineModelLoader {
  typealias Loading = Task<TranscriptRefiner, any Error>

  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "RefineModelLoader")

  /// The loaded model, or the load in progress; `nil` while unloaded.
  private var loading: Loading?
  /// How many dictations are using the model.
  private var users = 0

  var isInUse: Bool { users > 0 }
  var isLoaded: Bool { loading != nil }

  /// Marks the model as in use and starts loading it if needed, so it loads while the user is still speaking.
  func beginUse() {
    load()
    users += 1
  }

  func endUse() {
    users -= 1
  }

  /// Starts loading the model, if it isn't loaded or loading already, and returns it.
  @discardableResult
  func load() -> Loading {
    if let loading {
      return loading
    }
    let loading = Loading.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let refiner = try await TranscriptRefiner.load()
      Self.logger.info("Loaded the refine model in \(ContinuousClock.now - start, privacy: .public)")
      return refiner
    }
    self.loading = loading
    // A load that fails is forgotten, so the next dictation tries again rather than reusing the failure.
    Task {
      guard case .failure(let error) = await loading.result else { return }
      Self.logger.error("Couldn't load the refine model: \(error)")
      if self.loading == loading {
        self.loading = nil
      }
    }
    return loading
  }

  /// Unloads the model, unless a dictation is using it.
  func unload() {
    guard users == 0, let loading else { return }
    self.loading = nil
    Task {
      // A load that failed has nothing to unload.
      guard let refiner = try? await loading.value else { return }
      await refiner.unload()
      Self.logger.info("Unloaded the refine model")
    }
  }
}

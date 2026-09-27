import Foundation

/// Keeps something dictation needs, such as the microphone or the speech model, ready for as long as its keep-alive
/// setting says.
///
/// The owner reports when a dictation starts and stops using the resource. The schedule decides when to prepare and
/// release it: at launch, after the last use, and whenever the setting changes.
@MainActor
final class KeepAliveSchedule {
  private let storageKey: String
  private let isInUse: () -> Bool
  private let isPrepared: () -> Bool
  private let prepare: () -> Void
  private let release: () -> Void
  /// The setting in effect, compared against the stored one when settings change.
  private var setting: KeepAlive
  /// Releases the resource once the keep-alive time has passed since its last use.
  private var scheduledRelease: Task<Void, Never>?

  /// Creates a schedule for the setting stored under `storageKey` and applies the setting right away.
  ///
  /// - Parameters:
  ///   - storageKey: The `UserDefaults` key the keep-alive setting is stored under.
  ///   - isInUse: Whether a dictation is using the resource, which keeps it from being released.
  ///   - isPrepared: Whether the resource is ready, such as the microphone being on.
  ///   - prepare: Makes the resource ready, for the Always setting.
  ///   - release: Frees the resource.
  init(
    storageKey: String,
    isInUse: @escaping () -> Bool,
    isPrepared: @escaping () -> Bool,
    prepare: @escaping () -> Void,
    release: @escaping () -> Void
  ) {
    self.storageKey = storageKey
    self.isInUse = isInUse
    self.isPrepared = isPrepared
    self.prepare = prepare
    self.release = release
    setting = KeepAlive.stored(forKey: storageKey)
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.settingMayHaveChanged() }
    }
    apply()
  }

  /// Stops the countdown to releasing the resource, because a dictation started using it.
  func useStarted() {
    scheduledRelease?.cancel()
    scheduledRelease = nil
  }

  /// Applies the setting now that a dictation stopped using the resource, starting a timed setting's countdown.
  func useEnded() {
    apply()
  }

  private func settingMayHaveChanged() {
    let stored = KeepAlive.stored(forKey: storageKey)
    guard stored != setting else { return }
    setting = stored
    apply()
  }

  /// Prepares or releases the resource, or schedules its release, as the setting says.
  ///
  /// A timed setting counts from when this runs.
  private func apply() {
    scheduledRelease?.cancel()
    scheduledRelease = nil
    guard !isInUse() else { return }
    switch setting {
    case .never:
      release()
    case .always:
      prepare()
    case .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes:
      guard isPrepared(), let timeout = setting.timeout else { return }
      scheduledRelease = Task.afterDelay(timeout) { [weak self] in
        self?.scheduledRelease = nil
        self?.release()
      }
    }
  }
}

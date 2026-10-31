import AppKit
import Sparkle

/// Checks for a newer release once a day and asks before installing it, through Sparkle's update alert.
///
/// Casper never installs an update on its own. An update the user puts off stays in `availableVersion`, across
/// launches too, so the menu bar menu offers it until it's installed or skipped, and Sparkle asks again at the next
/// daily check. Local builds are numbered 0 and never check, so a build being tested isn't replaced by the latest
/// release.
@MainActor
@Observable
final class AppUpdater: NSObject {
  private static let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  private static let availableUpdateKey = "availableUpdate"

  /// Whether this build checks for updates, which only release builds do.
  let isEnabled = AppUpdater.currentBuild != "0"

  /// The version of the newer release a check found, until it's installed or the user skips it.
  ///
  /// It's saved, since after a relaunch Sparkle checks again only a day after the last check.
  private(set) var availableVersion: String?

  @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: self,
    userDriverDelegate: self
  )

  override init() {
    super.init()
    if isEnabled {
      availableVersion = Self.storedAvailableVersion()
    }
  }

  var checksAutomatically: Bool {
    get {
      access(keyPath: \.checksAutomatically)
      return controller.updater.automaticallyChecksForUpdates
    }
    set {
      withMutation(keyPath: \.checksAutomatically) {
        controller.updater.automaticallyChecksForUpdates = newValue
      }
    }
  }

  func start() {
    guard isEnabled else { return }
    controller.startUpdater()
  }

  /// Checks now, or brings back the alert for an update already found.
  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }

  private func setAvailableUpdate(_ item: SUAppcastItem?) {
    availableVersion = item?.displayVersionString
    guard let item else {
      UserDefaults.standard.removeObject(forKey: Self.availableUpdateKey)
      return
    }
    UserDefaults.standard.set(
      ["version": item.displayVersionString, "build": item.versionString],
      forKey: Self.availableUpdateKey
    )
  }

  /// The version an earlier launch found, unless this build is already that release or a newer one.
  private static func storedAvailableVersion() -> String? {
    guard let update = UserDefaults.standard.dictionary(forKey: availableUpdateKey) as? [String: String],
      let version = update["version"], let build = update["build"],
      SUStandardVersionComparator.default.compareVersion(build, toVersion: currentBuild) == .orderedDescending
    else {
      UserDefaults.standard.removeObject(forKey: availableUpdateKey)
      return nil
    }
    return version
  }
}

extension AppUpdater: SPUUpdaterDelegate {
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    setAvailableUpdate(item)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    setAvailableUpdate(nil)
  }

  func updater(
    _ updater: SPUUpdater,
    userDidMake choice: SPUUserUpdateChoice,
    forUpdate updateItem: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    if choice == .skip {
      setAvailableUpdate(nil)
    }
  }
}

// Sparkle calls its user driver's delegate on the main thread.
extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool { true }

  /// Shows the Dock icon while the update alert is open.
  ///
  /// Sparkle opens a daily check's alert behind other apps' windows rather than taking focus from what the user is
  /// typing into, so the Dock icon is what makes it findable. Closing the alert hides the icon again; see `AppDelegate`.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    guard handleShowingUpdate else { return }
    NSApp.setActivationPolicy(.regular)
  }
}

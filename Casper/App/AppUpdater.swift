import AppKit
import Sparkle

/// Checks for a newer release once a day through Sparkle, and by default downloads it in the background and installs it
/// the next time Casper quits.
///
/// An update found stays in `availableVersion`, across launches too, so the menu bar menu offers to install it right
/// away until it's installed or skipped. Each daily check also brings up Sparkle's update alert again, including for an
/// update already downloaded, since `SUScheduledImpatientCheckInterval` matches the check interval; choosing Skip This
/// Version in it stops the reminders for that release. Local builds are numbered 0 and never check, so a build being
/// tested isn't replaced by the latest release.
@MainActor
@Observable
final class AppUpdater: NSObject {
  private static let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  private static let availableUpdateKey = "availableUpdate"
  private static let lastCheckFailedKey = "lastUpdateCheckFailed"

  /// Whether this build checks for updates, which only release builds do.
  let isEnabled = AppUpdater.currentBuild != "0"

  /// The version of the newer release a check found, until it's installed or the user skips it.
  ///
  /// It's saved, since after a relaunch Sparkle checks again only a day after the last check.
  private(set) var availableVersion: String?

  /// Whether a check, or a download or install it started, is under way, including while Sparkle's alert is open.
  private(set) var isChecking = false

  /// Whether Sparkle can start a check or bring its open alert to the front, which it can't during a background
  /// download.
  private(set) var canCheckForUpdates = false

  /// When Casper last checked, on its own or when asked.
  private(set) var lastCheckDate: Date?

  /// Whether the last check ended in an error rather than finding an update or that Casper is up to date.
  ///
  /// It's saved alongside Sparkle's last check date, which a failed check also sets, so a relaunch doesn't report a
  /// failed check as up to date.
  private(set) var lastCheckFailed = UserDefaults.standard.bool(forKey: AppUpdater.lastCheckFailedKey) {
    didSet {
      UserDefaults.standard.set(lastCheckFailed, forKey: Self.lastCheckFailedKey)
    }
  }

  @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: self,
    userDriverDelegate: self
  )
  @ObservationIgnored private var observations: [NSKeyValueObservation] = []

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

  /// Whether a daily check downloads the update it finds and installs it when Casper quits, rather than asking first.
  var installsAutomatically: Bool {
    get {
      access(keyPath: \.installsAutomatically)
      return controller.updater.automaticallyDownloadsUpdates
    }
    set {
      withMutation(keyPath: \.installsAutomatically) {
        controller.updater.automaticallyDownloadsUpdates = newValue
      }
    }
  }

  func start() {
    guard isEnabled else { return }
    controller.startUpdater()
    lastCheckDate = controller.updater.lastUpdateCheckDate
    observeUpdater()
  }

  /// Checks now, or brings back the alert for an update already found, offering to install it.
  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }

  /// Checks now the way the daily check does, without an alert unless it finds an update and doesn't install updates
  /// automatically, so Settings can show the result itself.
  func checkInBackground() {
    controller.updater.checkForUpdatesInBackground()
  }

  /// Keeps the settings and status current when Sparkle changes them, such as from the checkbox in its update alert.
  private func observeUpdater() {
    let updater = controller.updater
    observations = [
      updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.withMutation(keyPath: \.checksAutomatically) {} }
      },
      updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.withMutation(keyPath: \.installsAutomatically) {} }
      },
      updater.observe(\.sessionInProgress, options: [.initial, .new]) { [weak self] updater, _ in
        MainActor.assumeIsolated {
          self?.isChecking = updater.sessionInProgress
          self?.lastCheckDate = updater.lastUpdateCheckDate
        }
      },
      updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
        MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
      },
    ]
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
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: (any Error)?
  ) {
    lastCheckDate = updater.lastUpdateCheckDate
    guard let error = error as NSError? else {
      lastCheckFailed = false
      return
    }
    // These end a check that worked: no newer release, or the user declining to authorize an install.
    let benignCodes = [SUError.noUpdateError, .installationCanceledError, .installationAuthorizeLaterError]
      .map { Int($0.rawValue) }
    lastCheckFailed = error.domain != SUSparkleErrorDomain || !benignCodes.contains(error.code)
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

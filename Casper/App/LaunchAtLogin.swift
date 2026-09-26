import OSLog
import ServiceManagement

/// Opens Casper when the user logs in, as one of the Mac's Login Items.
enum LaunchAtLogin {
  private static let defaultAppliedKey = "launchAtLoginDefaultApplied"
  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "LaunchAtLogin")

  static var status: SMAppService.Status { SMAppService.mainApp.status }

  /// Turns launch at login on the first time Casper runs.
  ///
  /// After that the user's choice stands, whether made in Casper's settings or in System Settings. A failed attempt
  /// is retried on the next launch.
  static func applyDefaultOnFirstLaunch() {
    guard !UserDefaults.standard.bool(forKey: defaultAppliedKey) else { return }
    if setEnabled(true) {
      UserDefaults.standard.set(true, forKey: defaultAppliedKey)
    }
  }

  /// Registers or unregisters Casper as a login item, returning whether it succeeded.
  @discardableResult
  static func setEnabled(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return true
    } catch {
      logger.error("Couldn't turn launch at login \(enabled ? "on" : "off"): \(error)")
      return false
    }
  }
}

extension SMAppService.Status {
  /// Whether Casper is registered, including when the user has turned it off in System Settings.
  var isRegistered: Bool { self == .enabled || self == .requiresApproval }
}

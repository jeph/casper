import OSLog
import ServiceManagement

/// Opens Casper when the user logs in, as one of the Mac's Login Items.
enum LaunchAtLogin {
  private static let choiceMadeKey = "launchAtLoginChoiceMade"
  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "LaunchAtLogin")

  static var status: SMAppService.Status { SMAppService.mainApp.status }

  /// Turns launch at login on the first time Casper runs.
  ///
  /// Once any change succeeds, this default or the user's own in Casper's settings, the choice stands and is never
  /// overridden, including changes made later in System Settings. A failed attempt is retried on the next launch.
  static func applyDefaultOnFirstLaunch() {
    guard !UserDefaults.standard.bool(forKey: choiceMadeKey) else { return }
    setEnabled(true)
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
      UserDefaults.standard.set(true, forKey: choiceMadeKey)
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

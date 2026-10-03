import AppKit

/// Starts dictation, applies the launch-at-login default, and keeps Casper menu bar only whenever none of its windows
/// are open.
///
/// `LSUIElement` starts the app without a Dock icon or menu bar. Opening a window through
/// `NSApplication.openWindowInFront(_:)` shows both, and closing the last one hides them again.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let readiness = DictationReadiness()
  let settingsNavigation = SettingsNavigation()
  let personas = PersonaStore()
  let history = DictationHistory()
  let dictionary = DictionaryStore()
  private lazy var learnedWordNotifier = LearnedWordNotifier(
    dictionary: dictionary,
    settingsNavigation: settingsNavigation
  )
  private var dictation: DictationController?
  private var voiceBubble: VoiceBubble?

  func applicationWillFinishLaunching(_ notification: Notification) {
    // The notifier becomes the notification center's delegate before launch finishes, so a click on a notification
    // that launched Casper reaches it.
    _ = learnedWordNotifier
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Before any download starts, since a download's folder looks unfinished until it's done.
    ModelDownloader.removeUnfinishedDownloads()
    SpeechModel.store.installMissingCompanions()
    let dictation = DictationController(
      readiness: readiness,
      personas: personas,
      history: history,
      dictionary: dictionary,
      learnedWordNotifier: learnedWordNotifier
    )
    self.dictation = dictation
    voiceBubble = VoiceBubble(status: dictation.status, readiness: readiness, settingsNavigation: settingsNavigation)
    LaunchAtLogin.applyDefaultOnFirstLaunch()
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
      notification in
      let closingWindow = (notification.object as AnyObject?).map(ObjectIdentifier.init)
      MainActor.assumeIsolated { Self.hideDockIconIfNoWindows(closingWindow: closingWindow) }
    }
  }

  /// Titled windows are the app's real windows; the menu bar extra and its menu are untitled.
  private static func hideDockIconIfNoWindows(closingWindow: ObjectIdentifier?) {
    let hasOpenWindow = NSApp.windows.contains { window in
      ObjectIdentifier(window) != closingWindow && window.isVisible && window.styleMask.contains(.titled)
    }
    if !hasOpenWindow {
      NSApp.setActivationPolicy(.accessory)
    }
  }
}

extension NSApplication {
  /// Shows the Dock icon and Casper's menus, runs `open`, and brings Casper's windows in front of other apps.
  ///
  /// A menu bar only app has no menus of its own, so the Dock icon comes with them. Casper is never the active app
  /// while its menu bar menu is in use, and `activate()` is only a request that macOS can decline, so the windows are
  /// also moved in front explicitly. `open` has already put the requested window above Casper's other windows, and
  /// that order is kept. `activate()` runs first because a declined activation still reorders Casper's windows when
  /// it's processed, which would undo that order.
  func openWindowInFront(_ open: () -> Void) {
    setActivationPolicy(.regular)
    activate()
    open()
    // SwiftUI creates the Settings window after this call returns.
    Task {
      let frontToBack = (NSWindow.windowNumbers(options: []) ?? [])
        .compactMap { window(withWindowNumber: $0.intValue) }
        .filter { $0.styleMask.contains(.titled) }
      for window in frontToBack.reversed() {
        window.orderFrontRegardless()
      }
    }
  }
}

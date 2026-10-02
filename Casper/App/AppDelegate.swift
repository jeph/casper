import AppKit

/// Starts dictation, applies the launch-at-login default, and keeps Casper menu bar only whenever it's in the
/// background with none of its windows open.
///
/// `LSUIElement` starts the app without a Dock icon or menu bar. `NSApplication.bringForward()` shows both, and
/// they're hidden again when the last window closes or Casper stops being the active app without a window open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let readiness = DictationReadiness()
  let settingsNavigation = SettingsNavigation()
  let personas = PersonaStore()
  private var dictation: DictationController?
  private var voiceBubble: VoiceBubble?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let dictation = DictationController(readiness: readiness, personas: personas)
    self.dictation = dictation
    voiceBubble = VoiceBubble(status: dictation.status, readiness: readiness, settingsNavigation: settingsNavigation)
    LaunchAtLogin.applyDefaultOnFirstLaunch()
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
      notification in
      let closingWindow = (notification.object as AnyObject?).map(ObjectIdentifier.init)
      MainActor.assumeIsolated {
        // Menus, tooltips, and the menu bar Casper gets while it's in front open and close untitled windows. Only a
        // real window closing can leave Casper with nothing to show; otherwise it stays until it loses focus.
        guard let closingWindow, Self.isTitledWindow(closingWindow) else { return }
        Self.hideDockIconIfNoWindows(closingWindow: closingWindow)
      }
    }
    // Clicking the voice bubble brings Casper forward without opening a window.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { Self.hideDockIconIfNoWindows(closingWindow: nil) }
    }
  }

  private static func isTitledWindow(_ id: ObjectIdentifier) -> Bool {
    NSApp.windows.contains { ObjectIdentifier($0) == id && $0.styleMask.contains(.titled) }
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
  /// Makes Casper the active app, showing its Dock icon and its menus in the menu bar, like a regular app.
  ///
  /// A menu bar only app has no menus of its own, so the Dock icon comes with them. `activate()` is only a request
  /// that macOS can decline.
  func bringForward() {
    setActivationPolicy(.regular)
    activate()
  }

  /// Brings Casper forward, runs `open`, and brings Casper's windows in front of other apps.
  ///
  /// Casper is never the active app while its menu bar menu is in use, and activation can be declined, so the windows
  /// are also moved in front explicitly. `open` has already put the requested window above Casper's other windows,
  /// and that order is kept. Activation is requested first because a declined activation still reorders Casper's
  /// windows when it's processed, which would undo that order.
  func openWindowInFront(_ open: () -> Void) {
    bringForward()
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

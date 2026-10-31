import AppKit
import SwiftUI

struct MenuBarMenu: View {
  @Environment(\.openSettings) private var openSettings
  @Environment(AppUpdater.self) private var updater

  var body: some View {
    if let version = updater.availableVersion {
      Button("Install Casper \(version)…", systemImage: "arrow.down.circle") {
        NSApp.openWindowInFront { updater.checkForUpdates() }
      }
      Divider()
    }
    InputDevicePicker {
      Text("Input Device")
    }
    Divider()
    Button("About Casper") {
      NSApp.openWindowInFront { NSApp.orderFrontStandardAboutPanel(nil) }
    }
    if updater.isEnabled && updater.availableVersion == nil {
      Button("Check for Updates…") {
        NSApp.openWindowInFront { updater.checkForUpdates() }
      }
    }
    Button("Settings…") {
      NSApp.openWindowInFront { openSettings() }
    }
    .keyboardShortcut(",")
    Divider()
    Button("Quit Casper") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

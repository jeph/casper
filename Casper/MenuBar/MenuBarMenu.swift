import AppKit
import SwiftUI

struct MenuBarMenu: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("About Casper") {
      // Menu bar apps are never frontmost, so windows would open behind other apps.
      NSApp.activate()
      NSApp.orderFrontStandardAboutPanel(nil)
    }
    Button("Settings…") {
      NSApp.activate()
      openSettings()
    }
    .keyboardShortcut(",")
    Divider()
    Button("Quit Casper") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

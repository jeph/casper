import AppKit
import SwiftUI

struct MenuBarMenu: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    InputDevicePicker {
      Text("Input Device")
    }
    Divider()
    Button("About Casper") {
      NSApp.openWindowInFront { NSApp.orderFrontStandardAboutPanel(nil) }
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

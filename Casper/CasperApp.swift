import AppKit
import SwiftUI

@main
struct CasperApp: App {
  var body: some Scene {
    MenuBarExtra("Casper", systemImage: "waveform") {
      MenuContent()
    }
    Settings {
      SettingsView()
    }
  }
}

private struct MenuContent: View {
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

import SwiftUI

@main
struct CasperApp: App {
  var body: some Scene {
    MenuBarExtra("Casper", systemImage: "waveform") {
      MenuBarMenu()
    }
    Settings {
      SettingsView()
    }
  }
}

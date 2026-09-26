import SwiftUI

@main
struct CasperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    MenuBarExtra("Casper", image: "CasperMenuBar") {
      MenuBarMenu()
    }
    Settings {
      SettingsView()
    }
  }
}

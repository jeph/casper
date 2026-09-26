import SwiftUI

@main
struct CasperApp: App {
  var body: some Scene {
    MenuBarExtra("Casper", image: "CasperMenuBar") {
      MenuBarMenu()
    }
    Settings {
      SettingsView()
    }
  }
}

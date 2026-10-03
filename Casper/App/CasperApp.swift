import SwiftUI

@main
struct CasperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu()
    } label: {
      MenuBarIcon()
    }
    Settings {
      SettingsView()
        .environment(appDelegate.readiness)
        .environment(appDelegate.readiness.permissions)
        .environment(appDelegate.settingsNavigation)
        .environment(appDelegate.personas)
        .environment(appDelegate.history)
        .environment(appDelegate.dictionary)
    }
  }
}

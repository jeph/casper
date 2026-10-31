import SwiftUI

@main
struct CasperApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu()
        .environment(appDelegate.updater)
    } label: {
      MenuBarIcon()
        .environment(appDelegate.settingsNavigation)
    }
    Settings {
      SettingsView()
        .environment(appDelegate.readiness)
        .environment(appDelegate.readiness.permissions)
        .environment(appDelegate.settingsNavigation)
        .environment(appDelegate.personas)
        .environment(appDelegate.runningApps)
        .environment(appDelegate.history)
        .environment(appDelegate.dictionary)
        .environment(appDelegate.updater)
    }
    Window(
      Text("Welcome to Casper", comment: "Title of the setup window and of its first step."),
      id: OnboardingView.windowID
    ) {
      OnboardingView()
        .environment(appDelegate.readiness)
        .environment(appDelegate.readiness.permissions)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    // The menu bar icon opens setup, and only until it's finished.
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}

import AppKit
import SwiftUI

/// Casper's icon in the menu bar, which also opens setup at launch until the user has finished it, and Settings
/// whenever code that isn't a view asks for it through `SettingsNavigation`.
///
/// Once setup is finished, launches start in the menu bar only. The icon is the one view SwiftUI creates on every
/// launch, and opening a window needs a view's `openWindow` or `openSettings` action.
struct MenuBarIcon: View {
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  @Environment(SettingsNavigation.self) private var settingsNavigation

  var body: some View {
    Image("CasperMenuBar")
      .accessibilityLabel(
        Text("Casper", comment: "App name, used as the accessibility label of the menu bar icon and the voice bubble.")
      )
      .onAppear {
        guard !UserDefaults.standard.bool(forKey: OnboardingView.completedStorageKey) else { return }
        NSApp.openWindowInFront { openWindow(id: OnboardingView.windowID) }
      }
      // Initially too, for a request made as Casper launched, such as by clicking one of its notifications.
      .onChange(of: settingsNavigation.isOpenRequested, initial: true) {
        guard settingsNavigation.isOpenRequested else { return }
        settingsNavigation.isOpenRequested = false
        NSApp.openWindowInFront { openSettings() }
      }
  }
}

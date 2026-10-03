import AppKit
import SwiftUI

/// Casper's icon in the menu bar, which also opens Settings the first time Casper runs so new users can set it up, and
/// whenever code that isn't a view asks for it through `SettingsNavigation`.
///
/// Later launches start in the menu bar only. The icon is the one view SwiftUI creates on every launch, and opening
/// Settings needs a view's `openSettings` action.
struct MenuBarIcon: View {
  @Environment(\.openSettings) private var openSettings
  @Environment(SettingsNavigation.self) private var settingsNavigation

  private static let hasLaunchedKey = "hasLaunched"

  var body: some View {
    Image("CasperMenuBar")
      .accessibilityLabel(
        Text("Casper", comment: "App name, used as the accessibility label of the menu bar icon and the voice bubble.")
      )
      .onAppear {
        guard !UserDefaults.standard.bool(forKey: Self.hasLaunchedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)
        NSApp.openWindowInFront { openSettings() }
      }
      // Initially too, for a request made as Casper launched, such as by clicking one of its notifications.
      .onChange(of: settingsNavigation.isOpenRequested, initial: true) {
        guard settingsNavigation.isOpenRequested else { return }
        settingsNavigation.isOpenRequested = false
        NSApp.openWindowInFront { openSettings() }
      }
  }
}

import AppKit
import SwiftUI

/// Casper's icon in the menu bar, which also opens Settings the first time Casper runs so new users can set it up.
///
/// Later launches start in the menu bar only. The icon is the one view SwiftUI creates on every launch, and opening
/// Settings needs a view's `openSettings` action.
struct MenuBarIcon: View {
  @Environment(\.openSettings) private var openSettings

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
  }
}

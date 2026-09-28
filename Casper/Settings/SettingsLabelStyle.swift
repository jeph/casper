import SwiftUI

/// Lines up the titles of Settings rows by giving every row's icon the same width.
///
/// A form places a label's title right after its icon, and SF Symbols have different widths, so a wide icon such as
/// `keyboard` would push its title to the right of the others.
struct SettingsLabelStyle: LabelStyle {
  @ScaledMetric(relativeTo: .body) private var iconWidth = 20.0

  func makeBody(configuration: Configuration) -> some View {
    Label {
      configuration.title
    } icon: {
      configuration.icon.frame(width: iconWidth)
    }
  }
}

extension LabelStyle where Self == SettingsLabelStyle {
  static var settings: SettingsLabelStyle { SettingsLabelStyle() }
}

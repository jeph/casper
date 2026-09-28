import SwiftUI

/// A Settings tab's symbol with a warning triangle in its corner, for pages that fix something dictation needs.
///
/// Settings tabs show only a plain image and a title, ignoring badges, so the triangle is drawn into the image. The
/// image isn't a template, which would lose the triangle's color, and the tab dims it like its other symbols.
struct BadgedTabIcon {
  let systemImage: String
  let colorScheme: ColorScheme
  let displayScale: CGFloat

  private static let symbolSize: CGFloat = 20
  private static let badgeSize: CGFloat = 12

  @MainActor
  var image: Image {
    let renderer = ImageRenderer(content: content)
    renderer.scale = displayScale
    guard let cgImage = renderer.cgImage else { return Image(systemName: systemImage) }
    let image = NSImage(
      cgImage: cgImage,
      size: NSSize(width: CGFloat(cgImage.width) / displayScale, height: CGFloat(cgImage.height) / displayScale)
    )
    image.isTemplate = false
    image.accessibilityDescription = String(
      localized: "Needs attention",
      comment: "Accessibility description of the warning on a Settings tab whose page fixes something."
    )
    return Image(nsImage: image)
  }

  private var content: some View {
    Image(systemName: systemImage)
      .font(.system(size: Self.symbolSize))
      .foregroundStyle(.primary)
      .padding(2)
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: Self.badgeSize, weight: .semibold))
          .symbolRenderingMode(.multicolor)
          .background {
            // A ring cut out of the symbol keeps the triangle readable where they overlap.
            Image(systemName: "triangle.fill")
              .font(.system(size: Self.badgeSize + 4, weight: .black))
              .blendMode(.destinationOut)
          }
      }
      .compositingGroup()
      .environment(\.colorScheme, colorScheme)
  }
}

import SwiftUI

/// The Casper ghost, drawn from `Design/Casper-Ghost.svg` in the foreground style, with its three bars cut out, or an
/// exclamation mark instead when something needs the user's attention.
///
/// The bars can be given heights of their own, so they can move with the voice, and the cut-out filled with a color.
struct GhostLogo: View {
  /// Each bar's height, from 0 for a dot to 1 for as tall as it can be; `nil` draws the bars as in the logo.
  var barLevels: [Double]?
  /// Whether an exclamation mark is cut out instead of the bars.
  var showsExclamationMark = false
  /// The color filling the cut-out, or `nil` to leave it see-through.
  var cutoutFill: Color?

  /// The ghost's bounds in the SVG's coordinates.
  private static let bounds = CGRect(x: 76, y: 67, width: 104, height: 114)
  /// The bars' horizontal centers, logo heights, and tallest heights that stay inside the ghost, in SVG coordinates.
  private static let bars: [(centerX: CGFloat, logoHeight: CGFloat, maxHeight: CGFloat)] = [
    (108, 28, 56), (128, 53, 84), (148, 36, 64),
  ]
  private static let barWidth: CGFloat = 12
  private static let barCenterY: CGFloat = 124

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / Self.bounds.width, size.height / Self.bounds.height)
      context.translateBy(
        x: (size.width - Self.bounds.width * scale) / 2,
        y: (size.height - Self.bounds.height * scale) / 2
      )
      context.scaleBy(x: scale, y: scale)
      context.translateBy(x: -Self.bounds.minX, y: -Self.bounds.minY)
      let cutout = showsExclamationMark ? Self.exclamationMark : barPaths
      context.drawLayer { layer in
        layer.fill(Self.body, with: .foreground)
        layer.blendMode = .destinationOut
        layer.fill(cutout, with: .color(.black))
      }
      if let cutoutFill {
        context.fill(cutout, with: .color(cutoutFill))
      }
    }
    .aspectRatio(Self.bounds.width / Self.bounds.height, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private var barPaths: Path {
    var path = Path()
    for (index, bar) in Self.bars.enumerated() {
      let height =
        barLevels.map { levels in
          Self.barWidth + (bar.maxHeight - Self.barWidth) * min(max(levels[index], 0), 1)
        } ?? bar.logoHeight
      path.addRoundedRect(
        in: CGRect(
          x: bar.centerX - Self.barWidth / 2,
          y: Self.barCenterY - height / 2,
          width: Self.barWidth,
          height: height
        ),
        cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
      )
    }
    return path
  }

  /// A stroke as wide as a bar above a dot, centered where the bars are.
  private static let exclamationMark = Path { path in
    let left = 128 - barWidth / 2
    let corner = CGSize(width: barWidth / 2, height: barWidth / 2)
    path.addRoundedRect(in: CGRect(x: left, y: 92, width: barWidth, height: 44), cornerSize: corner)
    path.addEllipse(in: CGRect(x: left, y: 146, width: barWidth, height: barWidth))
  }

  private static let body = Path { path in
    path.move(to: CGPoint(x: 76, y: 117))
    path.addCurve(to: CGPoint(x: 128, y: 67), control1: CGPoint(x: 76, y: 88), control2: CGPoint(x: 98, y: 67))
    path.addCurve(to: CGPoint(x: 180, y: 117), control1: CGPoint(x: 158, y: 67), control2: CGPoint(x: 180, y: 88))
    path.addLine(to: CGPoint(x: 180, y: 164))
    path.addCurve(to: CGPoint(x: 170, y: 181), control1: CGPoint(x: 180, y: 175), control2: CGPoint(x: 177, y: 181))
    path.addCurve(to: CGPoint(x: 154, y: 169), control1: CGPoint(x: 163, y: 181), control2: CGPoint(x: 161, y: 169))
    path.addCurve(to: CGPoint(x: 128, y: 181), control1: CGPoint(x: 145, y: 169), control2: CGPoint(x: 143, y: 181))
    path.addCurve(to: CGPoint(x: 102, y: 169), control1: CGPoint(x: 113, y: 181), control2: CGPoint(x: 111, y: 169))
    path.addCurve(to: CGPoint(x: 86, y: 181), control1: CGPoint(x: 95, y: 169), control2: CGPoint(x: 93, y: 181))
    path.addCurve(to: CGPoint(x: 76, y: 164), control1: CGPoint(x: 79, y: 181), control2: CGPoint(x: 76, y: 175))
    path.closeSubpath()
  }
}

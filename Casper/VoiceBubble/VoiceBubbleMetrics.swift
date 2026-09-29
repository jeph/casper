import CoreGraphics

/// The voice bubble's dimensions at one of its sizes, all scaled from the width of its circle.
///
/// Size 2 is the original 44 pt bubble, and each size is about 15% larger than the one before. Bars are rounded to half
/// points so they stay sharp on Retina screens, and the waveform shows the same number of bars at every size.
struct VoiceBubbleMetrics: Equatable {
  /// The sizes the setting offers, from smallest to largest.
  static let sizes = 1...5
  static let defaultSize = 3
  /// How much the bubble grows while the pointer is over it.
  static let hoverScale: CGFloat = 1.08
  /// The widest the callout above or below the bubble gets before its text wraps.
  static let calloutMaxWidth: CGFloat = 260
  /// Room above and below the bubble for the callout and the gap to it, which doesn't scale with the bubble's size.
  static let calloutRoom: CGFloat = 64
  private static let diameters: [CGFloat] = [38, 44, 50, 58, 66]
  /// The size the other dimensions were designed at, and are scaled from.
  private static let designDiameter: CGFloat = 44
  /// How many bars, each followed by a gap as wide as itself, fit across the waveform.
  private static let waveformBarCount: CGFloat = 16

  let diameter: CGFloat
  let ghostHeight: CGFloat
  let barWidth: CGFloat
  let waveformSize: CGSize
  let waveformInnerSpacing: CGFloat
  let waveformOuterPadding: CGFloat
  /// Room around the bubble for its shadow and for springing slightly past its size.
  let margin: CGFloat

  init(size: Int) {
    let size = min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound)
    diameter = Self.diameters[size - Self.sizes.lowerBound]
    let scale = diameter / Self.designDiameter
    ghostHeight = (22 * scale).rounded()
    barWidth = (3 * scale * 2).rounded() / 2
    waveformSize = CGSize(width: Self.waveformBarCount * barWidth * 2, height: ghostHeight)
    waveformInnerSpacing = (2 * scale).rounded()
    waveformOuterPadding = (16 * scale).rounded()
    margin = (16 * scale).rounded()
  }

  /// How far the bubble reaches right of the ghost's center when it's grown.
  var reach: CGFloat { diameter / 2 + waveformInnerSpacing + waveformSize.width + waveformOuterPadding }

  /// The bubble at its largest size, which the panel is sized and placed for.
  static let largest = VoiceBubbleMetrics(size: sizes.upperBound)

  /// The panel's size, with room around the ghost for the largest grown bubble and the callout on either side, so it
  /// stays the same size as the bubble resizes inside it.
  ///
  /// Placed beside the ghost, the callout can reach a whole callout's width to one side of it.
  static let panelSize = CGSize(
    width: max(largest.reach + largest.margin, calloutMaxWidth) * 2,
    height: largest.diameter + (largest.margin + calloutRoom) * 2
  )
}

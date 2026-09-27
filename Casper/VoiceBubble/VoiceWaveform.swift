import SwiftUI

/// The recording's loudness as bars scrolling from the trailing edge, updated each frame from the audio level meter.
///
/// Audio arrives in chunks about a tenth of a second apart, so the bars trail it slightly to scroll evenly.
struct VoiceWaveform: View {
  let meter: AudioLevelMeter
  /// When the recording started, which the bars are counted from.
  let start: ContinuousClock.Instant
  let size: CGSize
  /// The width of each bar, and of the gap after it.
  let barWidth: CGFloat

  /// The length of audio each bar shows, which sets how fast the bars scroll: slow enough to feel unhurried.
  static let barSeconds = 0.12
  /// How far the bars trail the audio, longer than the gap between chunks.
  static let delay = Duration.milliseconds(120)

  var body: some View {
    // The bars are passed in fresh each frame, because a canvas on glass only redraws when its inputs change.
    TimelineView(.animation) { _ in
      WaveformBars(bars: bars(at: ContinuousClock.now - Self.delay))
    }
    .frame(width: size.width, height: size.height)
    .mask {
      // Bars fade in at the trailing edge and out at the leading one, rather than being cut off.
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0), .init(color: .black, location: 0.25),
          .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    .accessibilityHidden(true)
  }

  private func bars(at now: ContinuousClock.Instant) -> [CGRect] {
    let step = barWidth * 2
    let position = (now - start).seconds / Self.barSeconds
    let newestBar = Int(position.rounded(.down))
    let barCount = Int(size.width / step) + 2
    let levels = meter.levels(since: start + .seconds(Double(newestBar - barCount) * Self.barSeconds))
    let loudest = levels.loudestForScaling
    return (0..<barCount)
      .map { age in
        let bar = newestBar - age
        let scaled = Self.level(ofBar: bar, start: start, levels: levels, loudest: loudest)
        let height = barWidth + (size.height - barWidth) * CGFloat(pow(scaled, 0.8))
        let centerX = size.width + step / 2 - (position - Double(bar)) * step
        return CGRect(
          x: centerX - barWidth / 2,
          y: (size.height - height) / 2,
          width: barWidth,
          height: height
        )
      }
  }

  /// The loudest level in a bar's stretch of audio, relative to the loudest recent level, from 0 to 1.
  static func level(
    ofBar bar: Int,
    start: ContinuousClock.Instant,
    levels: [AudioLevelMeter.Level],
    loudest: Float
  ) -> Double {
    guard bar >= 0 else { return 0 }
    let barStart = start + .seconds(Double(bar) * barSeconds)
    return Double(min(levels.peak(from: barStart, to: barStart + .seconds(barSeconds)) / loudest, 1))
  }
}

/// Rounded bars at the given positions, drawn with a canvas as the ghost is so glass shows them at full contrast.
private struct WaveformBars: View {
  let bars: [CGRect]

  var body: some View {
    Canvas { context, _ in
      for bar in bars {
        context.fill(Path(roundedRect: bar, cornerRadius: bar.width / 2), with: .foreground)
      }
    }
  }
}

extension [AudioLevelMeter.Level] {
  /// The amplitude to show as full height: the loudest of these levels, but no less than quiet speech, so silence and
  /// room noise stay low while speech fills the height whatever the microphone's gain.
  var loudestForScaling: Float {
    Swift.max(lazy.map(\.value).max() ?? 0, 0.02)
  }

  /// The loudest level measured in the given time range, or 0 if none was.
  func peak(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Float {
    var peak: Float = 0
    for level in self where level.time >= start && level.time < end {
      peak = Swift.max(peak, level.value)
    }
    return peak
  }
}

extension Duration {
  var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}

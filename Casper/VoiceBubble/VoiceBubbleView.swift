import SwiftUI

/// The voice bubble: the Casper ghost on glass, which grows a live waveform while recording and moves its bars while
/// transcribing.
///
/// The ghost sits at the center of the panel and the waveform always grows to its right. Near the right edge of the
/// screen, the grown bubble slides left as it grows, so it stays on screen with the ghost at its leading end.
struct VoiceBubbleView: View {
  let status: DictationStatus
  let layout: VoiceBubbleLayout
  @State private var recordingStart = ContinuousClock.now
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let metrics = layout.metrics
    let isRecording = status.phase == .recording
    HStack(spacing: 0) {
      ghost
        .frame(width: metrics.diameter, height: metrics.diameter)
      if isRecording {
        waveform
          .padding(.leading, metrics.waveformInnerSpacing)
          .padding(.trailing, metrics.waveformOuterPadding)
      }
    }
    .frame(height: metrics.diameter)
    // The waveform appears and fades while the bubble grows and shrinks; the mask keeps it inside the bubble's padding
    // throughout, so it never reaches the glass's edge.
    .mask {
      HStack(spacing: 0) {
        Rectangle()
          .frame(width: metrics.diameter)
        Rectangle()
          .padding(.trailing, metrics.waveformOuterPadding)
      }
    }
    .modifier(BubbleBackground())
    // The circle grows from its center, and the grown bubble from its leading end so the ghost stays put.
    .scaleEffect(isHovered ? VoiceBubbleMetrics.hoverScale : 1, anchor: isRecording ? .leading : .center)
    .onHover { isHovered = $0 }
    .animation(.spring(duration: 0.25, bounce: 0.35), value: isHovered)
    .offset(x: isRecording ? -layout.recordingShift : 0)
    .padding(.leading, metrics.panelSize.width / 2 - metrics.diameter / 2)
    .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .leading)
    .animation(.spring(duration: 0.35, bounce: 0.2), value: isRecording)
    .onChange(of: isRecording) { _, isRecording in
      if isRecording {
        recordingStart = .now
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text("Casper", comment: "App name, used as the accessibility label of the menu bar icon and the voice bubble.")
    )
    .accessibilityValue(phaseDescription)
  }

  private var waveform: some View {
    VoiceWaveform(
      meter: status.meter,
      start: recordingStart,
      size: layout.metrics.waveformSize,
      barWidth: layout.metrics.barWidth
    )
    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
  }

  private var ghost: some View {
    TimelineView(.animation(paused: status.phase == .idle)) { timeline in
      GhostLogo(barLevels: barLevels(at: timeline.date), barFill: barFill)
        .frame(height: layout.metrics.ghostHeight)
        .opacity(status.phase == .transcribing && reduceMotion ? fadingOpacity(at: timeline.date) : 1)
    }
  }

  /// Red while recording, and blue while the model transcribes; the logo's own cut-out bars otherwise.
  private var barFill: Color? {
    switch status.phase {
    case .idle: nil
    case .recording: .red
    case .transcribing: .blue
    }
  }

  /// The ghost's bar heights for the current phase, or `nil` for the logo's own.
  ///
  /// While recording, each bar glides between the heights of the waveform's latest full bars, a bar apart from the
  /// next, so they share the waveform's peaks and valleys at its calmer pace. While transcribing, the bars rise and
  /// fall in turn.
  private func barLevels(at date: Date) -> [Double]? {
    switch status.phase {
    case .idle:
      return nil
    case .recording:
      let now = ContinuousClock.now - VoiceWaveform.delay
      let position = (now - recordingStart).seconds / VoiceWaveform.barSeconds
      let newestBar = Int(position.rounded(.down))
      let progress = position - Double(newestBar)
      // Eases in and out of each height rather than moving at a constant speed.
      let glide = progress * progress * (3 - 2 * progress)
      let levels = status.meter.levels(since: now - .seconds(2))
      let loudest = levels.loudestForScaling
      func level(_ bar: Int) -> Double {
        VoiceWaveform.level(ofBar: bar, start: recordingStart, levels: levels, loudest: loudest)
      }
      // The newest bar is still filling, so the ghost follows the full bars before it.
      return [2, 0, 1]
        .map { slot in
          let bar = newestBar - 1 - slot
          return level(bar - 1) + (level(bar) - level(bar - 1)) * glide
        }
    case .transcribing:
      guard !reduceMotion else { return nil }
      let time = date.timeIntervalSinceReferenceDate
      return (0..<3)
        .map { index in
          0.2 + 0.5 * (sin(time * 2 * .pi * 1.2 - Double(index) * 0.9) + 1) / 2
        }
    }
  }

  /// With Reduce Motion on, transcribing fades the ghost in and out instead of moving its bars.
  private func fadingOpacity(at date: Date) -> Double {
    0.55 + 0.45 * (cos(date.timeIntervalSinceReferenceDate * 2 * .pi * 0.8) + 1) / 2
  }

  private var phaseDescription: Text {
    switch status.phase {
    case .idle:
      Text("Ready", comment: "Accessibility value of the voice bubble when Casper isn't dictating.")
    case .recording:
      Text("Listening", comment: "Accessibility value of the voice bubble while the dictation shortcut is held.")
    case .transcribing:
      Text("Transcribing", comment: "Accessibility value of the voice bubble while a recording is being transcribed.")
    }
  }
}

/// The voice bubble's size, and how far the grown bubble slides left to stay on screen where it sits.
@MainActor
@Observable
final class VoiceBubbleLayout {
  var metrics: VoiceBubbleMetrics
  var recordingShift: CGFloat = 0

  init(metrics: VoiceBubbleMetrics) {
    self.metrics = metrics
  }
}

/// Liquid Glass on macOS 26 and later, and the closest material before it.
private struct BubbleBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      // Interactive glass responds to the pointer the way system controls do.
      content.glassEffect(.regular.interactive(), in: .capsule)
    } else {
      content
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
  }
}

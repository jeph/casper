import SwiftUI

/// The voice bubble: the Casper ghost on glass, which grows a live waveform while recording and moves its bars while
/// transcribing.
///
/// The ghost sits at the center of the panel and the waveform always grows to its right. Near the right edge of the
/// screen, the grown bubble slides left as it grows, so it stays on screen with the ghost at its leading end.
struct VoiceBubbleView: View {
  let status: DictationStatus
  let placement: VoiceBubblePlacement
  @State private var recordingStart = ContinuousClock.now
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let diameter: CGFloat = 44
  private static let ghostHeight: CGFloat = 22
  private static let waveformWidth: CGFloat = 96
  private static let waveformHeight: CGFloat = 22
  private static let waveformInnerSpacing: CGFloat = 2
  private static let waveformOuterPadding: CGFloat = 16
  /// Room around the bubble for its shadow and for springing slightly past its size.
  private static let margin: CGFloat = 16
  /// How far the bubble reaches right of the ghost's center when it's grown.
  static let reach = diameter / 2 + waveformInnerSpacing + waveformWidth + waveformOuterPadding
  /// How much the bubble grows while the pointer is over it.
  static let hoverScale: CGFloat = 1.08
  static let panelSize = CGSize(width: (reach + margin) * 2, height: diameter + margin * 2)

  var body: some View {
    let isRecording = status.phase == .recording
    HStack(spacing: 0) {
      ghost
        .frame(width: Self.diameter, height: Self.diameter)
      if isRecording {
        waveform
          .padding(.leading, Self.waveformInnerSpacing)
          .padding(.trailing, Self.waveformOuterPadding)
      }
    }
    .frame(height: Self.diameter)
    .modifier(BubbleBackground())
    // The circle grows from its center, and the grown bubble from its leading end so the ghost stays put.
    .scaleEffect(isHovered ? Self.hoverScale : 1, anchor: isRecording ? .leading : .center)
    .onHover { isHovered = $0 }
    .animation(.spring(duration: 0.25, bounce: 0.35), value: isHovered)
    .offset(x: isRecording ? -placement.recordingShift : 0)
    .padding(.leading, Self.panelSize.width / 2 - Self.diameter / 2)
    .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .leading)
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
      size: CGSize(width: Self.waveformWidth, height: Self.waveformHeight)
    )
    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
  }

  private var ghost: some View {
    TimelineView(.animation(paused: status.phase == .idle)) { timeline in
      GhostLogo(barLevels: barLevels(at: timeline.date), barFill: status.phase == .recording ? .accentColor : nil)
        .frame(height: Self.ghostHeight)
        .opacity(status.phase == .transcribing && reduceMotion ? fadingOpacity(at: timeline.date) : 1)
    }
  }

  /// The ghost's bar heights for the current phase, or `nil` for the logo's own.
  ///
  /// While recording, each bar follows the voice a moment apart, in step with the waveform's newest bar. While
  /// transcribing, the bars rise and fall in turn.
  private func barLevels(at date: Date) -> [Double]? {
    switch status.phase {
    case .idle:
      return nil
    case .recording:
      let now = ContinuousClock.now - .milliseconds(120)
      let barDuration = Duration.seconds(VoiceWaveform.barSeconds)
      let levels = status.meter.levels(since: now - .seconds(2))
      let loudest = levels.loudestForScaling
      return [2, 0, 1]
        .map { slot in
          let end = now - barDuration * slot
          return Double(min(levels.peak(from: end - barDuration, to: end) / loudest, 1))
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

/// Where the voice bubble sits on screen, which decides how far the grown bubble slides left to stay on screen.
@MainActor
@Observable
final class VoiceBubblePlacement {
  var recordingShift: CGFloat = 0
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

import SwiftUI

/// The voice bubble: the Casper ghost on glass, which grows a live waveform while recording and moves its bars while
/// transcribing.
///
/// The ghost sits at the center of the panel and the waveform always grows to its right. Near the right edge of the
/// screen, the grown bubble slides left as it grows, so it stays on screen with the ghost at its leading end.
///
/// Hovering over the bubble shows the dictation hotkey in a callout.
struct VoiceBubbleView: View {
  let status: DictationStatus
  let layout: VoiceBubbleLayout
  @AppStorage(Hotkey.dictationStorageKey) private var hotkey = Hotkey.dictationDefault
  @State private var recordingStart = ContinuousClock.now
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let calloutGap: CGFloat = 8

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
    .modifier(GlassBackground(shape: Capsule(), isInteractive: true))
    // The circle grows from its center, and the grown bubble from its leading end so the ghost stays put.
    .scaleEffect(isHovered ? VoiceBubbleMetrics.hoverScale : 1, anchor: isRecording ? .leading : .center)
    .onHover { isHovered = $0 }
    .animation(.spring(duration: 0.25, bounce: 0.35), value: isHovered)
    .overlay(alignment: .topLeading) { calloutAnchor }
    .animation(.easeOut(duration: 0.15), value: showsHotkey)
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

  private var showsHotkey: Bool { isHovered && status.phase == .idle }

  /// Places the callout above the ghost, or below it near the top of the screen, lined up with the ghost's center or,
  /// near the screen's side, its edge.
  private var calloutAnchor: some View {
    let isBelow = layout.showsCalloutBelow
    let gap = Self.calloutGap
    return Color.clear
      .frame(width: layout.metrics.diameter, height: layout.metrics.diameter)
      .overlay(alignment: Alignment(horizontal: layout.calloutAlignment, vertical: isBelow ? .bottom : .top)) {
        ZStack {
          if showsHotkey {
            hotkeyCallout
              .transition(.opacity.combined(with: .offset(y: isBelow ? -4 : 4)))
          }
        }
        .frame(
          width: VoiceBubbleMetrics.calloutMaxWidth,
          alignment: Alignment(horizontal: layout.calloutAlignment, vertical: .center)
        )
        .alignmentGuide(isBelow ? .bottom : .top) { dimensions in
          isBelow ? dimensions[.top] - gap : dimensions[.bottom] + gap
        }
      }
      .allowsHitTesting(false)
  }

  private var hotkeyCallout: some View {
    Text(
      "Hold \(hotkey.displayName) to dictate",
      comment: "Shown when hovering over the voice bubble. The argument is the dictation shortcut, such as ⌥Space."
    )
    .font(.callout)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), isInteractive: false))
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
      // The oldest bar used starts up to five bars back, and is scaled to the moments before it.
      let oldestBarStart = now - .seconds(VoiceWaveform.barSeconds * 5)
      let levels = status.meter.levels(since: oldestBarStart - VoiceWaveform.scalingWindow)
      func level(_ bar: Int) -> Double {
        VoiceWaveform.level(ofBar: bar, start: recordingStart, levels: levels)
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

/// The voice bubble's size, where it places its callout, and how far the grown bubble slides left to stay on screen
/// where it sits.
@MainActor
@Observable
final class VoiceBubbleLayout {
  var metrics: VoiceBubbleMetrics
  var recordingShift: CGFloat = 0
  var showsCalloutBelow = false
  var calloutAlignment = HorizontalAlignment.center

  init(metrics: VoiceBubbleMetrics) {
    self.metrics = metrics
  }
}

/// Liquid Glass on macOS 26 and later, and the closest material before it.
private struct GlassBackground<GlassShape: InsettableShape>: ViewModifier {
  let shape: GlassShape
  /// Whether the glass responds to the pointer the way system controls do.
  let isInteractive: Bool

  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.glassEffect(.regular.interactive(isInteractive), in: shape)
    } else {
      content
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
  }
}

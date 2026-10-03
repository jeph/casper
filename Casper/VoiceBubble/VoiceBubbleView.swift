import AppKit
import SwiftUI

/// The voice bubble: the Casper ghost on glass, which grows a live waveform while recording and moves its bars while
/// transcribing.
///
/// The ghost sits at the center of the panel, or off it toward a nearby screen edge, and the waveform always grows to its
/// right. Near the right edge of the screen, the grown bubble slides left as it grows, so it stays on screen with the
/// ghost at its leading end.
///
/// Hovering over the bubble shows the dictation hotkey in a callout, and clicking it opens Settings. While something
/// dictation needs is missing, the ghost shows an exclamation mark instead, the callout says what's missing when the
/// bubble is hovered or the hotkey is pressed, and clicking opens the Settings page that fixes it.
struct VoiceBubbleView: View {
  let status: DictationStatus
  let layout: VoiceBubbleLayout
  let readiness: DictationReadiness
  let settingsNavigation: SettingsNavigation
  @AppStorage(Hotkey.dictationStorageKey) private var hotkey = Hotkey.dictationDefault
  @AppStorage(DictationMode.storageKey) private var dictationMode = DictationMode.defaultValue
  @State private var recordingStart = ContinuousClock.now
  @State private var isHovered = false
  /// Whether the warning callout stays up after a hotkey press, without the bubble being hovered.
  @State private var isWarningPinned = false
  /// How far the bubble has faded to its dictating colors, from 0 for not at all to 1 for fully.
  @State private var dictationColorAmount = 0.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openSettings) private var openSettings

  /// What the callout next to the bubble shows.
  private enum Callout: Equatable {
    case hotkey
    case warning(DictationReadiness.Warning)
  }

  /// How long the warning callout stays up after a hotkey press.
  private static let warningDuration = Duration.seconds(4)
  private static let calloutGap: CGFloat = 8
  /// How long the bubble takes to grow and slide when recording starts and stops, or its size setting changes.
  private static let resizeDuration = 0.35
  /// How the bubble fades to and from its dictating colors, finishing shortly before it settles when it grows.
  private static let dictationColorFade = Animation.easeInOut(duration: resizeDuration - 0.05)

  var body: some View {
    let metrics = layout.metrics
    let panelSize = VoiceBubbleMetrics.panelSize
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
    .modifier(
      GlassBackground(
        shape: Capsule(),
        isInteractive: true,
        tint: .accentColor,
        tintAmount: dictationColorAmount
      )
    )
    // The circle grows from its center, and the grown bubble from its leading end so the ghost stays put.
    .scaleEffect(isHovered ? VoiceBubbleMetrics.hoverScale : 1, anchor: isRecording ? .leading : .center)
    .onHover { isHovered = $0 }
    .animation(.spring(duration: 0.25, bounce: 0.35), value: isHovered)
    .overlay(alignment: .topLeading) { calloutAnchor }
    .animation(.easeOut(duration: 0.15), value: callout)
    .offset(x: isRecording ? -layout.recordingShift : 0)
    .offset(layout.ghostOffset)
    .padding(.leading, panelSize.width / 2 - metrics.diameter / 2)
    .frame(width: panelSize.width, height: panelSize.height, alignment: .leading)
    .animation(.spring(duration: Self.resizeDuration, bounce: 0.2), value: isRecording)
    .animation(.spring(duration: Self.resizeDuration, bounce: 0.2), value: metrics)
    .onChange(of: isRecording) { _, isRecording in
      if isRecording {
        recordingStart = .now
      }
    }
    .onChange(of: isDictating, initial: true) { _, isDictating in
      withAnimation(Self.dictationColorFade) {
        dictationColorAmount = isDictating ? 1 : 0
      }
    }
    .task(id: status.pressesWhileNotReady) {
      guard status.pressesWhileNotReady > 0 else { return }
      isWarningPinned = true
      // A later press restarts the wait rather than hiding the callout early.
      guard (try? await Task.sleep(for: Self.warningDuration)) != nil else { return }
      isWarningPinned = false
    }
    .onChange(of: layout.clicks) {
      if let warning = readiness.warning {
        settingsNavigation.pane = warning.pane
      } else if isDictating {
        // Dictated text is pasted into whichever app is frontmost when it's ready, so Casper stays in the background
        // until nothing is waiting to be typed.
        return
      }
      NSApp.openWindowInFront { openSettings() }
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
    // On the bubble in the accent color, the waveform is white like the ghost.
    .foregroundStyle(.white)
    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
  }

  private var ghost: some View {
    TimelineView(.animation(paused: !isDictating)) { timeline in
      GhostLogo(
        barLevels: barLevels(at: timeline.date),
        showsExclamationMark: showsWarning,
        fill: .white,
        fillAmount: dictationColorAmount
      )
      .frame(height: layout.metrics.ghostHeight)
      .opacity(status.phase == .transcribing && reduceMotion ? fadingOpacity(at: timeline.date) : 1)
    }
  }

  /// Whether the ghost shows an exclamation mark, while something is missing and it isn't showing dictation.
  private var showsWarning: Bool { !readiness.isReady && !isDictating }

  /// Whether dictation is underway, from the moment recording starts until the last transcript is typed, during which
  /// the bubble stays in the accent color so it never changes between recording and transcribing.
  private var isDictating: Bool { status.phase != .idle }

  private var callout: Callout? {
    if let warning = readiness.warning, isHovered || isWarningPinned {
      return .warning(warning)
    }
    return isHovered && status.phase == .idle ? .hotkey : nil
  }

  /// Places the callout above the ghost, or below it near the top of the screen, lined up with the ghost's center or,
  /// near the screen's side, its edge.
  private var calloutAnchor: some View {
    let isBelow = layout.showsCalloutBelow
    let gap = Self.calloutGap
    return Color.clear
      .frame(width: layout.metrics.diameter, height: layout.metrics.diameter)
      .overlay(alignment: Alignment(horizontal: layout.calloutAlignment, vertical: isBelow ? .bottom : .top)) {
        ZStack {
          if let callout {
            calloutView(callout)
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

  private func calloutView(_ callout: Callout) -> some View {
    Group {
      switch callout {
      case .hotkey:
        switch dictationMode {
        case .hold:
          Text(
            "Hold \(hotkey.displayName) to dictate",
            comment: "Voice bubble hover text in hold mode. The argument is the dictation shortcut, such as ⌥Space."
          )
        case .toggle:
          Text(
            "Press \(hotkey.displayName) to dictate",
            comment: "Voice bubble hover text in toggle mode. The argument is the dictation shortcut, such as ⌥Space."
          )
        }
      case .warning(let warning):
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
          VStack(alignment: .leading, spacing: 2) {
            Text(warning.message)
              .fontWeight(.semibold)
            Text(warning.action)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
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
      readiness.warning.map { Text($0.message) }
        ?? Text("Ready", comment: "Accessibility value of the voice bubble when Casper isn't dictating.")
    case .recording:
      Text("Listening", comment: "Accessibility value of the voice bubble while dictation is recording.")
    case .transcribing:
      Text("Transcribing", comment: "Accessibility value of the voice bubble while a recording is being transcribed.")
    }
  }
}

/// The voice bubble's size, how far the ghost sits from the panel's center, where it places its callout and how far the
/// grown bubble slides left to stay on screen where it sits, and the clicks the panel receives on it.
@MainActor
@Observable
final class VoiceBubbleLayout {
  var metrics: VoiceBubbleMetrics
  var recordingShift: CGFloat = 0
  /// How far the ghost sits from the panel's center, where the bubble's size lets it sit closer to the screen's edge
  /// than the largest bubble would.
  var ghostOffset = CGSize.zero
  var showsCalloutBelow = false
  var calloutAlignment = HorizontalAlignment.center
  /// Counts clicks on the bubble that didn't drag it.
  var clicks = 0

  init(metrics: VoiceBubbleMetrics) {
    self.metrics = metrics
  }
}

/// Liquid Glass on macOS 26 and later, and the closest material before it, tinted with a color that fades in and out.
///
/// In a window that isn't active, as the bubble's panel never is, glass leaves its own tint out, except clear glass on
/// macOS 27 and later. Elsewhere the tint is a solid fill beneath the content instead.
private struct GlassBackground<GlassShape: InsettableShape>: ViewModifier, Animatable {
  let shape: GlassShape
  /// Whether the glass responds to the pointer the way system controls do.
  let isInteractive: Bool
  /// The color the glass fades to, or `nil` for glass that's never tinted.
  var tint: Color?
  /// How far the tint has faded in, from 0 for not at all to 1 for fully.
  var tintAmount = 0.0

  nonisolated var animatableData: Double {
    get { tintAmount }
    set { tintAmount = newValue }
  }

  func body(content: Content) -> some View {
    if #available(macOS 27, *) {
      content.glassEffect(glass, in: shape)
    } else if #available(macOS 26, *) {
      filled(content).glassEffect(.regular.interactive(isInteractive), in: shape)
    } else {
      filled(content)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
  }

  private func filled(_ content: Content) -> some View {
    content.background(tint?.opacity(tintAmount) ?? .clear, in: shape)
  }

  /// How strong the glass's tint is when fully faded in, short of solid so the tinted bubble still reads as glass.
  private static var fullTint: Double { 0.5 }

  /// Regular glass, or clear glass when it's tinted, since that's the glass that keeps its tint.
  @available(macOS 27, *)
  private var glass: Glass {
    guard let tint else { return .regular.interactive(isInteractive) }
    return .clear.tint(tint.opacity(tintAmount * Self.fullTint)).interactive(isInteractive)
  }
}

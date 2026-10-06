import SwiftUI

/// Shows how to dictate, over and over: the shortcut's keys go down, the voice bubble listens, and once the shortcut
/// says to stop, the bubble transcribes and the sentence appears in a text field.
///
/// The keys are the user's dictation shortcut, and they're held or pressed twice as the user's shortcut mode needs.
struct DictationDemo: View {
  private enum Stage {
    case idle
    case recording
    case transcribing
    case typed
  }

  @State private var stage = Stage.idle
  @State private var areKeysDown = false
  @State private var recordingStart = Date.now
  @AppStorage(Hotkey.dictationStorageKey) private var hotkey = Hotkey.dictationDefault
  @AppStorage(DictationMode.storageKey) private var dictationMode = DictationMode.defaultValue
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The voice bubble's size the demo shows it at.
  private static let metrics = VoiceBubbleMetrics(size: 2)
  private static let screenSize = CGSize(width: 400, height: 128)
  private static let screenPadding: CGFloat = 18
  /// The length of audio each bar of the waveform shows, as in the voice bubble.
  private static let barSeconds = VoiceWaveform.barSeconds

  var body: some View {
    VStack(spacing: 12) {
      screen
      HStack(spacing: 6) {
        ForEach(Array(hotkey.keyLabels.enumerated()), id: \.offset) { _, label in
          Keycap(label: label, isDown: areKeysDown)
        }
      }
      caption
        .font(.callout)
        .foregroundStyle(.secondary)
        .id(stage)
        .transition(.opacity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "An animation of dictating: pressing the shortcut, speaking, and Casper typing what was said into a text field.",
        comment: "Accessibility label of setup's animation of how to dictate."
      )
    )
    .task(id: dictationMode) { await loop() }
  }

  /// A window with a text field, and the voice bubble near the bottom of the screen.
  private var screen: some View {
    VStack(alignment: .leading) {
      textField
      Spacer(minLength: 0)
      bubble
        // Centered as a whole, so it grows to both sides as it opens and shrinks back to the middle as it closes.
        .frame(maxWidth: .infinity)
    }
    .padding(Self.screenPadding)
    .frame(width: Self.screenSize.width, height: Self.screenSize.height)
    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
  }

  private var textField: some View {
    HStack(spacing: 1) {
      if stage == .typed {
        Text(RefineDemo.refinedText)
          .lineLimit(1)
          .transition(.opacity)
      }
      Caret(blinks: !reduceMotion)
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    .background(.background, in: .rect(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
  }

  private var bubble: some View {
    let metrics = Self.metrics
    let isDictating = stage == .recording || stage == .transcribing
    return HStack(spacing: 0) {
      TimelineView(.animation(paused: !isDictating || reduceMotion)) { timeline in
        GhostLogo(
          barLevels: ghostBarLevels(at: timeline.date),
          fill: .white,
          fillAmount: isDictating ? 1 : 0
        )
        .frame(height: metrics.ghostHeight)
      }
      .frame(width: metrics.diameter, height: metrics.diameter)
      if stage == .recording {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
          Canvas { context, _ in
            for bar in waveformBars(at: timeline.date) {
              context.fill(Path(roundedRect: bar, cornerRadius: bar.width / 2), with: .foreground)
            }
          }
        }
        .frame(width: metrics.waveformSize.width, height: metrics.waveformSize.height)
        .foregroundStyle(.white)
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .black, location: 0.25),
              .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        }
        .padding(.leading, metrics.waveformInnerSpacing)
        .padding(.trailing, metrics.waveformOuterPadding)
        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
      }
    }
    .frame(height: metrics.diameter)
    .modifier(
      GlassBackground(shape: Capsule(), isInteractive: false, tint: .accentColor, tintAmount: isDictating ? 1 : 0)
    )
  }

  @ViewBuilder
  private var caption: some View {
    switch (stage, dictationMode) {
    case (.idle, .hold):
      Text("Hold the shortcut", comment: "Caption of setup's dictation animation as the shortcut is about to be held.")
    case (.idle, .toggle):
      Text(
        "Press the shortcut",
        comment: "Caption of setup's dictation animation as the shortcut is about to be pressed."
      )
    case (.recording, .hold):
      Text("Speak while you hold it", comment: "Caption of setup's dictation animation while it records.")
    case (.recording, .toggle):
      Text("Speak, then press it again", comment: "Caption of setup's dictation animation while it records.")
    case (.transcribing, _):
      Text("Casper transcribes and refines it", comment: "Caption of setup's dictation animation while it transcribes.")
    case (.typed, _):
      Text(
        "And types it where your cursor is",
        comment: "Caption of setup's dictation animation once the sentence appears in a text field."
      )
    }
  }

  private func loop() async {
    stage = .idle
    areKeysDown = false
    while true {
      guard await pause(1.4) else { return }
      setKeys(down: true)
      recordingStart = .now
      withAnimation(.spring(duration: 0.35, bounce: 0.2)) { stage = .recording }
      if dictationMode == .toggle {
        guard await pause(0.25) else { return }
        setKeys(down: false)
        guard await pause(2.6) else { return }
        setKeys(down: true)
        guard await pause(0.25) else { return }
      } else {
        guard await pause(3.1) else { return }
      }
      setKeys(down: false)
      withAnimation(.spring(duration: 0.35, bounce: 0.2)) { stage = .transcribing }
      guard await pause(1.1) else { return }
      withAnimation(.easeInOut(duration: 0.3)) { stage = .typed }
      guard await pause(3) else { return }
      withAnimation(.easeInOut(duration: 0.3)) { stage = .idle }
    }
  }

  private func setKeys(down: Bool) {
    withAnimation(.spring(duration: 0.15, bounce: 0.3)) { areKeysDown = down }
  }

  /// Waits, returning whether it waited the whole time rather than being cancelled.
  private func pause(_ seconds: Double) async -> Bool {
    (try? await Task.sleep(for: .seconds(seconds))) != nil
  }

  /// A made-up loudness for each bar of the recording, from 0 to 1, that rises and falls the way speech does.
  private static func level(ofBar bar: Int) -> Double {
    guard bar >= 0 else { return 0 }
    let bar = Double(bar)
    return 0.15 + 0.85 * abs(sin(bar * 1.7) * cos(bar * 0.63))
  }

  /// The ghost's bars: gliding between the waveform's latest full bars while recording, as the voice bubble's do,
  /// rising and falling in turn while transcribing, and as in the logo otherwise.
  private func ghostBarLevels(at date: Date) -> [Double]? {
    guard !reduceMotion else { return nil }
    switch stage {
    case .idle, .typed:
      return nil
    case .recording:
      let position = date.timeIntervalSince(recordingStart) / Self.barSeconds
      let newestBar = Int(position.rounded(.down))
      let progress = position - Double(newestBar)
      // Eases in and out of each height rather than moving at a constant speed.
      let glide = progress * progress * (3 - 2 * progress)
      return [2, 0, 1]
        .map { slot in
          let bar = newestBar - 1 - slot
          return Self.level(ofBar: bar - 1) + (Self.level(ofBar: bar) - Self.level(ofBar: bar - 1)) * glide
        }
    case .transcribing:
      let time = date.timeIntervalSinceReferenceDate
      return (0..<3).map { index in 0.2 + 0.5 * (sin(time * 2 * .pi * 1.2 - Double(index) * 0.9) + 1) / 2 }
    }
  }

  /// The waveform's bars, scrolling in from the trailing edge, as the voice bubble draws them.
  private func waveformBars(at date: Date) -> [CGRect] {
    let size = Self.metrics.waveformSize
    let barWidth = Self.metrics.barWidth
    let step = barWidth * 2
    let position = reduceMotion ? 40 : date.timeIntervalSince(recordingStart) / Self.barSeconds
    let newestBar = Int(position.rounded(.down))
    return (0..<Int(size.width / step) + 2)
      .map { age in
        let bar = newestBar - age
        let height = barWidth + (size.height - barWidth) * Self.level(ofBar: bar)
        let centerX = size.width + step / 2 - (position - Double(bar)) * step
        return CGRect(x: centerX - barWidth / 2, y: (size.height - height) / 2, width: barWidth, height: height)
      }
  }
}

/// A key on a keyboard, which sinks while it's pressed.
private struct Keycap: View {
  let label: String
  let isDown: Bool

  var body: some View {
    Text(verbatim: label)
      .font(.system(size: label.count > 1 ? 13 : 17, weight: .medium))
      .foregroundStyle(isDown ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
      .frame(minWidth: label.count > 1 ? 110 : 38, minHeight: 38)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.background)
          .shadow(color: .black.opacity(isDown ? 0.12 : 0.3), radius: isDown ? 0.5 : 1, y: isDown ? 0.5 : 2)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(isDown ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isDown ? 1.5 : 0.5)
      }
      .scaleEffect(isDown ? 0.94 : 1)
      .offset(y: isDown ? 1.5 : 0)
  }
}

/// A text field's insertion point, blinking unless Reduce Motion is on.
private struct Caret: View {
  let blinks: Bool

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
      let isShown = !blinks || Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
      Rectangle()
        .frame(width: 1.5, height: 16)
        .opacity(isShown ? 1 : 0)
    }
  }
}

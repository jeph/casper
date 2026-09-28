import Foundation

/// How the dictation hotkey starts and stops recording.
enum DictationMode: String, CaseIterable, Identifiable {
  /// Records while the hotkey is held and stops when it's released.
  case hold
  /// Starts recording when the hotkey is pressed and stops when it's pressed again.
  case toggle

  enum HotkeyEvent {
    case press
    case release
  }

  /// What a hotkey event does to dictation.
  enum Action: Equatable {
    case startRecording
    /// Ends the recording once the last moment of speech is recorded.
    case stopRecording
    /// Cancels a stop that's waiting for the last moment of speech, so the same recording goes on.
    case continueRecording
  }

  /// The `UserDefaults` key the dictation mode is stored under.
  static let storageKey = "dictationMode"
  static let defaultValue = DictationMode.hold

  /// The stored mode, or the default if none is stored.
  static var stored: DictationMode {
    UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var id: Self { self }

  /// Decides what a hotkey event does in this mode.
  ///
  /// - Parameters:
  ///   - event: Whether the hotkey was pressed or released.
  ///   - isRecording: Whether a recording is in progress, including one waiting to stop.
  ///   - isStopping: Whether the recording is waiting for its last moment of speech before it stops.
  /// - Returns: What to do, or `nil` if the event does nothing.
  func action(for event: HotkeyEvent, isRecording: Bool, isStopping: Bool) -> Action? {
    switch event {
    case .press:
      // Pressing again before the recording stops continues the same recording.
      if isStopping { return .continueRecording }
      guard isRecording else { return .startRecording }
      // A press while recording in hold mode means the mode was switched mid-recording; the release stops it.
      return self == .toggle ? .stopRecording : nil
    case .release:
      return self == .hold && isRecording && !isStopping ? .stopRecording : nil
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .hold: "Hold to Talk"
    case .toggle: "Press to Toggle"
    }
  }
}

import Foundation

/// How the dictation hotkey starts and stops recording.
enum DictationMode: String, CaseIterable, Identifiable {
  /// Records while the hotkey is held and stops when it's released.
  case hold
  /// Starts recording when the hotkey is pressed and stops when it's pressed again.
  case toggle

  /// The `UserDefaults` key the dictation mode is stored under.
  static let storageKey = "dictationMode"
  static let defaultValue = DictationMode.hold

  /// The stored mode, or the default if none is stored.
  static var stored: DictationMode {
    UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .hold: "Hold to Talk"
    case .toggle: "Press to Toggle"
    }
  }
}

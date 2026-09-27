import Foundation

/// How long the microphone stays on after a dictation, so the next one starts without waiting for it to turn on.
enum MicrophoneKeepAlive: String, CaseIterable, Identifiable {
  case off
  case oneMinute
  case fiveMinutes
  case tenMinutes
  case fifteenMinutes
  /// On from launch until Casper quits.
  case always

  /// The `UserDefaults` key the setting is stored under.
  static let storageKey = "microphoneKeepAlive"
  static let defaultValue = MicrophoneKeepAlive.oneMinute

  /// The stored setting, or the default if none is stored.
  static var stored: MicrophoneKeepAlive {
    UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var id: Self { self }

  /// How long the microphone stays on after a dictation, or `nil` for Off and Always, which don't turn it off later.
  var timeout: Duration? {
    switch self {
    case .off, .always: nil
    case .oneMinute: .seconds(60)
    case .fiveMinutes: .seconds(5 * 60)
    case .tenMinutes: .seconds(10 * 60)
    case .fifteenMinutes: .seconds(15 * 60)
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .off: "Off"
    case .oneMinute: "1 Minute"
    case .fiveMinutes: "5 Minutes"
    case .tenMinutes: "10 Minutes"
    case .fifteenMinutes: "15 Minutes"
    case .always: "Always"
    }
  }
}

import Foundation

/// How long something Casper needs for dictation, such as the microphone or the models, stays ready after the
/// last dictation, so the next one doesn't wait for it.
enum KeepAlive: String, CaseIterable, Identifiable {
  /// Released as soon as each dictation ends.
  case never
  case oneMinute
  case fiveMinutes
  case tenMinutes
  case fifteenMinutes
  /// Ready from launch until Casper quits.
  case always

  /// The `UserDefaults` key for how long the microphone stays on.
  static let microphoneStorageKey = "microphoneKeepAlive"
  /// The `UserDefaults` key for how long the speech and language models stay loaded.
  static let modelStorageKey = "modelKeepAlive"
  static let defaultValue = KeepAlive.oneMinute

  /// The setting stored under `key`, or the default if none is stored.
  static func stored(forKey key: String) -> KeepAlive {
    UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var id: Self { self }

  /// How long to stay ready after a dictation, or `nil` for Never and Always, which don't use a timer.
  var timeout: Duration? {
    switch self {
    case .never, .always: nil
    case .oneMinute: .seconds(60)
    case .fiveMinutes: .seconds(5 * 60)
    case .tenMinutes: .seconds(10 * 60)
    case .fifteenMinutes: .seconds(15 * 60)
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .never: "Never"
    case .oneMinute: "1 Minute"
    case .fiveMinutes: "5 Minutes"
    case .tenMinutes: "10 Minutes"
    case .fifteenMinutes: "15 Minutes"
    case .always: "Always"
    }
  }
}

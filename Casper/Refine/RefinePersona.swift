import Foundation

/// The style transcripts are refined in, each with its own prompt in `RefinePrompt`.
enum RefinePersona: String, CaseIterable, Identifiable, Sendable {
  /// Fixes grammar and punctuation into polished writing.
  case formal
  /// Writes like a text message: keeps slang, shortens common words and phrases, and leaves out most punctuation.
  case casual

  /// The `UserDefaults` key the persona is stored under.
  ///
  /// The setting is experimental, so the casual persona can be tried out without replacing the formal one.
  static let storageKey = "refinePersona"
  static let defaultValue = RefinePersona.formal

  /// The stored persona, or the default if none is stored.
  static var stored: RefinePersona {
    UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? defaultValue
  }

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .formal: "Formal"
    case .casual: "Casual"
    }
  }

  /// What refining does with this persona, shown under the Refine Persona setting.
  var explanation: LocalizedStringResource {
    switch self {
    case .formal: "Fix grammar and punctuation into polished writing."
    case .casual: "Write like a text message, keeping slang and shortening common words and phrases."
    }
  }
}

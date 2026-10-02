import Foundation

/// A style transcripts are refined in: the instructions the language model follows, and how Settings shows them.
///
/// Casper comes with built-in personas, whose prompts can't be edited but can be duplicated, and the user can add their
/// own.
struct RefinePersona: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var name: String
  /// What refining does with this persona, shown under its name in Settings.
  var summary: String
  /// The SF Symbol shown beside the persona's name.
  var systemImage: String
  /// The system prompt, the whole prompt besides the transcript, so the model reads it once per persona.
  ///
  /// A built-in persona sends its own prompt instead, and these are the instructions its duplicates start with.
  var instructions: String

  /// The `UserDefaults` key the chosen persona's ID is stored under.
  static let storageKey = "refinePersona"

  /// The most characters a name can have, which keeps it on one line in the Persona menu.
  static let nameLimit = 40
  /// The most characters a summary can have, about two lines under the persona's name in Settings.
  static let summaryLimit = 120
  /// The most words instructions can have.
  ///
  /// Words rather than tokens, because the token count depends on the language model and needs one installed. The
  /// casual persona, the longest built-in one, uses about half of it, and the model keeps every word it has read in
  /// memory.
  static let instructionWordLimit = 10_000

  static let formal = RefinePersona(
    id: RefinePrompt.BuiltIn.formal.rawValue,
    name: "Formal",
    summary: "Fix grammar and punctuation into polished writing.",
    systemImage: "briefcase",
    instructions: RefinePrompt.instructions(for: .formal)
  )

  static let casual = RefinePersona(
    id: RefinePrompt.BuiltIn.casual.rawValue,
    name: "Casual",
    summary: "Write like a text message, keeping slang and shortening common words and phrases.",
    systemImage: "bubble.left.and.bubble.right",
    instructions: RefinePrompt.instructions(for: .casual)
  )

  static let builtIns = [formal, casual]

  var isBuiltIn: Bool { RefinePrompt.BuiltIn(rawValue: id) != nil }

  /// The number of words in a text, found the way text editing finds them, so languages written without spaces count
  /// each word too.
  static func wordCount(of text: String) -> Int {
    var count = 0
    text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
      count += 1
    }
    return count
  }
}

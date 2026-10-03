import Foundation

/// A word the speech model should be able to write, such as a name, a brand or jargon, and the ways it gets it wrong.
struct DictionaryWord: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  /// The word as it should appear in transcripts, which can be several words, such as "Hugging Face".
  var text: String
  /// How the speech model writes the word when it gets it wrong, such as "Neve" for "Niamh".
  ///
  /// Each spelling can be several words, such as "tail scale" for "Tailscale".
  var soundsLike: [String]

  init(id: UUID = UUID(), text: String, soundsLike: [String] = []) {
    self.id = id
    self.text = text
    self.soundsLike = soundsLike
  }
}

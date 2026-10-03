import Foundation
import OSLog
import Observation

/// The user's dictionary: words the speech model should be able to write, kept across launches in alphabetical order.
@MainActor
@Observable
final class DictionaryStore {
  private(set) var words: [DictionaryWord]

  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let defaults: UserDefaults

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "DictionaryStore")

  static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "Casper/Dictionary.json")
  /// The `UserDefaults` key for whether dictations use the dictionary.
  static let enabledStorageKey = "dictionaryEnabled"

  init(fileURL: URL = defaultFileURL, defaults: UserDefaults = .standard) {
    self.fileURL = fileURL
    self.defaults = defaults
    words = Self.load(from: fileURL).sorted(by: Self.alphabetically)
  }

  /// Whether dictations use the dictionary, which the Dictionary page's switch turns on and off.
  var isEnabled: Bool { defaults.object(forKey: Self.enabledStorageKey) as? Bool ?? true }

  /// The words a dictation uses: all of them, or none while the dictionary is turned off.
  var wordsForDictation: [DictionaryWord] { isEnabled ? words : [] }

  /// Whether a word other than the one with the given ID is spelled this way, ignoring case and surrounding spaces.
  func isTaken(_ text: String, exceptBy id: DictionaryWord.ID?) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return words.contains { word in
      word.id != id && word.text.compare(text, options: .caseInsensitive) == .orderedSame
    }
  }

  /// Adds a word, or replaces the one with its ID, with its spelling and Sounds Like spellings tidied.
  ///
  /// A word that's empty, or spelled like another word in the dictionary, isn't saved.
  func save(_ word: DictionaryWord) {
    var word = word
    word.text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !word.text.isEmpty, !isTaken(word.text, exceptBy: word.id) else { return }
    word.soundsLike = Self.tidied(word.soundsLike, for: word.text)
    if let index = words.firstIndex(where: { $0.id == word.id }) {
      words[index] = word
    } else {
      words.append(word)
    }
    words.sort(by: Self.alphabetically)
    persist()
  }

  func delete(_ ids: Set<DictionaryWord.ID>) {
    words.removeAll { ids.contains($0.id) }
    persist()
  }

  /// Sounds Like spellings with surrounding spaces trimmed and runs of spaces between words made one, leaving out
  /// empty ones, repeats regardless of case, and ones spelled exactly like the word, which would replace it with
  /// itself.
  private static func tidied(_ spellings: [String], for text: String) -> [String] {
    var tidied: [String] = []
    for spelling in spellings {
      let spelling = spelling.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      let isRepeat = tidied.contains { $0.compare(spelling, options: .caseInsensitive) == .orderedSame }
      guard !spelling.isEmpty, spelling != text, !isRepeat else { continue }
      tidied.append(spelling)
    }
    return tidied
  }

  private static func alphabetically(_ first: DictionaryWord, _ second: DictionaryWord) -> Bool {
    first.text.localizedStandardCompare(second.text) == .orderedAscending
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(words).write(to: fileURL, options: .atomic)
    } catch {
      Self.logger.error("Couldn't save the dictionary: \(error)")
    }
  }

  private static func load(from fileURL: URL) -> [DictionaryWord] {
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
    do {
      return try JSONDecoder().decode([DictionaryWord].self, from: Data(contentsOf: fileURL))
    } catch {
      logger.error("Couldn't read the dictionary, so it starts empty: \(error)")
      return []
    }
  }
}

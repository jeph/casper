import Foundation

/// Turns a refined dictation into a text message: common words and phrases become their texting short forms, commas go
/// except inside numbers, and so does the period at the very end.
///
/// The casual persona does this in code instead of asking the language model, so it happens the same way every time
/// and the model only has to clean up the speech. Short forms that depend on meaning, like "gonna" only before a verb,
/// stay with the model.
enum CasualStyle {
  /// Words and phrases with their short forms, as lowercase words with straight apostrophes, matched as whole words.
  ///
  /// "You'll" and "you've" are words of their own, so they stay. "Not gonna lie" and "gotta go" are there because the
  /// model writes "gonna" and "gotta" before code sees the text.
  private static let shortForms: [(words: [String], shortForm: String)] = [
    ("you", "u"),
    ("your", "ur"),
    ("you're", "ur"),
    ("okay", "ok"),
    ("please", "pls"),
    ("though", "tho"),
    ("want to", "wanna"),
    ("by the way", "btw"),
    ("let me know", "lmk"),
    ("to be honest", "tbh"),
    ("in my opinion", "imo"),
    ("never mind", "nvm"),
    ("right now", "rn"),
    ("for real", "fr"),
    ("my bad", "mb"),
    ("oh my god", "omg"),
    ("not going to lie", "ngl"),
    ("not gonna lie", "ngl"),
    ("on my way", "omw"),
    ("talk to you later", "ttyl"),
    ("got to go", "gtg"),
    ("gotta go", "gtg"),
    ("be right back", "brb"),
    ("hit me up", "hmu"),
    ("what the fuck", "wtf"),
    ("motherfucker", "mf"),
  ]
  .map { (words: $0.0.split(separator: " ").map(String.init), shortForm: $0.1) }
  // Longest first, so a phrase wins over a shorter one it starts with.
  .sorted { $0.words.count > $1.words.count }

  /// Marks that can come before a word without making it part of something else, like a file name or a URL.
  private static let opening: Set<Character> = ["\"", "'", "“", "‘", "(", "[", "{"]
  /// Marks that can come after a word without making it part of something else.
  private static let closing: Set<Character> = [".", ",", "!", "?", ";", ":", "\"", "'", "”", "’", ")", "]", "}", "…"]

  /// Styles a whole dictation.
  ///
  /// Run it once on the finished text, never on a piece of it, since each piece's end would lose its period.
  static func apply(to text: String) -> String {
    withoutFinalPeriod(withoutCommas(shortened(text)))
  }

  /// A run of text between spaces, split into the word and the marks around it.
  private struct Chunk {
    let leading: Substring
    let word: Substring
    let trailing: Substring

    init(_ text: Substring) {
      leading = text.prefix { CasualStyle.opening.contains($0) }
      let rest = text.dropFirst(leading.count)
      let trailingCount = rest.reversed().prefix { CasualStyle.closing.contains($0) }.count
      word = rest.dropLast(trailingCount)
      trailing = rest.suffix(trailingCount)
    }

    var key: String { word.lowercased().replacing("’", with: "'") }
  }

  /// Replaces each whole word or phrase that has a short form, keeping a capital first letter, or all capitals.
  ///
  /// A phrase only matches words on one line, with only spaces between them, so "by the way" matches in "By the way,
  /// I" but not in "by the, way" or "by the—way".
  private static func shortened(_ text: String) -> String {
    let runs = runs(of: text)
    var result = ""
    var index = 0
    while index < runs.count {
      guard !runs[index].isSeparator, let (shortForm, count) = shortForm(at: index, in: runs) else {
        result += runs[index].text
        index += 1
        continue
      }
      result += shortForm
      index += 2 * count - 1
    }
    return result
  }

  /// The text split into alternating runs of separators and of everything else.
  ///
  /// Spaces and dashes separate words, as in "You—please"; hyphens don't, so "your-notes.txt" stays one run.
  private static func runs(of text: String) -> [(text: Substring, isSeparator: Bool)] {
    let isSeparator = { (character: Character) in character.isWhitespace || character == "—" || character == "–" }
    var runs: [(text: Substring, isSeparator: Bool)] = []
    var start = text.startIndex
    for index in text.indices where index > start && isSeparator(text[index]) != isSeparator(text[start]) {
      runs.append((text[start..<index], isSeparator(text[start])))
      start = index
    }
    if start < text.endIndex {
      runs.append((text[start...], isSeparator(text[start])))
    }
    return runs
  }

  /// The short form for the words starting at `index`, with the marks around them, and how many words it replaces.
  private static func shortForm(
    at index: Int,
    in runs: [(text: Substring, isSeparator: Bool)]
  ) -> (String, Int)? {
    for (words, shortForm) in shortForms {
      let end = index + 2 * (words.count - 1)
      guard end < runs.count else { continue }
      let gaps = stride(from: index + 1, to: end, by: 2).map { runs[$0].text }
      guard gaps.allSatisfy({ $0.allSatisfy { $0.isWhitespace && !$0.isNewline } }) else { continue }
      let chunks = stride(from: index, through: end, by: 2).map { Chunk(runs[$0].text) }
      let marksOnlyOutside = chunks.indices.allSatisfy { position in
        (position == 0 || chunks[position].leading.isEmpty)
          && (position == chunks.count - 1 || chunks[position].trailing.isEmpty)
      }
      guard marksOnlyOutside, chunks.map(\.key) == words else { continue }
      let cased = cased(shortForm, like: chunks.map(\.word))
      return (chunks[0].leading + cased + chunks[chunks.count - 1].trailing, words.count)
    }
    return nil
  }

  private static func cased(_ shortForm: String, like words: [Substring]) -> String {
    let letters = words.joined().filter(\.isLetter)
    if letters.count > 1, letters.allSatisfy(\.isUppercase) {
      return shortForm.uppercased()
    }
    guard let first = words.first?.first, first.isUppercase else { return shortForm }
    return shortForm.prefix(1).uppercased() + shortForm.dropFirst()
  }

  /// Drops every comma except one between digits, as in $1,240.
  private static func withoutCommas(_ text: String) -> String {
    let characters = Array(text)
    var result = ""
    for (index, character) in characters.enumerated() {
      let isInNumber =
        index > 0 && index < characters.count - 1 && characters[index - 1].isNumber
        && characters[index + 1].isNumber
      if character == ",", !isInNumber { continue }
      result.append(character)
    }
    return result
  }

  /// Drops the period at the very end, but not an ellipsis, a question mark, or an exclamation mark.
  private static func withoutFinalPeriod(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return trimmed }
    return String(trimmed.dropLast())
  }
}

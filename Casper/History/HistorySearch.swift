import Foundation

/// How a search typed on the History page matches dictations: every word typed has to start a word in the dictation,
/// ignoring case and accents, so "contr" finds "Contract" but not "uncontrolled".
enum HistorySearch {
  /// The SQLite full-text query for what the user typed, or `nil` if there's nothing to search for.
  ///
  /// Each word is quoted, so characters with a meaning in SQLite's query syntax are searched for as text, and marked
  /// as a prefix.
  static func matchExpression(for query: String) -> String? {
    let words = words(in: query)
    guard !words.isEmpty else { return nil }
    return words.map { "\"\($0.replacing("\"", with: "\"\""))\"*" }.joined(separator: " ")
  }

  /// The parts of `text` that the words typed match, for highlighting.
  static func matches(of query: String, in text: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    for word in words(in: query) {
      var searchStart = text.startIndex
      while let range = text.range(
        of: word,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchStart..<text.endIndex
      ) {
        if range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)]) {
          ranges.append(range)
        }
        searchStart = range.upperBound
      }
    }
    return ranges
  }

  /// The words typed, leaving out any without a letter or number, which the full-text index can't search for.
  private static func words(in query: String) -> [Substring] {
    query.split { $0.isWhitespace }.filter { $0.contains(where: isWordCharacter) }
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }
}

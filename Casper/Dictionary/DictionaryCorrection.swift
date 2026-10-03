import Foundation

/// Puts dictionary words into a transcript in place of text the speech model wrote.
///
/// Every model's transcript goes through `swapSoundsLike(in:dictionary:)`. Transcribers whose library finds
/// replacements of its own apply them with `replace(_:in:)`, so all replacements follow the same rules.
enum DictionaryCorrection {
  /// A dictionary word to put in place of a range of a transcript.
  struct Replacement {
    let range: Range<String.Index>
    let word: String
  }

  /// Replaces every exact occurrence of a word's Sounds Like spellings with the word, ignoring case.
  ///
  /// A spelling only matches whole words: "Jeff" matches in "Jeff's" but not in "Jeffrey". Any run of spaces between a
  /// spelling's words matches any run of spaces in the transcript. Every spelling is matched against the transcript as
  /// the speech model wrote it, so a word put in by one replacement is never replaced again by another.
  static func swapSoundsLike(in text: String, dictionary: [DictionaryWord]) -> String {
    let spellings = SpellingIndex(dictionary)
    guard !spellings.isEmpty else { return text }
    var replacements: [Replacement] = []
    var previous: Character?
    for start in text.indices {
      defer { previous = text[start] }
      // A match starts a word, or at a character such as "." that isn't part of one.
      if let previous, isWordCharacter(previous) { continue }
      for candidate in spellings.candidates(at: start, in: text) {
        if let end = candidate.matchEnd(at: start, in: text) {
          replacements.append(Replacement(range: start..<end, word: candidate.word))
        }
      }
    }
    return replace(replacements, in: text)
  }

  /// Puts each replacement's word in place of its range, capitalized like the text it replaces.
  ///
  /// Where ranges overlap, the longest wins, then the one that starts first.
  static func replace(_ replacements: [Replacement], in text: String) -> String {
    let longestFirst = replacements.sorted { first, second in
      let firstLength = text.distance(from: first.range.lowerBound, to: first.range.upperBound)
      let secondLength = text.distance(from: second.range.lowerBound, to: second.range.upperBound)
      guard firstLength == secondLength else { return firstLength > secondLength }
      return first.range.lowerBound < second.range.lowerBound
    }
    var kept: [Replacement] = []
    for replacement in longestFirst where !kept.contains(where: { $0.range.overlaps(replacement.range) }) {
      kept.append(replacement)
    }
    var corrected = text
    // From the end, so the ranges still to replace stay where they were.
    for replacement in kept.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
      corrected.replaceSubrange(replacement.range, with: matchingCase(of: text[replacement.range], replacement.word))
    }
    return corrected
  }

  /// The dictionary word, capitalized the way the speech model wrote the text it replaces.
  ///
  /// A capital first letter, as at the start of a sentence, carries over to a word the dictionary spells all
  /// lowercase. Otherwise the dictionary's spelling wins, so "iPhone" and "MLX" keep their capitals and "jeff" becomes
  /// "Jeph".
  static func matchingCase(of written: Substring, _ word: String) -> String {
    guard let first = written.first(where: \.isLetter), first.isUppercase, word == word.lowercased() else {
      return word
    }
    return word.prefix(1).uppercased() + word.dropFirst()
  }

  static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }
}

/// The Sounds Like spellings of a dictionary, found by how they start, so a transcript is checked against only the
/// spellings that could match at each point rather than all of them.
private struct SpellingIndex {
  struct Spelling {
    /// The spelling's words, which the transcript must have with spaces between them.
    let parts: [Substring]
    let word: String

    /// Where a match of the spelling that starts at `start` ends, or `nil` if it doesn't match there.
    func matchEnd(at start: String.Index, in text: String) -> String.Index? {
      var position = start
      for (index, part) in parts.enumerated() {
        if index > 0 {
          let spaces = text[position...].prefix(while: \.isWhitespace)
          guard !spaces.isEmpty else { return nil }
          position = spaces.endIndex
        }
        guard let match = text.range(of: part, options: [.caseInsensitive, .anchored], range: position..<text.endIndex)
        else { return nil }
        position = match.upperBound
      }
      // A match ends a word, so "Jeff" doesn't match the start of "Jeffrey".
      if position < text.endIndex, DictionaryCorrection.isWordCharacter(text[position]) { return nil }
      return position
    }
  }

  private var spellings: [String: [Spelling]] = [:]

  init(_ dictionary: [DictionaryWord]) {
    for word in dictionary {
      for spelling in word.soundsLike {
        let parts = spelling.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { continue }
        spellings[Self.key(of: first), default: []].append(Spelling(parts: parts, word: word.text))
      }
    }
  }

  var isEmpty: Bool { spellings.isEmpty }

  func candidates(at start: String.Index, in text: String) -> [Spelling] {
    spellings[Self.key(of: text[start...])] ?? []
  }

  /// The lowercased word that text starts with, or its first character if that isn't part of a word, such as the "."
  /// of ".NET".
  private static func key(of text: Substring) -> String {
    let word = text.prefix(while: DictionaryCorrection.isWordCharacter)
    return (word.isEmpty ? text.prefix(1) : word).lowercased()
  }
}

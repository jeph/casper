import Foundation

/// Words the user typed over words Casper typed, which may belong in the dictionary.
struct Correction: Equatable, Sendable {
  /// What Casper typed, without punctuation at either end, such as "tail scale".
  let original: String
  /// What the user typed in its place, such as "Tailscale".
  let replacement: String
}

/// Finds the words a user corrected in text Casper typed, by comparing it with what the text field holds afterward.
///
/// Adapted from OpenWhispr's correction learner (https://github.com/OpenWhispr/openwhispr,
/// `src/utils/correctionLearner.js` at 85b0115): finding the typed text in the field, the word-by-word comparison, and
/// the filters, with the same common words and the same 0.65 limit on how much of a word's spelling may change. Unlike
/// OpenWhispr, a run of changed words is one correction, so "tail scale" corrected to "Tailscale" is found as written,
/// and a correction with a common word anywhere in it is left out. OpenWhispr's license:
///
/// MIT License
///
/// Copyright (c) 2024 OpenWhispr Team
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
/// documentation files (the "Software"), to deal in the Software without restriction, including without limitation
/// the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
/// permit persons to whom the Software is furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all copies or substantial portions of
/// the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
/// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
/// OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
/// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
enum CorrectionFinder {
  /// Everyday words, which are never corrections.
  ///
  /// Swapping one for another, such as "why" for "what", is an edit to what was said, not a word the speech model got
  /// wrong. Words under three letters are never corrections, so none are listed.
  private static let commonWords = Set(
    """
    the and for not with you this but his from they say her she will one all would there their what out about who \
    get which when make can like time just him know take into year your good some could them see other than then now \
    look only come over think also back after use two how our work first well way even new want because any these \
    give day most are was were been has had did does said went made got came took saw knew thought where why here \
    very much many still too again off down never every own same another both each few more less last next while \
    before through under between should might must being have that its yes okay
    """
    .split(separator: " ").map(String.init)
  )

  /// The most a correction's spelling may differ from the words it replaces, as a share of the longer one's letters.
  ///
  /// A mishearing fixed by the user, such as "Shunade" for "Sinead" (4 of 7), stays under it, and an unrelated word
  /// put in its place doesn't.
  private static let maximumChangedShare = 0.65

  /// Fields with more words than this aren't searched for the typed text, which would take too long.
  private static let maximumFieldWords = 20_000

  /// The most word pairs two texts are compared in, which takes 8 bytes each, so about 32 MB: a little over 2,000 words
  /// typed in one paste.
  static let maximumComparedPairs = 4_000_000

  /// The corrections in `field` to text Casper typed as `typed`, leaving out rewrites, common words, changes only to
  /// capitals, and words spelled too differently to be the same word misheard.
  ///
  /// A field that no longer holds most of the typed text, such as one the app reused for something else, has none.
  static func corrections(typed: String, field: String) -> [Correction] {
    // Text that's still in the field as typed wasn't corrected.
    guard !typed.isEmpty, !field.contains(typed) else { return [] }
    let typedWords = words(in: typed)
    let fieldWords = words(in: field)
    guard !typedWords.isEmpty, fieldWords.count <= maximumFieldWords else { return [] }
    let editedWords =
      field.count <= typed.count * 3 / 2 ? fieldWords : region(matching: typedWords, in: fieldWords)
    guard let editedWords, typedWords.count * editedWords.count <= maximumComparedPairs else { return [] }
    let runs = changedRuns(from: typedWords, to: editedWords)
    // More than half the words changed is a rewrite, not corrections.
    guard runs.reduce(0, { $0 + $1.original.count }) * 2 <= typedWords.count else { return [] }

    var corrections: [Correction] = []
    for run in runs {
      // Several words changed one for one are corrected one by one; otherwise the run is one correction.
      let pairs =
        run.original.count == run.replacement.count && run.original.count > 1
        ? zip(run.original, run.replacement).map { ([$0], [$1]) }
        : [(run.original, run.replacement)]
      for (original, replacement) in pairs {
        let correction = Correction(
          original: original.joined(separator: " "),
          replacement: replacement.joined(separator: " ")
        )
        let isRepeat = corrections.contains {
          $0.replacement.compare(correction.replacement, options: .caseInsensitive) == .orderedSame
        }
        guard !isRepeat, isPlausible(correction, replacementWords: replacement) else { continue }
        corrections.append(correction)
      }
    }
    return corrections
  }

  /// The text's words, without punctuation at either end.
  static func words(in text: String) -> [String] {
    let edges = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted
    return text.split(whereSeparator: \.isWhitespace)
      .map { $0.trimmingCharacters(in: edges) }
      .filter { !$0.isEmpty }
  }

  /// Index pairs of the words two lists have in common, ignoring case, in order: their longest common subsequence.
  static func matches(_ first: [String], _ second: [String]) -> [(first: Int, second: Int)] {
    let first = first.map { $0.lowercased() }
    let second = second.map { $0.lowercased() }
    // `lengths[i][j]` is the longest common subsequence of `first[i...]` and `second[j...]`.
    var lengths = Array(repeating: Array(repeating: 0, count: second.count + 1), count: first.count + 1)
    for i in first.indices.reversed() {
      for j in second.indices.reversed() {
        lengths[i][j] =
          first[i] == second[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
      }
    }
    var pairs: [(first: Int, second: Int)] = []
    var i = 0
    var j = 0
    while i < first.count, j < second.count {
      if first[i] == second[j] {
        pairs.append((i, j))
        i += 1
        j += 1
      } else if lengths[i + 1][j] >= lengths[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    return pairs
  }

  /// The stretch of the field's words that best matches the typed words, for text typed into a field that already held
  /// other text, or `nil` if none matches at least 30% of the words.
  private static func region(matching typedWords: [String], in fieldWords: [String]) -> [String]? {
    let size = typedWords.count
    guard fieldWords.count > size else { return fieldWords }
    let typed = typedWords.map { $0.lowercased() }
    let field = fieldWords.map { $0.lowercased() }
    var bestStart = 0
    var bestMatches = -1
    for start in 0...(field.count - size) {
      let matches = (0..<size).count(where: { field[start + $0] == typed[$0] })
      if matches > bestMatches {
        bestMatches = matches
        bestStart = start
      }
    }
    guard bestMatches * 10 >= size * 3 else { return nil }
    return Array(fieldWords[bestStart..<bestStart + size])
  }

  /// Each stretch of words between the words both lists share, where words were both taken out and put in.
  private static func changedRuns(
    from original: [String],
    to edited: [String]
  ) -> [(original: [String], replacement: [String])] {
    let anchors = matches(original, edited) + [(original.count, edited.count)]
    var runs: [(original: [String], replacement: [String])] = []
    var originalStart = 0
    var editedStart = 0
    for anchor in anchors {
      let removed = Array(original[originalStart..<anchor.first])
      let added = Array(edited[editedStart..<anchor.second])
      if !removed.isEmpty, !added.isEmpty {
        runs.append((removed, added))
      }
      originalStart = anchor.first + 1
      editedStart = anchor.second + 1
    }
    return runs
  }

  private static func isPlausible(_ correction: Correction, replacementWords: [String]) -> Bool {
    let original = correction.original.lowercased()
    let replacement = correction.replacement.lowercased()
    guard replacement.count >= 3, replacement != original else { return false }
    guard !replacementWords.contains(where: { commonWords.contains($0.lowercased()) }) else { return false }
    // Compared without spaces, so words joined or split, like "tail scale" and "Tailscale", count as the same letters.
    let originalLetters = Array(original.filter { !$0.isWhitespace })
    let replacementLetters = Array(replacement.filter { !$0.isWhitespace })
    let distance = editDistance(originalLetters, replacementLetters)
    return Double(distance) <= maximumChangedShare * Double(max(originalLetters.count, replacementLetters.count))
  }

  /// The fewest single-character insertions, deletions and substitutions that turn one spelling into the other.
  private static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
    var previous = Array(0...second.count)
    for (i, firstCharacter) in first.enumerated() {
      var current = [i + 1] + Array(repeating: 0, count: second.count)
      for (j, secondCharacter) in second.enumerated() {
        current[j + 1] =
          firstCharacter == secondCharacter
          ? previous[j]
          : 1 + min(previous[j], previous[j + 1], current[j])
      }
      previous = current
    }
    return previous[second.count]
  }
}

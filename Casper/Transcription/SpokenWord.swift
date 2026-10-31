import Foundation

/// A word a speech model heard, and when it starts, in seconds from the start of the recording.
struct SpokenWord: Sendable, Equatable {
  let text: String
  let start: TimeInterval

  /// How far apart two transcriptions of the same audio can place a word, in seconds.
  ///
  /// Parakeet's timing for a word after a pause can come early by a few frames, and by different amounts depending on
  /// the audio around it.
  static let timingTolerance = 0.35

  /// The index in `heard` of the first word after `previous`, the last words kept from a transcription of the audio
  /// before `heard` overlaps it, or `nil` if `heard` doesn't repeat the last of them.
  ///
  /// The overlap is the longest run of `previous`'s last words that `heard` repeats, the same words ignoring case and
  /// punctuation at about the same time. Matching whole runs, not single words, keeps a word said twice in a row, once
  /// on each side of a cut, from being taken for a copy of the first: "like that." repeats as a run only where it
  /// was said, so the "That" after it is new. Among equally long runs, the one closest in time wins.
  static func firstNew(in heard: [SpokenWord], after previous: [SpokenWord]) -> Int? {
    let heardTexts = heard.map { normalized($0.text) }
    let previousTexts = previous.map { normalized($0.text) }
    func matches(_ heardIndex: Int, _ previousIndex: Int) -> Bool {
      abs(heard[heardIndex].start - previous[previousIndex].start) <= timingTolerance
        && heardTexts[heardIndex] == previousTexts[previousIndex]
    }
    for count in stride(from: min(heard.count, previous.count), through: 1, by: -1) {
      let previousStart = previous.count - count
      let runStarts = (0...(heard.count - count))
        .filter { start in (0..<count).allSatisfy { matches(start + $0, previousStart + $0) } }
      let distance = { (start: Int) in
        (0..<count).reduce(0.0) { $0 + abs(heard[start + $1].start - previous[previousStart + $1].start) }
      }
      if let closest = runStarts.min(by: { distance($0) < distance($1) }) {
        return closest + count
      }
    }
    return nil
  }

  private static func normalized(_ word: String) -> String {
    String(word.lowercased().filter { $0.isLetter || $0.isNumber })
  }
}

/// Where prompt lookup decoding takes its guesses: the transcript, followed by the tokens written so far.
///
/// The rest of the prompt isn't searched: its examples matched the latest tokens more recently than the transcript did
/// and led guesses astray, and the end of the last example's answer was always the first guess.
struct TranscriptLookup {
  /// The longest run of latest tokens looked up, since longer matches make better guesses.
  private static let longestMatch = 3

  /// The transcript followed by the tokens written so far.
  private var searched: [Int]
  /// How many tokens of `searched` are the transcript's.
  private let transcriptLength: Int

  init(transcript: [Int]) {
    searched = transcript
    transcriptLength = transcript.count
  }

  mutating func append(written tokens: some Sequence<Int>) {
    searched += tokens
  }

  /// Up to `count` tokens that followed the latest written tokens where they last appeared before, trying the longest
  /// match first, or the start of the transcript before anything is written.
  func guess(count: Int) -> ArraySlice<Int> {
    let writtenCount = searched.count - transcriptLength
    guard writtenCount > 0 else { return searched.prefix(count) }
    for length in stride(from: min(Self.longestMatch, writtenCount), through: 1, by: -1) {
      let latest = searched.suffix(length)
      for start in stride(from: searched.count - length - 1, through: 0, by: -1)
      where searched[start..<(start + length)].elementsEqual(latest) {
        let next = start + length
        return searched[next..<min(next + count, searched.count)]
      }
    }
    return []
  }
}

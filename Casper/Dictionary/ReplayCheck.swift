/// Decides whether a correction is a word the speech model misheard, from a replay: the same recording transcribed
/// again with the correction in the dictionary.
///
/// A misheard word comes out as the user's spelling once the model knows it. An edit to what was said, such as
/// "Thursday" for a spoken "Friday", doesn't, since the audio still says "Friday". Only the places where the transcript
/// has the corrected words are judged, so a replay that writes the word somewhere else doesn't count.
///
/// A correction doesn't record which of several places with the same words the user edited, so the replay has to
/// write the replacement at every one of them. That rejects "Sam" changed to "Pam" in "Call Sam then email Sam" even
/// if the replay happens to write "Pam" for the other "Sam".
enum ReplayCheck {
  /// The index of the one transcript with the words the user corrected, which is the dictation to replay, or `nil` if
  /// none has them or several do, since it's unknown which of those the user edited.
  static func transcript(containing correction: Correction, among transcripts: [String]) -> Int? {
    let containing = transcripts.indices.filter {
      !occurrences(of: correction.original, in: CorrectionFinder.words(in: transcripts[$0])).isEmpty
    }
    return containing.count == 1 ? containing.first : nil
  }

  /// Whether the replay wrote the correction's replacement at every place the transcript has the words it replaces.
  ///
  /// Transcripts too long to compare within `CorrectionFinder.maximumComparedPairs` never support a correction.
  static func replay(_ replay: String, of transcript: String, supports correction: Correction) -> Bool {
    let transcriptWords = CorrectionFinder.words(in: transcript)
    let replayWords = CorrectionFinder.words(in: replay)
    guard transcriptWords.count * replayWords.count <= CorrectionFinder.maximumComparedPairs else { return false }
    let replacement = CorrectionFinder.words(in: correction.replacement).map { $0.lowercased() }
    let matches = CorrectionFinder.matches(transcriptWords, replayWords)
    let ranges = occurrences(of: correction.original, in: transcriptWords)
    return !ranges.isEmpty
      && ranges.allSatisfy { range in
        // The replay's words between the shared words on either side of the corrected ones.
        let start = matches.last { $0.first < range.lowerBound }.map { $0.second + 1 } ?? 0
        let end = matches.first { $0.first >= range.upperBound }?.second ?? replayWords.count
        return start <= end && replayWords[start..<end].map { $0.lowercased() } == replacement
      }
  }

  /// Every place the words appear in order, ignoring case.
  private static func occurrences(of text: String, in words: [String]) -> [Range<Int>] {
    let target = CorrectionFinder.words(in: text).map { $0.lowercased() }
    guard !target.isEmpty, words.count >= target.count else { return [] }
    let lowercased = words.map { $0.lowercased() }
    return (0...(words.count - target.count))
      .compactMap { start in
        let range = start..<start + target.count
        return Array(lowercased[range]) == target ? range : nil
      }
  }
}

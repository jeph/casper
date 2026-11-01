import Testing

struct TranscriptLookupTests {
  /// The first guess is how the transcript starts, which a refined transcript most often starts the same way.
  @Test func guessesTheTranscriptsStartBeforeAnythingIsWritten() {
    #expect(TranscriptLookup(transcript: [1, 2, 3, 4]).guess(count: 2) == [1, 2])
    #expect(TranscriptLookup(transcript: [1]).guess(count: 2) == [1])
  }

  @Test func guessesWhatFollowedTheLatestTokensInTheTranscript() {
    var lookup = TranscriptLookup(transcript: [10, 11, 12, 13, 14])
    lookup.append(written: [11, 12])
    #expect(lookup.guess(count: 2) == [13, 14])
  }

  /// "2" alone last appeared before 8, but "1 2" appeared before 9, and the longer match is the better guess.
  @Test func prefersTheLongestMatch() {
    var lookup = TranscriptLookup(transcript: [1, 2, 9, 9, 3, 2, 8, 8])
    lookup.append(written: [1, 2])
    #expect(lookup.guess(count: 2) == [9, 9])
  }

  @Test func prefersTheMostRecentMatch() {
    var lookup = TranscriptLookup(transcript: [4, 5, 6, 4, 7])
    lookup.append(written: [4])
    #expect(lookup.guess(count: 1) == [7])
  }

  /// Words the model wrote that the transcript doesn't have, like a figure for a spoken number, can repeat.
  @Test func findsMatchesInWhatWasWritten() {
    var lookup = TranscriptLookup(transcript: [1, 2])
    lookup.append(written: [50, 51, 52, 50])
    #expect(lookup.guess(count: 2) == [51, 52])
  }

  /// The latest tokens are only written ones: the transcript's end followed by the first written token, "7 8 1", last
  /// appeared before 5, but the model only wrote "1", which last appeared before 6.
  @Test func looksUpOnlyWrittenTokens() {
    var lookup = TranscriptLookup(transcript: [7, 8, 1, 5, 1, 6, 7, 8])
    lookup.append(written: [1])
    #expect(lookup.guess(count: 2) == [6, 7])
  }

  @Test func guessesNothingWithoutAMatch() {
    var lookup = TranscriptLookup(transcript: [1, 2, 3])
    lookup.append(written: [9])
    #expect(lookup.guess(count: 2).isEmpty)
  }

  @Test func stopsAtWhatWasWrittenLast() {
    var lookup = TranscriptLookup(transcript: [1, 2, 3])
    lookup.append(written: [2])
    #expect(lookup.guess(count: 5) == [3, 2])
  }

  @Test func guessesNothingWhenNoneAreWanted() {
    var lookup = TranscriptLookup(transcript: [1, 2, 3])
    #expect(lookup.guess(count: 0).isEmpty)
    lookup.append(written: [1])
    #expect(lookup.guess(count: 0).isEmpty)
  }
}

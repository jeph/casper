import Testing

struct SpokenWordTests {
  /// "that." ends the earlier segment and "That" starts the next sentence a quarter second later, close enough in time
  /// to pass for a copy of it on its own.
  @Test func keepsAWordSaidAgainRightAfterTheCut() {
    let previous = [Self.word("like", 9.4), Self.word("that.", 9.68)]
    let heard = [Self.word("like", 9.38), Self.word("that.", 9.64), Self.word("That", 9.88), Self.word("is", 10.1)]
    #expect(SpokenWord.firstNew(in: heard, after: previous) == 2)
  }

  /// With only one earlier word to go by, the copy closest in time to it is the repeat, even when it isn't the first.
  @Test func takesTheClosestCopyAsTheRepeat() {
    let previous = [Self.word("that", 9.9)]
    let heard = [Self.word("that", 9.64), Self.word("that", 9.88), Self.word("is", 10.1)]
    #expect(SpokenWord.firstNew(in: heard, after: previous) == 2)
  }

  /// The run "like that" places the repeat, though the second "that" is closer in time to the earlier "that".
  @Test func prefersTheLongestRunToTheClosestWord() {
    let previous = [Self.word("like", 9.4), Self.word("that", 9.8)]
    let heard = [Self.word("like", 9.38), Self.word("that", 9.55), Self.word("that", 9.82)]
    #expect(SpokenWord.firstNew(in: heard, after: previous) == 2)
  }

  @Test func matchesWordsIgnoringCaseAndPunctuation() {
    let previous = [Self.word("Friday.", 4.0)]
    let heard = [Self.word("friday,", 4.2), Self.word("then", 4.6)]
    #expect(SpokenWord.firstNew(in: heard, after: previous) == 1)
  }

  @Test func ignoresTheSameWordAtAnotherTime() {
    let previous = [Self.word("okay", 4.0)]
    let heard = [Self.word("okay", 5.0)]
    #expect(SpokenWord.firstNew(in: heard, after: previous) == nil)
  }

  @Test func findsNothingWithoutEarlierWords() {
    #expect(SpokenWord.firstNew(in: [Self.word("hello", 1.0)], after: []) == nil)
    #expect(SpokenWord.firstNew(in: [], after: [Self.word("hello", 1.0)]) == nil)
  }

  private static func word(_ text: String, _ start: Double) -> SpokenWord {
    SpokenWord(text: text, start: start)
  }
}

import Testing

struct LiveRefinementTests {
  /// The user may have paused in the middle of the newest sentence, so it waits for the next one.
  @Test func holdsBackTheNewestSentence() {
    var refinement = LiveRefinement(openWords: 25)
    refinement.append(transcript: "I want to go to the.")
    #expect(refinement.takeText() == nil)
    refinement.append(transcript: "Store and buy milk. Then home.")
    #expect(refinement.takeText() == "I want to go to the. Store and buy milk.")
  }

  /// Whole sentences are kept open from the end until they hold the fewest open words, including the one that
  /// reaches it.
  @Test func keepsWholeSentencesOpenUntilTheyHoldEnoughWords() {
    var refinement = LiveRefinement(openWords: 5)
    refinement.append(transcript: "One two three four five six. Seven eight nine. Ten eleven. Twelve.")
    #expect(refinement.takeText() == "One two three four five six. Seven eight nine. Ten eleven.")
    refinement.refined("One two three four five six. Seven eight nine. Ten eleven.")
    refinement.append(transcript: "Thirteen.")
    #expect(refinement.takeText() == "Seven eight nine. Ten eleven. Twelve.")
  }

  /// "No, Saturday" reaches back to the open sentence it corrects.
  @Test func givesTheOpenTextToTheNextRefine() {
    var refinement = LiveRefinement(openWords: 25)
    refinement.append(transcript: "Let's ship on Friday. No, sorry, Saturday. Thanks.")
    #expect(refinement.takeText() == "Let's ship on Friday. No, sorry, Saturday.")
    refinement.refined("Let's ship on Saturday.")
    #expect(refinement.takeLastText() == "Let's ship on Saturday. Thanks.")
    #expect(refinement.finished(lastRefined: "Let's ship on Saturday. Thanks.") == "Let's ship on Saturday. Thanks.")
  }

  /// A blank line for a new paragraph isn't a sentence, so it doesn't take the place of one that's kept open.
  @Test func doesNotCountBlankLinesAsSentences() {
    var refinement = LiveRefinement(openWords: 3)
    refinement.refined("First one here.\n\nSecond one here.")
    #expect(refinement.takeLastText() == "Second one here.")
    #expect(refinement.finished(lastRefined: "Second one here.") == "First one here.\n\nSecond one here.")
  }

  @Test func keepsAFragmentOpenWithoutCountingIt() {
    var refinement = LiveRefinement(openWords: 3)
    refinement.refined("Settled words here. Open words here. And then")
    #expect(refinement.takeLastText() == "Open words here. And then")
  }

  @Test func settlesEverythingWithoutOpenWords() {
    var refinement = LiveRefinement(openWords: 0)
    refinement.refined("First. Second.")
    refinement.append(transcript: "Third.")
    #expect(refinement.takeLastText() == "Third.")
    #expect(refinement.finished(lastRefined: "Third.") == "First. Second. Third.")
  }

  @Test func finishesWithNothingRefinedWhileRecording() {
    var refinement = LiveRefinement(openWords: 25)
    refinement.append(transcript: "Just one sentence.")
    #expect(refinement.takeLastText() == "Just one sentence.")
    #expect(refinement.finished(lastRefined: "") == "")
  }
}

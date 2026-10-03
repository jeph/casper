import Testing

struct CorrectionFinderTests {
  @Test(
    arguments: [
      // A misheard name, with the punctuation around it left out.
      ("Ask Shivan to move the meeting. ", "Ask Siobhan to move the meeting. ", [("Shivan", "Siobhan")]),
      // Words joined into one are one correction.
      ("Before the tail scale migration. ", "Before the Tailscale migration. ", [("tail scale", "Tailscale")]),
      ("Casper runs Quen 3 now. ", "Casper runs Qwen3 now. ", [("Quen 3", "Qwen3")]),
      // At either end of the text.
      ("Shivan, call me. ", "Siobhan, call me. ", [("Shivan", "Siobhan")]),
      ("Then call Shivan. ", "Then call Siobhan. ", [("Shivan", "Siobhan")]),
      // Several words changed one for one are separate corrections.
      ("Ask Shivan Murfy to call. ", "Ask Siobhan Murphy to call. ", [("Shivan", "Siobhan"), ("Murfy", "Murphy")]),
      (
        "Tell Shivan and Sirsha the news. ", "Tell Siobhan and Saoirse the news. ",
        [("Shivan", "Siobhan"), ("Sirsha", "Saoirse")]
      ),
      // The same correction twice is found once.
      ("Shivan said Shivan would come. ", "Siobhan said Siobhan would come. ", [("Shivan", "Siobhan")]),
    ]
  )
  func findsCorrections(typed: String, field: String, expected: [(String, String)]) {
    let corrections = CorrectionFinder.corrections(typed: typed, field: field)
    #expect(corrections == expected.map { Correction(original: $0, replacement: $1) })
  }

  @Test(
    arguments: [
      // Nothing was changed.
      ("Ask Shivon to move the meeting. ", "Ask Shivon to move the meeting. "),
      // An unrelated word put in place of another is a change of mind, not a mishearing.
      ("Ask Shivon to move the meeting. ", "Ask Shivon to move the call. "),
      // 5 of 7 letters changed is over the limit, even for a real name.
      ("Ask Shivon to move the meeting. ", "Ask Siobhan to move the meeting. "),
      // Swapping everyday words is an edit to what was said.
      ("Why is the build failing? ", "What is the build failing? "),
      // Only capitals changed.
      ("Ask siobhan to move the meeting. ", "Ask Siobhan to move the meeting. "),
      // Too short to be a word worth adding.
      ("Ask Ali to move the meeting. ", "Ask Al to move the meeting. "),
      // More than half the words changed is a rewrite.
      ("Ask Shivon to move it. ", "Siobhan could reschedule it. "),
      // Words only added or only removed aren't replacements.
      ("Ask Shivon to move the meeting. ", "Ask Shivon to move the weekly meeting. "),
      ("", "Anything"),
    ]
  )
  func ignoresEditsThatArentMishearings(typed: String, field: String) {
    #expect(CorrectionFinder.corrections(typed: typed, field: field).isEmpty)
  }

  @Test func findsTheTypedTextAmongTextAlreadyInTheField() {
    let before = "Hi team, a few updates from this morning about the release schedule and the open bugs. "
    let after = " Thanks, and let me know if anything here looks wrong to you before Friday's planning call."
    let corrections = CorrectionFinder.corrections(
      typed: "Ask Shivan to check the Unifly config. ",
      field: before + "Ask Siobhan to check the Unifly config. " + after
    )
    #expect(corrections == [Correction(original: "Shivan", replacement: "Siobhan")])
  }

  @Test func findsACorrectionInALongPasteInsideALargeField() {
    let filler = Array(repeating: "Lorem ipsum dolor sit amet.", count: 1_500).joined(separator: " ")
    let paste = Array(repeating: "The quarterly numbers look fine.", count: 150).joined(separator: " ")
    let corrections = CorrectionFinder.corrections(
      typed: paste + " Ask Shivan to check them. ",
      field: filler + " " + paste + " Ask Siobhan to check them. " + filler
    )
    #expect(corrections == [Correction(original: "Shivan", replacement: "Siobhan")])
  }

  @Test func aLargeFieldThatNoLongerHoldsThePasteHasNoCorrections() {
    let paste = (0..<1_000).map { "word\($0 % 500)" }.joined(separator: " ") + " "
    let field = (0..<20_000).map { "other\($0 % 500)" }.joined(separator: " ")
    #expect(CorrectionFinder.corrections(typed: paste, field: field).isEmpty)
  }
}

struct ReplayCheckTests {
  @Test func findsTheOneTranscriptWithTheCorrectedWords() {
    let siobhan = Correction(original: "Shivon", replacement: "Siobhan")
    let tailscale = Correction(original: "tail scale", replacement: "Tailscale")
    let transcripts = ["Before the tail scale migration.", "Ask shivon to move it.", "Then email Sam."]
    #expect(ReplayCheck.transcript(containing: siobhan, among: transcripts) == 1)
    #expect(ReplayCheck.transcript(containing: tailscale, among: transcripts) == 0)
    #expect(ReplayCheck.transcript(containing: siobhan, among: ["Ask Siobhan to move it."]) == nil)
    // Words in two dictations of one paste: it's unknown which the user edited.
    let sam = Correction(original: "Sam", replacement: "Pam")
    #expect(ReplayCheck.transcript(containing: sam, among: ["Call Sam.", "Then email Sam."]) == nil)
  }

  @Test(
    arguments: [
      // The replay wrote the user's spelling where the transcript had the misheard word.
      (
        "Ask Shivon to move the meeting.", "Ask Siobhan to move the meeting.",
        Correction(original: "Shivon", replacement: "Siobhan"), true
      ),
      (
        "Before the tail scale migration.", "Before the Tailscale migration.",
        Correction(original: "tail scale", replacement: "Tailscale"), true
      ),
      // The audio still says what was transcribed, so the edit changed what was said.
      (
        "Move the meeting to Friday.", "Move the meeting to Friday.",
        Correction(original: "Friday", replacement: "Thursday"), false
      ),
      // The replacement elsewhere in the replay doesn't count.
      ("Call Sam and Pam.", "Call Sam and Pam.", Correction(original: "Sam", replacement: "Pam"), false),
      // A replay that wrote something else in that spot doesn't support it either.
      (
        "Ask Shivon to move the meeting.", "Ask Sheva to move the meeting.",
        Correction(original: "Shivon", replacement: "Siobhan"), false
      ),
      // With the words in two places, the replay must write the replacement in both, since either may be the one the
      // user edited.
      (
        "Call Sam then email Sam.", "Call Sam then email Pam.", Correction(original: "Sam", replacement: "Pam"),
        false
      ),
      (
        "Shivan said Shivan would come.", "Siobhan said Siobhan would come.",
        Correction(original: "Shivan", replacement: "Siobhan"), true
      ),
    ]
  )
  func judgesTheReplayAtTheCorrectedSpot(transcript: String, replay: String, correction: Correction, supports: Bool) {
    #expect(ReplayCheck.replay(replay, of: transcript, supports: correction) == supports)
  }
}

import Testing

struct DictionaryCorrectionTests {
  private static let dictionary = [
    DictionaryWord(text: "Jeph", soundsLike: ["Jeff"]),
    DictionaryWord(text: "Tailscale", soundsLike: ["tail scale"]),
    // Its Sounds Like spelling is another word's replacement, which must not be replaced again.
    DictionaryWord(text: "Tailspin", soundsLike: ["Tailscale"]),
    DictionaryWord(text: "Niamh", soundsLike: ["Neve"]),
    DictionaryWord(text: "kubectl", soundsLike: ["cube control"]),
    DictionaryWord(text: "iPhone", soundsLike: ["eye phone"]),
    DictionaryWord(text: "MLX", soundsLike: ["M L X"]),
    DictionaryWord(text: "Scalewise", soundsLike: ["scale wise"]),
    DictionaryWord(text: "C++", soundsLike: ["C plus plus"]),
    DictionaryWord(text: ".NET", soundsLike: ["dot net"]),
  ]

  @Test(
    arguments: [
      ("Tell Jeff the build passed.", "Tell Jeph the build passed."),
      ("tell jeff later", "tell Jeph later"),
      ("Jeff's laptop, and Jeffrey's.", "Jeph's laptop, and Jeffrey's."),
      ("Before the tail scale migration.", "Before the Tailscale migration."),
      ("Tail  scale is down.", "Tailscale is down."),
      ("Tail\nscale is down.", "Tailscale is down."),
      ("Is Tailscale down?", "Is Tailspin down?"),
      ("Tail scale, not Tailscale.", "Tailscale, not Tailspin."),
      ("Lunch with Neve? Sure.", "Lunch with Niamh? Sure."),
      ("Run cube control apply.", "Run kubectl apply."),
      ("Cube control is installed.", "Kubectl is installed."),
      ("Buy an eye phone.", "Buy an iPhone."),
      ("Eye phone sales.", "iPhone sales."),
      ("Runs on m l x.", "Runs on MLX."),
      ("“Jeff”, she said.", "“Jeph”, she said."),
      ("Written in C plus plus.", "Written in C++."),
      ("A dot net app.", "A .NET app."),
      ("No dictionary words here.", "No dictionary words here."),
      ("", ""),
    ]
  )
  func swapsSoundsLikeSpellingsForTheirWords(transcript: String, expected: String) {
    #expect(DictionaryCorrection.swapSoundsLike(in: transcript, dictionary: Self.dictionary) == expected)
  }

  /// Where two spellings overlap, the longer one wins, then the one that starts first.
  @Test(
    arguments: [
      ("The tail scale wise.", "The Tailscale wise."),
      ("A scale wise tail scale.", "A Scalewise Tailscale."),
      ("A tail scale wise guy.", "A tail Scalewise guy."),
    ]
  )
  func resolvesOverlappingSpellings(transcript: String, expected: String) {
    let dictionary = Self.dictionary + [DictionaryWord(text: "Scalewise guy", soundsLike: ["scale wise guy"])]
    #expect(DictionaryCorrection.swapSoundsLike(in: transcript, dictionary: dictionary) == expected)
  }

  @Test func spellingsOnlyMatchWholeWords() {
    let dictionary = [DictionaryWord(text: "Ann", soundsLike: ["an"])]
    #expect(DictionaryCorrection.swapSoundsLike(in: "Plan an answer.", dictionary: dictionary) == "Plan Ann answer.")
  }

  @Test func wordsWithoutSoundsLikeLeaveTheTranscriptAlone() {
    let dictionary = [DictionaryWord(text: "Jeph")]
    #expect(DictionaryCorrection.swapSoundsLike(in: "Tell Jeff.", dictionary: dictionary) == "Tell Jeff.")
  }

  @Test(
    arguments: [
      // A capital first letter carries over to a word the dictionary spells in lowercase.
      ("Cube control", "kubectl", "Kubectl"),
      ("cube control", "kubectl", "kubectl"),
      // Otherwise the dictionary's capitals win.
      ("eye phone", "iPhone", "iPhone"),
      ("Eye phone", "iPhone", "iPhone"),
      ("jeff", "Jeph", "Jeph"),
      ("m l x", "MLX", "MLX"),
      // Speech models don't write in all capitals, so there's no rule for it.
      ("EYE PHONE", "iPhone", "iPhone"),
      ("“Jeff", "jeph", "Jeph"),
    ]
  )
  func capitalizesLikeTheReplacedText(written: String, word: String, expected: String) {
    #expect(DictionaryCorrection.matchingCase(of: written[...], word) == expected)
  }

  /// Replacements a transcriber's library finds follow the same rules as the swap.
  @Test func replacesRangesLongestFirstFromTheEnd() {
    let text = "Ask shivon about the tail scale config."
    func range(of words: String) -> Range<String.Index> {
      text.range(of: words) ?? text.startIndex..<text.startIndex
    }
    let replacements = [
      DictionaryCorrection.Replacement(range: range(of: "shivon"), word: "Siobhan"),
      DictionaryCorrection.Replacement(range: range(of: "tail"), word: "Tail"),
      DictionaryCorrection.Replacement(range: range(of: "tail scale"), word: "Tailscale"),
    ]
    #expect(DictionaryCorrection.replace(replacements, in: text) == "Ask Siobhan about the Tailscale config.")
  }
}

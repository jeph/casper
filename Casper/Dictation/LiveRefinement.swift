import NaturalLanguage

/// The text of a recording refined while it's in progress: refined text that's settled, refined text still open to
/// change, and transcribed sentences waiting to be refined.
///
/// Each refine is given the open text along with the sentences transcribed since, so taking something back can still
/// reach the words it replaces, and a sentence split across two refines is refined whole. The open text is the last
/// whole sentences of the refined text holding at least `openWords` words, so short sentences keep more of them open.
/// The newest transcribed sentence waits for the next refine, since the user may have paused in the middle of it.
struct LiveRefinement {
  /// The fewest words of refined text kept open, unless there are fewer.
  let openWords: Int

  /// The refined text that won't change, ending with the space or line breaks after its last sentence.
  private var settled = ""
  private var open = ""
  /// The transcribed text not refined yet.
  private var waiting = ""

  init(openWords: Int) {
    self.openWords = openWords
  }

  mutating func append(transcript: String) {
    waiting = Self.joined(waiting, transcript)
  }

  /// Takes the text for a refine while recording: the open text and the transcribed sentences before the newest, or
  /// `nil` if there are none.
  ///
  /// Pass the refined text to `refined(_:)` before taking more.
  mutating func takeText() -> String? {
    let sentences = Self.sentences(in: waiting)
    guard sentences.count > 1, let newest = sentences.last?.lowerBound else { return nil }
    let text = Self.joined(open, String(waiting[..<newest]))
    waiting = String(waiting[newest...])
    open = ""
    return text
  }

  /// Takes the text for the last refine, once the recording has ended: the open text and all the transcribed text.
  mutating func takeLastText() -> String {
    let text = Self.joined(open, waiting)
    open = ""
    waiting = ""
    return text
  }

  /// Settles all but the last whole sentences of refined text holding at least `openWords` words, and keeps those
  /// open.
  ///
  /// A fragment at the end, without the mark that ends a sentence, stays open without counting toward them.
  mutating func refined(_ text: String) {
    var sentences = Self.sentences(in: text)
    var openStart = text.endIndex
    if let last = sentences.last, !Self.endsSentence(text[last]) {
      openStart = last.lowerBound
      sentences.removeLast()
    }
    var words = 0
    while words < openWords, let sentence = sentences.popLast() {
      openStart = sentence.lowerBound
      words += RefinePersona.wordCount(of: String(text[sentence]))
    }
    settled = Self.settling(String(text[..<openStart]), after: settled)
    open = text[openStart...].trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The whole refined text, given the last refined text.
  func finished(lastRefined: String) -> String {
    Self.settling(lastRefined, after: settled).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The ranges of the sentences in `text`, each with the space or line breaks after it, leaving out blank lines.
  private static func sentences(in text: String) -> [Range<String.Index>] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    return tokenizer.tokens(for: text.startIndex..<text.endIndex)
      .filter { !text[$0].allSatisfy(\.isWhitespace) }
  }

  /// Whether a sentence ends with the mark that ends one, possibly followed by closing quotes or brackets.
  private static func endsSentence(_ sentence: Substring) -> Bool {
    let closing: Set<Character> = ["\"", "'", "”", "’", ")", "]", "」", "』", "»"]
    let marks: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "؟", "।"]
    guard let last = sentence.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }) else {
      return false
    }
    return marks.contains(last)
  }

  /// `text` added to settled text, with a space between them unless the settled text ends with one or a line break.
  private static func settling(_ text: String, after settled: String) -> String {
    guard let last = settled.last, !last.isWhitespace, !text.isEmpty else { return settled + text }
    return settled + " " + text
  }

  private static func joined(_ first: String, _ second: String) -> String {
    [first, second]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

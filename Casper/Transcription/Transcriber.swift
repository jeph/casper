/// Turns recorded speech into text.
///
/// Each speech model is wrapped in a type conforming to this protocol. The rest of Casper only uses this protocol,
/// so recording and insertion don't depend on which model runs.
protocol Transcriber: Sendable {
  /// Transcribes mono audio, returning the text without surrounding whitespace.
  ///
  /// The transcript's length is bounded by the length of the audio, so a model that gets stuck can't run on. A model
  /// that writes text one token at a time has nothing stopping it, so its transcriber limits it to
  /// `maximumTokens(forSeconds:)`. One whose library already bounds its output by the audio relies on that instead.
  ///
  /// The transcriber uses whatever of the dictionary its model or library can: a model that takes a list of words gets
  /// the words, and a library that corrects misheard words itself also gets their Sounds Like spellings. One that can
  /// do neither ignores it. Casper swaps Sounds Like spellings for their words afterward whatever the model, so a
  /// transcriber doesn't need to.
  func transcribe(_ samples: [Float], sampleRate: Double, dictionary: [DictionaryWord]) async throws -> String

  /// Builds whatever the transcriber makes from the dictionary ahead of the next dictation, so it doesn't wait for it.
  ///
  /// Nothing a transcriber builds from the dictionary may need the model reloaded: a change applies to the next
  /// dictation either way.
  func prepare(for dictionary: [DictionaryWord]) async

  /// Frees the memory the model uses. The transcriber can't be used afterward.
  func unload() async
}

extension Transcriber {
  /// The most tokens a transcript of `seconds` of audio can take.
  ///
  /// Read English speech averages 3.4 tokens a second and peaks at 6.5, so 10 a second leaves room for fast speech
  /// and other languages. The allowance on top covers labels a model writes before the transcript, such as the
  /// language it detected.
  static func maximumTokens(forSeconds seconds: Double) -> Int {
    16 + Int((seconds * 10).rounded(.up))
  }

  func prepare(for dictionary: [DictionaryWord]) async {}
}

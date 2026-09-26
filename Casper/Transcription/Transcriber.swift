/// Turns recorded speech into text.
///
/// Each speech model is wrapped in a type conforming to this protocol. The rest of Casper only uses this protocol,
/// so recording and insertion don't depend on which model runs.
protocol Transcriber: Sendable {
  /// Transcribes mono audio, returning the text without surrounding whitespace.
  func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String
}

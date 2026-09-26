import AudioCommon

/// Runs any speech-to-text model from the speech-swift library, which all conform to its `SpeechRecognitionModel`.
///
/// The model runs on this actor, off the main thread, and handles one transcription at a time.
actor SpeechSwiftTranscriber: Transcriber {
  private let model: any SpeechRecognitionModel

  init(model: sending any SpeechRecognitionModel) {
    self.model = model
  }

  func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
    // A nil language lets the model detect it.
    model.transcribe(audio: samples, sampleRate: Int(sampleRate), language: nil)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

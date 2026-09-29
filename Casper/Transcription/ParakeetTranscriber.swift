import FluidAudio

/// Transcribes with a Parakeet TDT model through FluidAudio.
///
/// Parakeet writes each token at a point in the audio and can't go past its end, and FluidAudio caps the tokens in
/// each 15-second window, so its transcripts are already bounded by the length of the audio.
actor ParakeetTranscriber: Transcriber {
  enum TranscriptionError: Error {
    case unloaded
  }

  private var manager: AsrManager?
  private let decoderLayers: Int

  init(models: AsrModels) async throws {
    let manager = AsrManager()
    try await manager.loadModels(models)
    self.manager = manager
    decoderLayers = models.version.decoderLayers
  }

  /// FluidAudio takes samples at 16 kHz only, which `SpeechModel.sampleRate` records at.
  func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
    guard let manager else { throw TranscriptionError.unloaded }
    // Each recording is transcribed on its own, so the decoder starts fresh rather than continuing the last one.
    var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
    return try await manager.transcribe(samples, decoderState: &decoderState).text
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func unload() async {
    await manager?.cleanup()
    manager = nil
  }
}

import Observation

/// What dictation is doing, for showing it on screen.
@MainActor
@Observable
final class DictationStatus {
  enum Phase {
    case idle
    /// The hotkey is held, or was just released and the last moment of speech is still being recorded.
    case recording
    /// Recording ended and its transcript hasn't been typed yet.
    case transcribing
  }

  /// The loudness of the recording in progress.
  let meter: AudioLevelMeter
  var isRecording = false
  var transcriptionsInProgress = 0

  init(meter: AudioLevelMeter) {
    self.meter = meter
  }

  /// A new recording shows over transcriptions still finishing from earlier ones.
  var phase: Phase {
    if isRecording { return .recording }
    return transcriptionsInProgress > 0 ? .transcribing : .idle
  }
}

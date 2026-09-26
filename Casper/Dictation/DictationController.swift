import AVFoundation
import OSLog

/// Push-to-talk dictation: records while the dictation hotkey is held, then types the transcript at the cursor.
@MainActor
final class DictationController {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Dictation")

  private let model = SpeechModel.qwen3ASR17B
  /// Loads while Casper starts, so the model is usually ready by the first dictation.
  private let transcriber: Task<any Transcriber, any Error>
  private let recorder = AudioRecorder()
  private var hotkey: GlobalHotkey?
  /// The latest transcription, which the next one waits for so transcripts are typed in the order they were spoken.
  private var latestTranscription: Task<Void, Never>?

  init() {
    let model = model
    transcriber = Task.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let transcriber = try await model.loadTranscriber()
      Self.logger.info("Loaded the speech model in \(ContinuousClock.now - start, privacy: .public)")
      return transcriber
    }
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.startRecording() },
      onRelease: { [weak self] in self?.finishRecording() }
    )
  }

  private func startRecording() {
    guard !recorder.isRecording else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      break
    case .notDetermined:
      Task { await AVCaptureDevice.requestAccess(for: .audio) }
      return
    default:
      Self.logger.error("Microphone access is off.")
      return
    }
    do {
      try recorder.start(sampleRate: model.sampleRate)
    } catch {
      Self.logger.error("Couldn't start recording: \(error)")
    }
  }

  private func finishRecording() {
    guard recorder.isRecording else { return }
    let samples = recorder.stop()
    guard !samples.isEmpty else { return }
    let sampleRate = model.sampleRate
    let previous = latestTranscription
    latestTranscription = Task { [transcriber] in
      do {
        let start = ContinuousClock.now
        let text = try await transcriber.value.transcribe(samples, sampleRate: sampleRate)
        let seconds = Double(samples.count) / sampleRate
        Self.logger.info(
          "Transcribed \(seconds, format: .fixed(precision: 1)) s of audio in \(ContinuousClock.now - start, privacy: .public)"
        )
        await previous?.value
        // A trailing space lets the next dictation, or typing, continue the sentence without joining words.
        if let last = text.last {
          TextInserter.insert(last.isWhitespace ? text : text + " ")
        }
      } catch {
        Self.logger.error("Couldn't transcribe: \(error)")
      }
    }
  }
}

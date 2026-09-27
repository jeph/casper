import AVFoundation
import OSLog

/// Push-to-talk dictation: records while the dictation hotkey is held, then types the transcript at the cursor.
@MainActor
final class DictationController {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Dictation")

  private let model = SpeechModel.qwen3ASR17B
  /// Loads while Casper starts, so the model is usually ready by the first dictation.
  private let transcriber: Task<any Transcriber, any Error>
  private let recorder: AudioRecorder
  private var hotkey: GlobalHotkey?
  /// The latest transcription, which the next one waits for so transcripts are typed in the order they were spoken.
  private var latestTranscription: Task<Void, Never>?
  /// Stops the recording shortly after the hotkey is released, unless the hotkey is pressed again first.
  private var pendingStop: Task<Void, Never>?
  /// The keep-alive setting in effect, compared against the stored one when settings change.
  private var keepAlive = MicrophoneKeepAlive.stored
  /// Turns the microphone off once the keep-alive time has passed since the last dictation.
  private var closeMicrophone: Task<Void, Never>?

  /// How long recording continues after the hotkey is released.
  ///
  /// People tend to let go while still finishing the last word, and the microphone delivers audio slightly after it's
  /// spoken.
  private static let recordingTail = Duration.milliseconds(300)

  init() {
    let model = model
    recorder = AudioRecorder(sampleRate: model.sampleRate)
    transcriber = Task.detached(priority: .userInitiated) {
      let start = ContinuousClock.now
      let transcriber = try await model.loadTranscriber()
      Self.logger.info("Loaded the speech model in \(ContinuousClock.now - start, privacy: .public)")
      return transcriber
    }
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.hotkeyPressed() },
      onRelease: { [weak self] in self?.hotkeyReleased() }
    )
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.keepAliveSettingMayHaveChanged() }
    }
    applyKeepAlive()
  }

  private func keepAliveSettingMayHaveChanged() {
    let stored = MicrophoneKeepAlive.stored
    guard stored != keepAlive else { return }
    keepAlive = stored
    applyKeepAlive()
  }

  /// Turns the microphone on or off, or schedules it to turn off, as the keep-alive setting says.
  ///
  /// Runs at launch, after each dictation, and when the setting changes. A timed setting counts from when this runs.
  private func applyKeepAlive() {
    closeMicrophone?.cancel()
    closeMicrophone = nil
    guard !recorder.isRecording else { return }
    switch keepAlive {
    case .off:
      recorder.close()
    case .always:
      // Asking for access is left to the first dictation, rather than prompting as Casper launches.
      guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
      do {
        try recorder.open()
      } catch {
        Self.logger.error("Couldn't turn the microphone on: \(error)")
      }
    case .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes:
      guard recorder.isOpen, let timeout = keepAlive.timeout else { return }
      closeMicrophone = Task {
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        // The sleep can finish just before a dictation cancels the task, in which case it doesn't throw.
        guard !Task.isCancelled else { return }
        closeMicrophone = nil
        recorder.close()
      }
    }
  }

  private func hotkeyPressed() {
    // Pressing again before the recording stops continues the same recording.
    if let pendingStop {
      pendingStop.cancel()
      self.pendingStop = nil
      return
    }
    startRecording()
  }

  private func hotkeyReleased() {
    guard recorder.isRecording, pendingStop == nil else { return }
    pendingStop = Task {
      do {
        try await Task.sleep(for: Self.recordingTail)
      } catch {
        return
      }
      // The sleep can finish just before a re-press cancels the task, in which case it doesn't throw.
      guard !Task.isCancelled else { return }
      pendingStop = nil
      finishRecording()
    }
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
    closeMicrophone?.cancel()
    closeMicrophone = nil
    do {
      try recorder.start()
    } catch {
      Self.logger.error("Couldn't start recording: \(error)")
    }
  }

  private func finishRecording() {
    guard recorder.isRecording else { return }
    let samples = recorder.stop()
    applyKeepAlive()
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

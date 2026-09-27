import AVFoundation
import OSLog

/// Push-to-talk dictation: records while the dictation hotkey is held, then types the transcript at the cursor.
@MainActor
final class DictationController {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Dictation")

  /// What dictation is doing, for the voice bubble.
  let status: DictationStatus
  private let speechModel: SpeechModelLoader
  private let recorder: AudioRecorder
  private let microphoneKeepAlive: KeepAliveSchedule
  private let speechModelKeepAlive: KeepAliveSchedule
  private var hotkey: GlobalHotkey?
  /// The latest transcription, which the next one waits for so transcripts are typed in the order they were spoken.
  private var latestTranscription: Task<Void, Never>?
  /// Stops the recording shortly after the hotkey is released, unless the hotkey is pressed again first.
  private var pendingStop: Task<Void, Never>?
  /// The active speech model's ID, compared against the stored one when settings change.
  private var activeModelID = SpeechModel.active?.id

  /// How long recording continues after the hotkey is released.
  ///
  /// People tend to let go while still finishing the last word, and the microphone delivers audio slightly after it's
  /// spoken.
  private static let recordingTail = Duration.milliseconds(300)

  init() {
    let recorder = AudioRecorder(sampleRate: SpeechModel.sampleRate)
    let speechModel = SpeechModelLoader()
    self.recorder = recorder
    self.speechModel = speechModel
    status = DictationStatus(meter: recorder.meter)
    microphoneKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.microphoneStorageKey,
      isInUse: { recorder.isRecording },
      isPrepared: { recorder.isOpen },
      prepare: {
        // Asking for access is left to the first dictation, rather than prompting as Casper launches.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        do {
          try recorder.open()
        } catch {
          Self.logger.error("Couldn't turn the microphone on: \(error)")
        }
      },
      release: { recorder.close() }
    )
    speechModelKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.speechModelStorageKey,
      isInUse: { speechModel.isInUse },
      isPrepared: { speechModel.isLoaded },
      prepare: { speechModel.load() },
      release: { speechModel.unload() }
    )
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.hotkeyPressed() },
      onRelease: { [weak self] in self?.hotkeyReleased() }
    )
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.activeModelMayHaveChanged() }
    }
  }

  /// Unloads the previous model once nothing is using it, and loads the new one if its keep-alive setting says to.
  private func activeModelMayHaveChanged() {
    let id = SpeechModel.active?.id
    guard id != activeModelID else { return }
    activeModelID = id
    speechModel.unloadIfInactive()
    speechModelKeepAlive.apply()
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
    pendingStop = Task.afterDelay(Self.recordingTail) { [weak self] in
      self?.pendingStop = nil
      self?.finishRecording()
    }
  }

  private func startRecording() {
    guard !recorder.isRecording else { return }
    guard SpeechModel.active != nil else {
      Self.logger.error("No voice model is chosen, so there's nothing to transcribe with.")
      return
    }
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
    microphoneKeepAlive.useStarted()
    do {
      try recorder.start()
    } catch {
      Self.logger.error("Couldn't start recording: \(error)")
      return
    }
    status.isRecording = true
    speechModel.beginUse()
    speechModelKeepAlive.useStarted()
  }

  private func finishRecording() {
    guard recorder.isRecording else { return }
    let samples = recorder.stop()
    status.isRecording = false
    microphoneKeepAlive.apply()
    guard !samples.isEmpty else {
      endSpeechModelUse()
      return
    }
    status.transcriptionsInProgress += 1
    let previous = latestTranscription
    latestTranscription = Task {
      defer { status.transcriptionsInProgress -= 1 }
      do {
        let text = try await transcribe(samples)
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

  /// Transcribes a recording, then ends its use of the speech model.
  private func transcribe(_ samples: [Float]) async throws -> String {
    defer { endSpeechModelUse() }
    let start = ContinuousClock.now
    let text = try await speechModel.transcriber().value.transcribe(samples, sampleRate: SpeechModel.sampleRate)
    let seconds = Double(samples.count) / SpeechModel.sampleRate
    Self.logger.info(
      "Transcribed \(seconds, format: .fixed(precision: 1)) s of audio in \(ContinuousClock.now - start, privacy: .public)"
    )
    return text
  }

  private func endSpeechModelUse() {
    speechModel.endUse()
    speechModelKeepAlive.apply()
  }
}

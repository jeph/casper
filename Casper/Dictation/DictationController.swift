import AVFoundation
import OSLog

/// Push-to-talk dictation: records while the dictation hotkey is held, then types the refined transcript at the cursor.
@MainActor
final class DictationController {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Dictation")

  /// What dictation is doing, for the voice bubble.
  let status: DictationStatus
  private let speechModel: SpeechModelLoader
  private let refineModel: RefineModelLoader
  private let recorder: AudioRecorder
  private let microphoneKeepAlive: KeepAliveSchedule
  private let modelKeepAlive: KeepAliveSchedule
  private var hotkey: GlobalHotkey?
  /// The number the next finished recording gets, counting up in the order recordings were made.
  private var nextDictation = 0
  /// The number of the earliest dictation whose text hasn't been typed yet.
  private var nextDelivery = 0
  /// Text of dictations that finished before an earlier one, waiting to be typed in order, by dictation number.
  private var undelivered: [Int: String] = [:]
  /// Stops the recording shortly after the hotkey is released, unless the hotkey is pressed again first.
  private var pendingStop: Task<Void, Never>?
  /// The active speech model's ID, compared against the stored one when settings change.
  private var activeModelID = SpeechModel.active?.id
  /// The refine setting in effect, compared against the stored one when settings change.
  private var refinesTranscripts = TranscriptRefiner.isEnabled
  /// Whether the recording in progress will be refined, decided when it starts so its model loads while the user speaks.
  private var refinesRecording = false

  /// How long recording continues after the hotkey is released.
  ///
  /// People tend to let go while still finishing the last word, and the microphone delivers audio slightly after it's
  /// spoken.
  private static let recordingTail = Duration.milliseconds(150)

  init() {
    let recorder = AudioRecorder(sampleRate: SpeechModel.sampleRate)
    let speechModel = SpeechModelLoader()
    let refineModel = RefineModelLoader()
    self.recorder = recorder
    self.speechModel = speechModel
    self.refineModel = refineModel
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
    // The speech and refine models share one keep-alive setting, since each dictation needs both.
    modelKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.modelStorageKey,
      isInUse: { speechModel.isInUse || refineModel.isInUse },
      isPrepared: { speechModel.isLoaded || refineModel.isLoaded },
      prepare: {
        speechModel.load()
        if TranscriptRefiner.isEnabled {
          refineModel.load()
        }
      },
      release: {
        speechModel.unload()
        refineModel.unload()
      }
    )
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.hotkeyPressed() },
      onRelease: { [weak self] in self?.hotkeyReleased() }
    )
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.activeModelMayHaveChanged()
        self?.refineSettingMayHaveChanged()
      }
    }
  }

  /// Unloads the previous model once nothing is using it, and loads the new one if its keep-alive setting says to.
  private func activeModelMayHaveChanged() {
    let id = SpeechModel.active?.id
    guard id != activeModelID else { return }
    activeModelID = id
    speechModel.unloadIfInactive()
    modelKeepAlive.apply()
  }

  /// Unloads the refine model once nothing is using it if refining was turned off, and loads it if it was turned on and
  /// the keep-alive setting says to.
  private func refineSettingMayHaveChanged() {
    let enabled = TranscriptRefiner.isEnabled
    guard enabled != refinesTranscripts else { return }
    refinesTranscripts = enabled
    if !enabled {
      refineModel.unload()
    }
    modelKeepAlive.apply()
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
    refinesRecording = TranscriptRefiner.isEnabled
    if refinesRecording {
      refineModel.beginUse()
    }
    modelKeepAlive.useStarted()
  }

  private func finishRecording() {
    guard recorder.isRecording else { return }
    let samples = recorder.stop()
    status.isRecording = false
    microphoneKeepAlive.apply()
    guard !samples.isEmpty else {
      if refinesRecording {
        endRefineModelUse()
      }
      endSpeechModelUse()
      return
    }
    status.transcriptionsInProgress += 1
    let dictation = nextDictation
    nextDictation += 1
    let refines = refinesRecording
    // Each dictation is transcribed and refined as soon as it can be, alongside earlier ones still in progress. Only
    // typing waits for them.
    Task {
      defer {
        status.transcriptionsInProgress -= 1
        if refines {
          endRefineModelUse()
        }
      }
      var text = ""
      do {
        let transcript = try await transcribe(samples)
        text = refines ? await refine(transcript) : transcript
      } catch {
        Self.logger.error("Couldn't transcribe: \(error)")
      }
      deliver(text, of: dictation)
    }
  }

  /// Types a dictation's text once every earlier dictation's has been typed, along with later ones already finished.
  ///
  /// Finished dictations are typed in one paste because each paste replaces the clipboard, possibly before the app
  /// has read the previous one.
  private func deliver(_ text: String, of dictation: Int) {
    // A trailing space lets the next dictation, or typing, continue the sentence without joining words.
    undelivered[dictation] = text.last.map { $0.isWhitespace ? text : text + " " } ?? ""
    var ready = ""
    while let next = undelivered.removeValue(forKey: nextDelivery) {
      ready += next
      nextDelivery += 1
    }
    if !ready.isEmpty {
      TextInserter.insert(ready)
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

  /// Refines a transcript, or returns it unchanged if refining fails.
  private func refine(_ transcript: String) async -> String {
    guard !transcript.isEmpty else { return transcript }
    let start = ContinuousClock.now
    do {
      let text = try await refineModel.load().value.refine(transcript)
      Self.logger.info("Refined the transcript in \(ContinuousClock.now - start, privacy: .public)")
      return text
    } catch {
      Self.logger.error("Couldn't refine, so the transcript is typed as it is: \(error)")
      return transcript
    }
  }

  private func endSpeechModelUse() {
    speechModel.endUse()
    modelKeepAlive.apply()
  }

  private func endRefineModelUse() {
    refineModel.endUse()
    if !TranscriptRefiner.isEnabled {
      refineModel.unload()
    }
    modelKeepAlive.apply()
  }
}

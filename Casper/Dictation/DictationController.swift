import AVFoundation
import OSLog

/// Hotkey-driven dictation: records while the hotkey is held, or from one press to the next in toggle mode, then types
/// the refined transcript at the cursor.
@MainActor
final class DictationController {
  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Dictation")

  /// What dictation is doing, for the voice bubble.
  let status: DictationStatus
  private let speechModel: ModelLoader<SpeechModel>
  private let languageModel: ModelLoader<LanguageModel>
  private let recorder: AudioRecorder
  private let microphoneKeepAlive: KeepAliveSchedule
  private let modelKeepAlive: KeepAliveSchedule
  private let readiness: DictationReadiness
  private var hotkey: GlobalHotkey?
  /// The number the next finished recording gets, counting up in the order recordings were made.
  private var nextDictation = 0
  /// The number of the earliest dictation whose text hasn't been typed yet.
  private var nextDelivery = 0
  /// Text of dictations that finished before an earlier one, waiting to be typed in order, by dictation number.
  private var undelivered: [Int: String] = [:]
  /// Stops the recording shortly after the user ends it, unless the hotkey is pressed again first.
  private var pendingStop: Task<Void, Never>?
  /// The active models' IDs, compared against the stored ones when settings change.
  private var activeSpeechModelID = SpeechModel.active?.id
  private var activeLanguageModelID = LanguageModel.active?.id
  /// The refine setting in effect, compared against the stored one when settings change.
  private var refinesTranscripts = TranscriptRefiner.isEnabled
  /// Whether the recording in progress will be refined, decided when it starts so its model loads while the user speaks.
  private var refinesRecording = false

  /// How long recording continues after the hotkey is released, or pressed again in toggle mode.
  ///
  /// People tend to end a recording while still finishing the last word, and the microphone delivers audio slightly
  /// after it's spoken.
  private static let recordingTail = Duration.milliseconds(150)

  init(readiness: DictationReadiness) {
    self.readiness = readiness
    let permissions = readiness.permissions
    let recorder = AudioRecorder(sampleRate: SpeechModel.sampleRate)
    let speechModel = ModelLoader<SpeechModel>()
    let languageModel = ModelLoader<LanguageModel>()
    self.recorder = recorder
    self.speechModel = speechModel
    self.languageModel = languageModel
    status = DictationStatus(meter: recorder.meter)
    microphoneKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.microphoneStorageKey,
      isInUse: { recorder.isRecording },
      isPrepared: { recorder.isOpen },
      prepare: {
        // Asking for access is left to the first dictation, rather than prompting as Casper launches.
        guard permissions.isMicrophoneAllowed else { return }
        do {
          try recorder.open()
        } catch {
          Self.logger.error("Couldn't turn the microphone on: \(error)")
        }
      },
      release: { recorder.close() }
    )
    // The speech and language models share one keep-alive setting, since each dictation needs both.
    modelKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.modelStorageKey,
      isInUse: { speechModel.isInUse || languageModel.isInUse },
      isPrepared: { speechModel.isLoaded || languageModel.isLoaded },
      prepare: {
        speechModel.load()
        if TranscriptRefiner.isEnabled {
          languageModel.load()
        }
      },
      release: {
        speechModel.unload()
        languageModel.unload()
      }
    )
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.handle(.press) },
      onRelease: { [weak self] in self?.handle(.release) }
    )
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.activeModelsMayHaveChanged()
        self?.refineSettingMayHaveChanged()
      }
    }
  }

  /// Unloads previous models once nothing is using them, and loads new ones if the keep-alive setting says to.
  private func activeModelsMayHaveChanged() {
    let speechModelID = SpeechModel.active?.id
    let languageModelID = LanguageModel.active?.id
    guard speechModelID != activeSpeechModelID || languageModelID != activeLanguageModelID else { return }
    activeSpeechModelID = speechModelID
    activeLanguageModelID = languageModelID
    speechModel.unloadIfInactive()
    languageModel.unloadIfInactive()
    modelKeepAlive.apply()
  }

  /// Unloads the language model once nothing is using it if refining was turned off, and loads it if it was turned on
  /// and the keep-alive setting says to.
  private func refineSettingMayHaveChanged() {
    let enabled = TranscriptRefiner.isEnabled
    guard enabled != refinesTranscripts else { return }
    refinesTranscripts = enabled
    // A dictation using the model unloads it when it's done.
    if !enabled, !languageModel.isInUse {
      languageModel.unload()
    }
    modelKeepAlive.apply()
  }

  private func handle(_ event: DictationMode.HotkeyEvent) {
    let action = DictationMode.stored.action(
      for: event,
      isRecording: recorder.isRecording,
      isStopping: pendingStop != nil
    )
    switch action {
    case .startRecording:
      startRecordingIfReady()
    case .stopRecording:
      pendingStop = Task.afterDelay(Self.recordingTail) { [weak self] in
        self?.pendingStop = nil
        self?.finishRecording()
      }
    case .continueRecording:
      pendingStop?.cancel()
      pendingStop = nil
    case nil:
      break
    }
  }

  private func startRecordingIfReady() {
    // Access may have been turned off in System Settings since it was last checked.
    readiness.permissions.refresh()
    guard readiness.isReady else {
      // The voice bubble explains what's missing instead of listening.
      status.pressesWhileNotReady += 1
      if readiness.permissions.microphone == .notDetermined {
        Task {
          await AVCaptureDevice.requestAccess(for: .audio)
          readiness.permissions.refresh()
        }
      }
      return
    }
    startRecording()
  }

  private func startRecording() {
    guard !recorder.isRecording else { return }
    microphoneKeepAlive.useStarted()
    do {
      try recorder.start()
    } catch {
      Self.logger.error("Couldn't start recording: \(error)")
      return
    }
    status.isRecording = true
    speechModel.beginUse()
    refinesRecording = TranscriptRefiner.isEnabled && LanguageModel.active != nil
    if refinesRecording {
      languageModel.beginUse()
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
        endLanguageModelUse()
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
          endLanguageModelUse()
        }
      }
      let text: String
      do {
        let transcript = try await transcribe(samples)
        text = refines ? await refine(transcript) : transcript
      } catch {
        Self.logger.error("Couldn't transcribe: \(error)")
        text = ""
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
    let finished = (nextDelivery...).prefix { undelivered[$0] != nil }
    let ready = finished.compactMap { undelivered[$0] }.joined()
    nextDelivery += finished.count
    undelivered = undelivered.filter { $0.key >= nextDelivery }
    if !ready.isEmpty {
      TextInserter.insert(ready)
    }
  }

  /// Transcribes a recording, then ends its use of the speech model.
  private func transcribe(_ samples: [Float]) async throws -> String {
    defer { endSpeechModelUse() }
    let start = ContinuousClock.now
    let text = try await speechModel.model().value.transcribe(samples, sampleRate: SpeechModel.sampleRate)
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
      let text = try await languageModel.model().value.refine(transcript)
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

  private func endLanguageModelUse() {
    languageModel.endUse()
    if !TranscriptRefiner.isEnabled, !languageModel.isInUse {
      languageModel.unload()
    }
    modelKeepAlive.apply()
  }
}

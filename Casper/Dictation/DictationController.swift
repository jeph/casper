import AVFoundation
import OSLog
import Observation

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
  private let readiness: DictationReadiness
  private let personas: PersonaStore
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
  /// The persona the recording in progress is refined with, or `nil` if it isn't refined, decided when it starts so its
  /// model loads while the user speaks, and so editing the persona meanwhile doesn't change how it's refined.
  private var recordingPersona: RefinePersona?

  /// How long recording continues after the hotkey is released, or pressed again in toggle mode.
  ///
  /// People tend to end a recording while still finishing the last word, and the microphone delivers audio slightly
  /// after it's spoken.
  private static let recordingTail = Duration.milliseconds(150)

  init(readiness: DictationReadiness, personas: PersonaStore) {
    self.readiness = readiness
    self.personas = personas
    let permissions = readiness.permissions
    let recorder = AudioRecorder(sampleRate: SpeechModel.sampleRate)
    self.recorder = recorder
    speechModel = ModelLoader()
    languageModel = ModelLoader()
    status = DictationStatus(meter: recorder.meter)
    microphoneKeepAlive = KeepAliveSchedule(
      storageKey: KeepAlive.microphoneStorageKey,
      isInUse: { recorder.isRecording },
      isPrepared: { recorder.isOpen },
      prepare: {
        // Asking for access is left to the first dictation, rather than prompting as Casper launches.
        if permissions.isMicrophoneAllowed {
          recorder.open()
        }
      },
      release: { recorder.close() }
    )
    hotkey = GlobalHotkey(
      onPress: { [weak self] in self?.handle(.press) },
      onRelease: { [weak self] in self?.handle(.release) }
    )
    // The models load as Casper launches and stay loaded, so no dictation waits for them.
    speechModel.keepLoaded()
    if refinesTranscripts {
      languageModel.keepLoaded()
    }
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        // The refine setting comes first, so a model chosen at the same time loads only if refining is on.
        self?.refineSettingMayHaveChanged()
        self?.activeModelsMayHaveChanged()
      }
    }
    cacheChosenPersonaPromptOnChange()
  }

  /// Loads the language model if refining was turned on, and unloads it once nothing is using it if it was turned off.
  private func refineSettingMayHaveChanged() {
    let enabled = TranscriptRefiner.isEnabled
    guard enabled != refinesTranscripts else { return }
    refinesTranscripts = enabled
    if enabled {
      languageModel.keepLoaded()
      cacheChosenPersonaPrompt()
    } else {
      languageModel.release()
    }
  }

  /// Replaces a model the user switched away from with the newly chosen one.
  private func activeModelsMayHaveChanged() {
    let speechModelID = SpeechModel.active?.id
    let languageModelID = LanguageModel.active?.id
    guard speechModelID != activeSpeechModelID || languageModelID != activeLanguageModelID else { return }
    activeSpeechModelID = speechModelID
    activeLanguageModelID = languageModelID
    speechModel.keepLoaded()
    if refinesTranscripts {
      languageModel.keepLoaded()
      cacheChosenPersonaPrompt()
    }
  }

  /// Caches the chosen persona's prompt now and again whenever the user picks another persona or edits it.
  private func cacheChosenPersonaPromptOnChange() {
    withObservationTracking {
      _ = personas.selected
    } onChange: { [weak self] in
      // Tracking ends with the first change, which is reported before it's made, so tracking starts over after it.
      Task { @MainActor in self?.cacheChosenPersonaPromptOnChange() }
    }
    cacheChosenPersonaPrompt()
  }

  /// Has the language model read the chosen persona's prompt start in the background, if refining is on, so the next
  /// dictation doesn't wait for it.
  private func cacheChosenPersonaPrompt() {
    guard refinesTranscripts, let loading = try? languageModel.model() else { return }
    let persona = personas.selected
    Task {
      try? await loading.value.cachePrompt(for: persona)
    }
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
    recorder.start()
    status.isRecording = true
    speechModel.beginUse()
    recordingPersona = TranscriptRefiner.isEnabled && LanguageModel.active != nil ? personas.selected : nil
    guard let persona = recordingPersona else { return }
    languageModel.beginUse()
    // A model that loads with this recording, after an earlier load failed, reads the prompt while the user speaks.
    guard let loading = try? languageModel.model() else { return }
    Task {
      try? await loading.value.cachePrompt(for: persona)
    }
  }

  private func finishRecording() {
    guard recorder.isRecording else { return }
    let samples = recorder.stop()
    // Counted before the recording ends, so the voice bubble goes straight from recording to transcribing.
    if !samples.isEmpty {
      status.transcriptionsInProgress += 1
    }
    status.isRecording = false
    microphoneKeepAlive.apply()
    guard !samples.isEmpty else {
      if recordingPersona != nil {
        languageModel.endUse()
      }
      speechModel.endUse()
      return
    }
    let dictation = nextDictation
    nextDictation += 1
    let persona = recordingPersona
    // Each dictation is transcribed and refined as soon as it can be, alongside earlier ones still in progress. Only
    // typing waits for them.
    Task {
      defer {
        status.transcriptionsInProgress -= 1
        if persona != nil {
          languageModel.endUse()
        }
      }
      let text: String
      do {
        let transcript = try await transcribe(samples)
        text = if let persona { await refine(transcript, persona: persona) } else { transcript }
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

  /// Transcribes a recording, with its silence shortened unless that's turned off, then ends its use of the speech
  /// model.
  private func transcribe(_ recording: [Float]) async throws -> String {
    defer { speechModel.endUse() }
    let start = ContinuousClock.now
    let speech = await Self.shortenSilence(in: recording)
    let trimmed = ContinuousClock.now
    let text = try await speechModel.model().value.transcribe(speech, sampleRate: SpeechModel.sampleRate)
    let recordingSeconds = Double(recording.count) / SpeechModel.sampleRate
    let speechSeconds = Double(speech.count) / SpeechModel.sampleRate
    Self.logger.info(
      """
      Trimmed \(recordingSeconds, format: .fixed(precision: 1)) s of audio to \
      \(speechSeconds, format: .fixed(precision: 1)) s in \(trimmed - start, privacy: .public), and transcribed it \
      in \(ContinuousClock.now - trimmed, privacy: .public)
      """
    )
    return text
  }

  /// Returns the recording with its silence shortened, unless that's turned off.
  ///
  /// Runs off the main actor, since the work grows with the recording's length and would otherwise hold up the UI.
  @concurrent
  nonisolated private static func shortenSilence(in recording: [Float]) async -> [Float] {
    guard SilenceTrimmer.isEnabled else { return recording }
    return SilenceTrimmer().trim(recording, sampleRate: SpeechModel.sampleRate)
  }

  /// Refines a transcript in a persona, or returns it unchanged if refining fails.
  private func refine(_ transcript: String, persona: RefinePersona) async -> String {
    guard !transcript.isEmpty else { return transcript }
    let start = ContinuousClock.now
    do {
      let text = try await languageModel.model().value.refine(transcript, persona: persona)
      Self.logger.info("Refined the transcript in \(ContinuousClock.now - start, privacy: .public)")
      return text
    } catch {
      Self.logger.error("Couldn't refine, so the transcript is typed as it is: \(error)")
      return transcript
    }
  }
}

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
  private let history: DictationHistory
  private let dictionary: DictionaryStore
  private var hotkey: GlobalHotkey?
  /// The number the next finished recording gets, counting up in the order recordings were made.
  private var nextDictation = 0
  /// The number of the earliest dictation whose text hasn't been typed yet.
  private var nextDelivery = 0
  /// Dictations that finished before an earlier one, waiting to be typed in order, by dictation number.
  private var undelivered: [Int: FinishedDictation] = [:]
  /// Stops the recording shortly after the user ends it, unless the hotkey is pressed again first.
  private var pendingStop: Task<Void, Never>?
  /// The active models' IDs, compared against the stored ones when settings change.
  private var activeSpeechModelID = SpeechModel.active?.id
  private var activeLanguageModelID = LanguageModel.active?.id
  /// The refine setting in effect, compared against the stored one when settings change.
  private var refinesTranscripts = TranscriptRefiner.isEnabled
  /// The dictionary setting in effect, compared against the stored one when settings change.
  private var usesDictionary: Bool
  /// The persona the recording in progress is refined with, or `nil` if it isn't refined, decided when it starts so its
  /// model loads while the user speaks, and so editing the persona meanwhile doesn't change how it's refined.
  private var recordingPersona: RefinePersona?

  /// How long recording continues after the hotkey is released, or pressed again in toggle mode.
  ///
  /// People tend to end a recording while still finishing the last word, and the microphone delivers audio slightly
  /// after it's spoken.
  private static let recordingTail = Duration.milliseconds(150)

  init(readiness: DictationReadiness, personas: PersonaStore, history: DictationHistory, dictionary: DictionaryStore) {
    self.readiness = readiness
    self.personas = personas
    self.history = history
    self.dictionary = dictionary
    usesDictionary = dictionary.isEnabled
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
        self?.dictionarySettingMayHaveChanged()
      }
    }
    cacheChosenPersonaPromptOnChange()
    prepareDictionaryOnChange()
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
    prepareDictionary()
    if refinesTranscripts {
      languageModel.keepLoaded()
      cacheChosenPersonaPrompt()
    }
  }

  /// Has the speech model build what it needs from the dictionary if it was turned on.
  ///
  /// Turned off, dictations pass no words, which needs nothing built.
  private func dictionarySettingMayHaveChanged() {
    let enabled = dictionary.isEnabled
    guard enabled != usesDictionary else { return }
    usesDictionary = enabled
    prepareDictionary()
  }

  /// Prepares the speech model for the dictionary now and again whenever the user changes its words.
  private func prepareDictionaryOnChange() {
    withObservationTracking {
      _ = dictionary.words
    } onChange: { [weak self] in
      // Tracking ends with the first change, which is reported before it's made, so tracking starts over after it.
      Task { @MainActor in self?.prepareDictionaryOnChange() }
    }
    prepareDictionary()
  }

  /// Has the speech model build what it makes from the dictionary in the background, so dictations don't wait for it.
  ///
  /// The model stays loaded; only what it built from the old words is replaced.
  private func prepareDictionary() {
    guard let loading = try? speechModel.model() else { return }
    let words = dictionary.wordsForDictation
    Task {
      try? await loading.value.prepare(for: words)
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
    // Dated when the recording ends, so the history lists dictations in the order they were spoken.
    let recordedAt = Date.now
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
      deliver(FinishedDictation(text: text, recordedAt: recordedAt), number: dictation)
    }
  }

  /// A dictation's final text, and when its recording ended.
  private struct FinishedDictation {
    let text: String
    let recordedAt: Date
  }

  /// Types a dictation's text and saves it to the history once every earlier dictation's has been, along with later
  /// ones already finished.
  ///
  /// Finished dictations are typed in one paste because each paste replaces the clipboard, possibly before the app
  /// has read the previous one. Saving in the same order keeps the history in the order dictations were spoken.
  private func deliver(_ finished: FinishedDictation, number: Int) {
    undelivered[number] = finished
    let ready = (nextDelivery...).prefix { undelivered[$0] != nil }.compactMap { undelivered[$0] }
    nextDelivery += ready.count
    undelivered = undelivered.filter { $0.key >= nextDelivery }
    for dictation in ready {
      history.save(dictation.text, recordedAt: dictation.recordedAt)
    }
    // A trailing space lets the next dictation, or typing, continue the sentence without joining words.
    let text =
      ready.map { dictation in
        dictation.text.last.map { $0.isWhitespace ? dictation.text : dictation.text + " " } ?? ""
      }
      .joined()
    if !text.isEmpty {
      TextInserter.insert(text)
    }
  }

  /// Transcribes a recording, with its silence shortened unless that's turned off, then ends its use of the speech
  /// model.
  ///
  /// The dictionary is read as the recording goes to the speech model, so a change made while recording applies.
  /// Sounds Like spellings are swapped for their words afterward, whatever the model did with them.
  private func transcribe(_ recording: [Float]) async throws -> String {
    defer { speechModel.endUse() }
    let start = ContinuousClock.now
    let speech = await Self.shortenSilence(in: recording)
    let trimmed = ContinuousClock.now
    let words = dictionary.wordsForDictation
    let transcript = try await speechModel.model().value
      .transcribe(
        speech,
        sampleRate: SpeechModel.sampleRate,
        dictionary: words
      )
    let text = await Self.swapSoundsLike(in: transcript, dictionary: words)
    let recordingSeconds = Double(recording.count) / SpeechModel.sampleRate
    let speechSeconds = Double(speech.count) / SpeechModel.sampleRate
    Self.logger.info(
      """
      Trimmed \(recordingSeconds, format: .fixed(precision: 1)) s of audio to \
      \(speechSeconds, format: .fixed(precision: 1)) s in \(trimmed - start, privacy: .public), and transcribed it \
      with \(words.count) dictionary words in \(ContinuousClock.now - trimmed, privacy: .public)
      """
    )
    return text
  }

  /// Runs off the main actor, since the work grows with the transcript and the dictionary.
  @concurrent
  nonisolated private static func swapSoundsLike(in transcript: String, dictionary: [DictionaryWord]) async -> String {
    DictionaryCorrection.swapSoundsLike(in: transcript, dictionary: dictionary)
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

import AppKit
import OSLog

/// Adds the words a user corrects in dictated text to the dictionary, when transcribing the dictation again with the
/// word in the dictionary shows the speech model misheard it.
///
/// Each word is saved with what the speech model wrote as its Sounds Like spelling, so later dictations put the word in
/// its place.
///
/// After each paste it watches the field Casper pasted into, compares the text there with what was typed each time the
/// user pauses, and replays each dictation with a correction while Casper is otherwise idle, one at a time. Each paste
/// has its own watch, so a paste into another field doesn't end an earlier one, but a paste into the same field does:
/// the earlier watch would take the pasted text for the user's edit. A dictation that starts cancels the replay in
/// progress, which runs again once Casper is idle. Recordings and transcripts are only held in memory, and only until
/// their paste's watch ends and their dictation is checked.
@MainActor
final class CorrectionLearner {
  /// What a replay needs from one dictation.
  struct Dictation {
    /// The audio as the speech model received it.
    let speech: [Float]
    /// The speech model's transcript, with Sounds Like spellings swapped, before any refining.
    let transcript: String
    /// The speech model that transcribed it, since a replay with another model proves nothing.
    let modelID: String
  }

  /// A dictation and the corrections whose replaced words its transcript has.
  private struct Check {
    let dictation: Dictation
    let corrections: [Correction]
  }

  nonisolated private static let logger = Logger(subsystem: "io.jeph.Casper", category: "CorrectionLearner")

  /// How long the user stops changing the field before it's compared with what was typed.
  private static let editPause = Duration.seconds(3)
  /// How long after a paste the field is watched at most.
  private static let watchLimit = Duration.seconds(60)
  /// How long the pasted text takes to reach the field, which the app does after Casper's ⌘V.
  private static let pasteDelay = Duration.milliseconds(500)

  private let dictionary: DictionaryStore
  private let speechModel: ModelLoader<SpeechModel>
  private let notifier: LearnedWordNotifier
  /// Whether dictation is recording, transcribing or refining, which replays wait for.
  private let isDictating: () -> Bool

  /// Dictations waiting for a replay, oldest first.
  private var checks: [Check] = []
  /// The replay in progress.
  private var replay: Task<Void, Never>?
  /// The watches still following fields Casper pasted into.
  private var watches: [PastedFieldWatch] = []
  /// The fields of pastes whose watches start once the pasted text has reached the field, by paste.
  private var pendingFields: [UUID: AXUIElement] = [:]

  init(
    dictionary: DictionaryStore,
    speechModel: ModelLoader<SpeechModel>,
    notifier: LearnedWordNotifier,
    isDictating: @escaping () -> Bool
  ) {
    self.dictionary = dictionary
    self.speechModel = speechModel
    self.notifier = notifier
    self.isDictating = isDictating
  }

  /// Starts watching for corrections to text Casper just pasted into the frontmost app, alongside the watches of
  /// earlier pastes into other fields, and ends the watch of an earlier paste into the same field.
  ///
  /// Call it right after the paste keystroke, before the app reports the pasted text to the earlier watch.
  func pasted(_ text: String, from dictations: [Dictation]) {
    guard let app = NSWorkspace.shared.frontmostApplication,
      // Casper's own fields, such as the dictionary's search, would have Casper wait on itself for every read.
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return }
    let watchesPaste = dictionary.learnsCorrections && !dictations.isEmpty
    // With no watch to end or start, the app isn't asked over Accessibility for its field.
    guard watchesPaste || !watches.isEmpty || !pendingFields.isEmpty,
      let field = PastedFieldWatch.focusedField(ofProcess: app.processIdentifier)
    else { return }
    endWatches(following: field)
    guard watchesPaste else { return }
    let paste = UUID()
    pendingFields[paste] = field
    Task {
      try? await Task.sleep(for: Self.pasteDelay)
      // A later paste into the same field took this one's place before its watch started.
      guard pendingFields.removeValue(forKey: paste) != nil,
        let watch = PastedFieldWatch(field: field, processID: app.processIdentifier, pasted: text)
      else { return }
      watches.append(watch)
      defer { watches.removeAll { $0 === watch } }
      // Each edit is checked once, though the field is compared again at every pause.
      var queued: Set<Correction> = []
      for await edited in watch.edits(pause: Self.editPause, limit: Self.watchLimit) {
        let found = await Self.checks(typed: text, field: edited, dictations: dictations)
        let new = found.compactMap { check in
          let corrections = check.corrections.filter { !queued.contains($0) }
          return corrections.isEmpty ? nil : Check(dictation: check.dictation, corrections: corrections)
        }
        queued.formUnion(new.flatMap(\.corrections))
        checks += new
        replayNext()
      }
    }
  }

  /// Ends the watches of earlier pastes into the field, including those that haven't started yet.
  private func endWatches(following field: AXUIElement) {
    let unstarted = pendingFields.filter { CFEqual($0.value, field) }.keys
    for paste in unstarted {
      pendingFields[paste] = nil
    }
    let ended = watches.count { $0.endBeforePaste(into: field) } + unstarted.count
    guard ended > 0 else { return }
    Self.logger.info("Ended the watches of \(ended) earlier pastes into the field Casper pasted into")
  }

  /// Cancels the replay in progress, which runs again once dictation is done, so a new dictation never waits for it.
  func dictationStarted() {
    replay?.cancel()
  }

  /// Starts the next replay if dictation is done.
  func dictationEnded() {
    replayNext()
  }

  /// The dictations to replay for the user's corrections to a paste, each with the corrections only its transcript has.
  ///
  /// A correction whose words are in several of the paste's dictations is dropped, since it's unknown which one the
  /// user edited.
  ///
  /// Runs off the main actor, since the work grows with the pasted text and the field.
  @concurrent
  nonisolated private static func checks(typed: String, field: String, dictations: [Dictation]) async -> [Check] {
    let corrections = CorrectionFinder.corrections(typed: typed, field: field)
    logger.info("Found \(corrections.count) corrections to a paste of \(dictations.count) dictations")
    let transcripts = dictations.map(\.transcript)
    let byDictation = Dictionary(grouping: corrections) {
      ReplayCheck.transcript(containing: $0, among: transcripts)
    }
    return dictations.indices.compactMap { index in
      byDictation[index].map { Check(dictation: dictations[index], corrections: $0) }
    }
  }

  private func replayNext() {
    guard replay == nil, !isDictating(), let check = checks.first else { return }
    replay = Task {
      let learned = await replayed(check)
      replay = nil
      // A cancelled replay is tried again; any other outcome is final.
      if let learned {
        checks.removeFirst()
        add(learned)
      }
      replayNext()
    }
  }

  /// The corrections the replay confirms, or `nil` if it was cancelled.
  private func replayed(_ check: Check) async -> [Correction]? {
    let corrections = check.corrections.filter(isNew)
    guard dictionary.learnsCorrections, !corrections.isEmpty, SpeechModel.active?.id == check.dictation.modelID else {
      return []
    }
    // Without the Sounds Like spellings `add(_:)` saves: `confirmed` swaps those as text, so with them the replay would
    // confirm every correction whatever the audio says.
    let words = dictionary.wordsForDictation + corrections.map { DictionaryWord(text: $0.replacement) }
    speechModel.beginUse()
    defer { speechModel.endUse() }
    let start = ContinuousClock.now
    do {
      let transcript = try await speechModel.model().value
        .transcribe(check.dictation.speech, sampleRate: SpeechModel.sampleRate, dictionary: words)
      // Ending without throwing doesn't mean the replay wasn't cancelled partway.
      try Task.checkCancellation()
      let confirmed = await Self.confirmed(corrections, replay: transcript, of: check.dictation, dictionary: words)
      Self.logger.info(
        """
        Replayed a dictation for \(corrections.count) corrections in \(ContinuousClock.now - start, privacy: .public), \
        confirming \(confirmed.count)
        """
      )
      return confirmed
    } catch is CancellationError {
      return nil
    } catch {
      // Some libraries report cancellation with errors of their own.
      guard !Task.isCancelled else { return nil }
      Self.logger.error("Couldn't replay a dictation to check its corrections: \(error)")
      return []
    }
  }

  /// The corrections the replay wrote where the dictation's transcript has the words they replace.
  ///
  /// Runs off the main actor, since the work grows with the transcript.
  @concurrent
  nonisolated private static func confirmed(
    _ corrections: [Correction],
    replay: String,
    of dictation: Dictation,
    dictionary: [DictionaryWord]
  ) async -> [Correction] {
    let replay = DictionaryCorrection.swapSoundsLike(in: replay, dictionary: dictionary)
    return corrections.filter { ReplayCheck.replay(replay, of: dictation.transcript, supports: $0) }
  }

  /// Whether a correction's replacement isn't a word or Sounds Like spelling in the dictionary already.
  private func isNew(_ correction: Correction) -> Bool {
    !dictionary.isTaken(correction.replacement, exceptBy: nil)
      && !dictionary.words.contains { word in
        word.soundsLike.contains { $0.compare(correction.replacement, options: .caseInsensitive) == .orderedSame }
      }
  }

  private func add(_ corrections: [Correction]) {
    // Checked again, since the user may have changed the dictionary during the replay.
    for correction in corrections where dictionary.learnsCorrections && isNew(correction) {
      dictionary.save(DictionaryWord(text: correction.replacement, soundsLike: [correction.original]))
      notifier.notify(added: correction.replacement)
    }
  }
}

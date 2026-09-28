import Foundation
import Observation

/// What stops dictation from working, and the warning that tells the user how to fix it.
@MainActor
@Observable
final class DictationReadiness {
  /// Tells the user what dictation is missing, and the Settings page that fixes it.
  struct Warning: Equatable {
    let message: LocalizedStringResource
    /// What clicking the warning does, shown under the message.
    let action: LocalizedStringResource
    let pane: SettingsPane
  }

  /// Something dictation needs that's missing, most important first.
  private enum Issue: CaseIterable {
    case missingAccess
    case noVoiceModel
    /// Refining is on, but no language model is installed to refine with.
    case noLanguageModel

    var pane: SettingsPane {
      switch self {
      case .missingAccess: .permissions
      case .noVoiceModel: .voiceModels
      case .noLanguageModel: .languageModels
      }
    }
  }

  let permissions = Permissions()
  // Copies of settings in `UserDefaults`, which views can't observe directly.
  private var activeSpeechModelID = SpeechModel.active?.id
  private var activeLanguageModelID = LanguageModel.active?.id
  private var refinesTranscripts = TranscriptRefiner.isEnabled

  init() {
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
    }
  }

  /// The warning for the most important issue, or `nil` when dictation can work.
  var warning: Warning? { issue.map(warning(for:)) }

  var isReady: Bool { issue == nil }

  /// Whether a Settings page fixes an issue, which may not be the most important one.
  func needsAttention(_ pane: SettingsPane) -> Bool {
    Issue.allCases.contains { $0.pane == pane && has($0) }
  }

  private var issue: Issue? { Issue.allCases.first(where: has) }

  private func has(_ issue: Issue) -> Bool {
    switch issue {
    case .missingAccess: !permissions.isEverythingAllowed
    case .noVoiceModel: !isInstalled(activeSpeechModelID, in: SpeechModel.store)
    case .noLanguageModel: refinesTranscripts && !isInstalled(activeLanguageModelID, in: LanguageModel.store)
    }
  }

  private func isInstalled<Model>(_ id: Model.ID?, in store: ModelStore<Model>) -> Bool {
    id.map(store.installed.contains) ?? false
  }

  private func warning(for issue: Issue) -> Warning {
    switch issue {
    case .missingAccess:
      Warning(
        message: missingAccessMessage,
        action: LocalizedStringResource(
          "Click to open Permissions",
          comment: "Shown under a voice bubble warning. Clicking the bubble opens the Permissions page of Settings."
        ),
        pane: issue.pane
      )
    case .noVoiceModel:
      Warning(
        message: LocalizedStringResource(
          "Casper needs a voice model",
          comment: "Voice bubble warning when no voice model is installed."
        ),
        action: LocalizedStringResource(
          "Click to open Voice Models",
          comment: "Shown under a voice bubble warning. Clicking the bubble opens the Voice Models page of Settings."
        ),
        pane: issue.pane
      )
    case .noLanguageModel:
      Warning(
        message: LocalizedStringResource(
          "Refining needs a language model",
          comment: "Voice bubble warning when refining transcripts is on but no language model is installed."
        ),
        action: LocalizedStringResource(
          "Click to open Language Models",
          comment: "Shown under a voice bubble warning. Clicking the bubble opens the Language Models page of Settings."
        ),
        pane: issue.pane
      )
    }
  }

  private var missingAccessMessage: LocalizedStringResource {
    switch (permissions.isMicrophoneAllowed, permissions.isAccessibilityTrusted) {
    case (false, false):
      LocalizedStringResource(
        "Casper needs microphone and Accessibility access",
        comment: "Voice bubble warning when both permissions are missing. Accessibility is the System Settings pane."
      )
    case (false, true):
      LocalizedStringResource(
        "Casper needs microphone access",
        comment: "Voice bubble warning when microphone access is missing."
      )
    default:
      LocalizedStringResource(
        "Casper needs Accessibility access",
        comment: "Voice bubble warning when Accessibility access is missing. Accessibility is the System Settings pane."
      )
    }
  }

  private func settingsMayHaveChanged() {
    // Assigning an unchanged value would still redraw every view that shows it.
    let activeSpeechModelID = SpeechModel.active?.id
    if activeSpeechModelID != self.activeSpeechModelID {
      self.activeSpeechModelID = activeSpeechModelID
    }
    let activeLanguageModelID = LanguageModel.active?.id
    if activeLanguageModelID != self.activeLanguageModelID {
      self.activeLanguageModelID = activeLanguageModelID
    }
    let refinesTranscripts = TranscriptRefiner.isEnabled
    if refinesTranscripts != self.refinesTranscripts {
      self.refinesTranscripts = refinesTranscripts
    }
  }
}

import AppKit
import SwiftUI

/// The setup Casper walks a new user through in a window of its own, which opens Settings once finished.
///
/// Setup welcomes the user, has them choose a voice model and a language model and allow the access Casper needs, and
/// shows how to dictate.
///
/// Each step after the welcome needs its choice made or its access allowed before the next. Only finishing marks setup
/// as done, so setup closed before then starts over the next time Casper launches, and setup finished never shows
/// again.
struct OnboardingView: View {
  static let windowID = "onboarding"
  /// The `UserDefaults` key for whether the user has finished setup.
  static let completedStorageKey = "hasCompletedSetup"

  private enum Step: Int, CaseIterable {
    case welcome
    case voiceModel
    case languageModel
    case permissions
    case dictation
  }

  @State private var step = Step.welcome
  /// Whether the last change of step went forward, which sets the side pages slide in from and out to.
  @State private var isMovingForward = true
  @State private var practiceText = ""
  @AppStorage(completedStorageKey) private var hasCompletedSetup = false
  @AppStorage(SpeechModel.activeStorageKey) private var activeSpeechModelID = ""
  @AppStorage(LanguageModel.activeStorageKey) private var activeLanguageModelID = ""
  @AppStorage(Hotkey.dictationStorageKey) private var hotkey = Hotkey.dictationDefault
  @AppStorage(DictationMode.storageKey) private var dictationMode = DictationMode.defaultValue
  @Environment(Permissions.self) private var permissions
  @Environment(DictationReadiness.self) private var readiness
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismissWindow) private var dismissWindow

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        page
          .id(step)
          .transition(pageTransition)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      footer
    }
    .frame(width: 640, height: 680)
  }

  @ViewBuilder
  private var page: some View {
    switch step {
    case .welcome:
      WelcomePage()
    case .voiceModel:
      OnboardingPage(
        systemImage: "waveform",
        title: Text("Casper recognizes your voice", comment: "Title of the setup step for choosing a voice model."),
        message: Text(
          """
          A voice model on this Mac turns your speech into text. Your data is kept locally and never sent to the \
          cloud. Choose one to download. You can change it later in Settings.
          """,
          comment: "Explanation on the setup step for choosing a voice model."
        )
      ) {
        OnboardingModelPicker<SpeechModel>()
      }
    case .languageModel:
      OnboardingPage(
        systemImage: "wand.and.sparkles",
        title: Text(
          "Type what you mean, not what you say",
          comment: "Title of the setup step for choosing a language model, which refines what was dictated."
        ),
        message: Text(
          """
          Casper refines what you dictate with a language model on this Mac, removing filler words and fixing \
          grammar and punctuation. Choose one to download.
          """,
          comment: "Explanation on the setup step for choosing a language model."
        )
      ) {
        RefineDemo()
          .padding(.horizontal, 20)
        OnboardingModelPicker<LanguageModel>()
      }
    case .permissions:
      OnboardingPage(
        systemImage: "hand.raised",
        title: Text("Give Casper access", comment: "Title of the setup step for allowing permissions."),
        message: Text(
          """
          Casper needs the microphone to hear you and Accessibility to type for you. Notifications are optional: they \
          tell you when Casper learns a word.
          """,
          comment: "Explanation on the setup step for allowing the microphone, Accessibility and notifications."
        )
      ) {
        PermissionsView()
      }
    case .dictation:
      dictationPage
    }
  }

  private var dictationPage: some View {
    OnboardingPage(
      title: dictationMode == .hold
        ? Text("Hold \(hotkey.displayName) and speak", comment: "Title of setup's last step in hold mode.")
        : Text("Press \(hotkey.displayName) and speak", comment: "Title of setup's last step in toggle mode."),
      message: Text(
        """
        Casper types what you said wherever your cursor is, in any app. The voice bubble on your screen shows when \
        it's listening.
        """,
        comment: "Explanation on setup's last step, which shows how to dictate."
      )
    ) {
      DictationDemo()
      Form {
        Section {
          DictationShortcutRow()
          TextField(
            text: $practiceText,
            prompt: Text("Click here, then dictate to try it", comment: "Placeholder of the text field in setup."),
            axis: .vertical
          ) {
            Text("Try It", comment: "Accessibility label of the text field on setup's last step for trying dictation.")
          }
          .labelsHidden()
          .multilineTextAlignment(.leading)
          .lineLimit(1...2)
        }
        Section {
          ChosenModelStatus<SpeechModel>(
            kind: Text("Voice Model", comment: "Row on setup's last step showing whether the voice model is ready."),
            systemImage: "waveform"
          )
          ChosenModelStatus<LanguageModel>(
            kind: Text(
              "Language Model",
              comment: "Row on setup's last step showing whether the language model is ready."
            ),
            systemImage: "text.bubble"
          )
        } footer: {
          if SpeechModel.store.awaitingUse != nil || LanguageModel.store.awaitingUse != nil {
            Group {
              if readiness.isReady {
                Text(
                  "Casper switches to each new model once it's downloaded. Downloads continue after setup.",
                  comment: "Note on setup's last step while models download and Casper can already dictate."
                )
              } else {
                Text(
                  "You can dictate once your models are downloaded. Downloads continue after setup.",
                  comment: "Note on setup's last step while the models dictation needs download."
                )
              }
            }
            .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .labelStyle(.settings)
    }
  }

  private var footer: some View {
    HStack {
      Button {
        go(to: Step(rawValue: step.rawValue - 1))
      } label: {
        Text("Back", comment: "Button in setup that returns to the previous step.")
      }
      .opacity(step == .welcome ? 0 : 1)
      .disabled(step == .welcome)
      Spacer()
      Button {
        if step == .dictation {
          finish()
        } else {
          go(to: Step(rawValue: step.rawValue + 1))
        }
      } label: {
        primaryButtonTitle
          .frame(minWidth: 80)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canContinue)
      // Return in the practice field shouldn't end setup.
      .keyboardShortcut(step == .dictation ? nil : .defaultAction)
    }
    .controlSize(.large)
    .overlay { pageIndicator }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }

  private var primaryButtonTitle: Text {
    switch step {
    case .welcome: Text("Get Started", comment: "Button on the first step of setup that starts it.")
    case .dictation: Text("Finish", comment: "Button on the last step of setup that ends it and opens Settings.")
    default: Text("Continue", comment: "Button in setup that goes to the next step.")
    }
  }

  private var pageIndicator: some View {
    HStack(spacing: 6) {
      ForEach(Step.allCases, id: \.self) { page in
        Capsule()
          .fill(page == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
          .frame(width: page == step ? 18 : 7, height: 7)
      }
    }
    .animation(.spring(duration: 0.3), value: step)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "Step \(step.rawValue + 1) of \(Step.allCases.count)",
        comment: "Accessibility label of the dots at the bottom of setup showing how far along it is."
      )
    )
  }

  /// Whether the current step is done, which the next one needs.
  private var canContinue: Bool {
    switch step {
    case .welcome, .dictation:
      true
    case .voiceModel:
      hasChosen(in: SpeechModel.store, activeID: activeSpeechModelID)
    case .languageModel:
      hasChosen(in: LanguageModel.store, activeID: activeLanguageModelID)
    case .permissions:
      // Notifications are only for learned words, so setup asks for them without requiring them.
      permissions.isEverythingAllowed
    }
  }

  /// Whether a model is chosen that is or will be installed, which one whose download failed won't be.
  private func hasChosen<Model>(in store: ModelStore<Model>, activeID: String) -> Bool {
    guard let id = store.chosenID(activeID: activeID) else { return false }
    if case .failed = store.downloads[id] {
      return false
    }
    return true
  }

  private var pageTransition: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .offset(x: isMovingForward ? 40 : -40)),
      removal: .opacity.combined(with: .offset(x: isMovingForward ? -40 : 40))
    )
  }

  private func go(to newStep: Step?) {
    guard let newStep else { return }
    isMovingForward = newStep.rawValue > step.rawValue
    // The outgoing page leaves with the transition it was last drawn with, so it's drawn with the new direction before
    // the step changes.
    Task {
      withAnimation(.smooth(duration: 0.35)) { step = newStep }
    }
  }

  private func finish() {
    hasCompletedSetup = true
    NSApp.openWindowInFront { openSettings() }
    // Closed once Settings is open, since closing Casper's last window would hide its Dock icon and menus.
    Task { dismissWindow(id: Self.windowID) }
  }
}

/// A step of setup: a heading that explains it, above what the step asks of the user.
private struct OnboardingPage<Content: View>: View {
  var systemImage: String?
  let title: Text
  let message: Text
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 28))
            .foregroundStyle(.tint)
            .frame(height: 34)
        }
        title
          .font(.title.weight(.semibold))
        message
          .foregroundStyle(.secondary)
          .frame(maxWidth: 480)
          .fixedSize(horizontal: false, vertical: true)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 40)
      content
    }
    // Clears the window's buttons, which sit over the content in place of a title bar.
    .padding(.top, 34)
  }
}

/// The first step of setup: the ghost, voicing its bars as if it were speaking, and what Casper does.
private struct WelcomePage: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 14) {
      TimelineView(.animation(paused: reduceMotion)) { timeline in
        GhostLogo(barLevels: reduceMotion ? nil : barLevels(at: timeline.date))
          .frame(height: 110)
      }
      .padding(.bottom, 10)
      Text("Welcome to Casper", comment: "Title of the setup window and of its first step.")
        .font(.largeTitle.weight(.semibold))
      Text(
        """
        Dictate into any app on your Mac. Casper turns what you say into clean, polished text, and everything runs \
        locally for maximum privacy.
        """,
        comment: "Explanation on the first step of setup."
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 440)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// The bars rise and fall at their own paces, unhurried like the voice bubble's.
  private func barLevels(at date: Date) -> [Double] {
    let time = date.timeIntervalSinceReferenceDate
    return [(0.9, 0.0), (1.3, 1.7), (1.1, 3.1)]
      .map { speed, phase in
        0.35 + 0.3 * sin(time * speed + phase) * (0.6 + 0.4 * sin(time * speed * 0.37 + phase))
      }
  }
}

/// The model of one kind the user chose in setup, and whether it's ready or still downloading.
private struct ChosenModelStatus<Model: DownloadableModel>: View {
  let kind: Text
  let systemImage: String
  @AppStorage(Model.activeStorageKey) private var activeModelID = ""
  private let store = Model.store

  var body: some View {
    let model = store.chosenID(activeID: activeModelID).flatMap { id in Model.all.first { $0.id == id } }
    LabeledContent {
      if let model {
        ModelDownloadStatus(model: model) {
          Label("Ready", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }
    } label: {
      Label {
        kind
        if let model {
          Text(model.title)
        }
      } icon: {
        Image(systemName: systemImage)
      }
    }
  }
}

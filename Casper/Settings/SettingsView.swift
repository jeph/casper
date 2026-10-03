import SwiftUI

struct SettingsView: View {
  @Environment(SettingsNavigation.self) private var navigation
  @Environment(DictationReadiness.self) private var readiness
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale
  @AppStorage(SettingsPane.advancedEnabledStorageKey) private var showsAdvancedSettings = false

  var body: some View {
    @Bindable var navigation = navigation
    TabView(selection: $navigation.pane) {
      ForEach(SettingsPane.allCases.filter { $0 != .advanced || showsAdvancedSettings }) { pane in
        Tab(value: pane) {
          page(pane)
        } label: {
          Label {
            Text(pane.title)
          } icon: {
            if readiness.needsAttention(pane) {
              BadgedTabIcon(systemImage: pane.systemImage, colorScheme: colorScheme, displayScale: displayScale)
                .image
            } else {
              Image(systemName: pane.systemImage)
            }
          }
        }
      }
    }
    .frame(width: 680, height: 490)
  }

  @ViewBuilder
  private func page(_ pane: SettingsPane) -> some View {
    switch pane {
    case .general: GeneralView()
    case .refine: RefineView()
    case .history: HistoryView()
    case .dictionary: DictionaryView()
    case .voiceModels: VoiceModelsView()
    case .languageModels: LanguageModelsView()
    case .permissions: PermissionsView()
    case .advanced: AdvancedView()
    }
  }
}

/// The Settings page shown, which other parts of Casper can switch before opening Settings.
@MainActor
@Observable
final class SettingsNavigation {
  var pane = SettingsPane.general
  /// Whether code outside a view asked for Settings to open, which the menu bar icon does, since opening Settings needs
  /// a view's `openSettings` action.
  var isOpenRequested = false

  /// Opens Settings on a page from code that isn't a view, such as a notification's click.
  func open(_ pane: SettingsPane) {
    self.pane = pane
    isOpenRequested = true
  }
}

enum SettingsPane: CaseIterable, Identifiable {
  case general
  case refine
  case dictionary
  case history
  case voiceModels
  case languageModels
  case permissions
  case advanced

  var id: Self { self }

  /// The `UserDefaults` key for whether the Advanced tab is shown, off unless turned on in General.
  static let advancedEnabledStorageKey = "advancedSettingsEnabled"

  var title: LocalizedStringResource {
    switch self {
    case .general: "General"
    case .refine: "Refine"
    case .history: "History"
    case .dictionary: "Dictionary"
    case .voiceModels: "Voice Models"
    case .languageModels: "Language Models"
    case .permissions: "Permissions"
    case .advanced: "Advanced"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .refine: "wand.and.sparkles"
    case .history: "clock.arrow.circlepath"
    case .dictionary: "character.book.closed"
    case .voiceModels: "waveform"
    case .languageModels: "text.bubble"
    case .permissions: "hand.raised"
    case .advanced: "wrench.and.screwdriver"
    }
  }
}

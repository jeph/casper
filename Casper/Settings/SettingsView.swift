import SwiftUI

struct SettingsView: View {
  @Environment(SettingsNavigation.self) private var navigation
  @Environment(DictationReadiness.self) private var readiness
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    @Bindable var navigation = navigation
    TabView(selection: $navigation.pane) {
      ForEach(SettingsPane.allCases) { pane in
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
    .frame(width: 680, height: 460)
  }

  @ViewBuilder
  private func page(_ pane: SettingsPane) -> some View {
    switch pane {
    case .general: GeneralView()
    case .refine: RefineView()
    case .history: HistoryView()
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
}

enum SettingsPane: CaseIterable, Identifiable {
  case general
  case refine
  case history
  case voiceModels
  case languageModels
  case permissions
  case advanced

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .general: "General"
    case .refine: "Refine"
    case .history: "History"
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
    case .voiceModels: "waveform"
    case .languageModels: "text.bubble"
    case .permissions: "hand.raised"
    case .advanced: "wrench.and.screwdriver"
    }
  }
}

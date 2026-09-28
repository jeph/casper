import SwiftUI

struct SettingsView: View {
  @Environment(SettingsNavigation.self) private var navigation
  @Environment(DictationReadiness.self) private var readiness

  var body: some View {
    @Bindable var navigation = navigation
    NavigationSplitView {
      List(SettingsPane.allCases, selection: $navigation.pane) { pane in
        HStack {
          Label {
            Text(pane.title)
          } icon: {
            Image(systemName: pane.systemImage)
          }
          if readiness.needsAttention(pane) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
              .symbolRenderingMode(.multicolor)
              .accessibilityLabel(
                Text(
                  "Needs attention",
                  comment: "Accessibility label of the warning next to a Settings sidebar page that fixes something."
                )
              )
          }
        }
      }
      .navigationSplitViewColumnWidth(180)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      switch navigation.pane {
      case .general:
        GeneralView()
      case .voiceModels:
        VoiceModelsView()
      case .languageModels:
        LanguageModelsView()
      case .permissions:
        PermissionsView()
      case nil:
        EmptyView()
      }
    }
    .frame(width: 680, height: 460)
  }
}

/// The Settings page shown, which other parts of Casper can switch before opening Settings.
@MainActor
@Observable
final class SettingsNavigation {
  var pane: SettingsPane? = .general
}

enum SettingsPane: CaseIterable, Identifiable {
  case general
  case voiceModels
  case languageModels
  case permissions

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .general: "General"
    case .voiceModels: "Voice Models"
    case .languageModels: "Language Models"
    case .permissions: "Permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .voiceModels: "waveform"
    case .languageModels: "text.bubble"
    case .permissions: "hand.raised"
    }
  }
}

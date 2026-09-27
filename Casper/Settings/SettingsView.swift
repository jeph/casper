import SwiftUI

struct SettingsView: View {
  @State private var selection: SettingsPane? = .general

  var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: $selection) { pane in
        Label {
          Text(pane.title)
        } icon: {
          Image(systemName: pane.systemImage)
        }
      }
      .navigationSplitViewColumnWidth(180)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      switch selection {
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

private enum SettingsPane: CaseIterable, Identifiable {
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

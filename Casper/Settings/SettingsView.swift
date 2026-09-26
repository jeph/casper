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
  case permissions

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .general: "General"
    case .permissions: "Permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .permissions: "hand.raised"
    }
  }
}

import SwiftUI

struct SettingsView: View {
  @State private var selection: SettingsPane? = .permissions

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
  case permissions

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .permissions: "Permissions"
    }
  }

  var systemImage: String {
    switch self {
    case .permissions: "hand.raised"
    }
  }
}

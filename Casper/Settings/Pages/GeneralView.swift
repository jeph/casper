import AppKit
import ServiceManagement
import SwiftUI

struct GeneralView: View {
  @State private var launchAtLoginStatus = LaunchAtLogin.status
  @AppStorage(Hotkey.dictationStorageKey) private var dictationHotkey = Hotkey.dictationDefault

  var body: some View {
    Form {
      Section {
        InputDevicePicker {
          Label {
            Text("Input Device")
            Text("The microphone Casper listens to when you dictate.")
          } icon: {
            Image(systemName: "mic")
          }
        }
      }
      Section {
        Toggle(isOn: launchAtLogin) {
          Label {
            Text("Start at Login")
            Text("Open Casper automatically when you log in to your Mac.")
          } icon: {
            Image(systemName: "power")
          }
        }
        if launchAtLoginStatus == .requiresApproval {
          LabeledContent {
            Button("Open Login Items") {
              SMAppService.openSystemSettingsLoginItems()
            }
          } label: {
            Text("Casper is turned off in Login Items in System Settings.")
              .foregroundStyle(.secondary)
          }
        }
      }
      Section {
        LabeledContent {
          HStack {
            if dictationHotkey != .dictationDefault {
              Button("Reset to Default", systemImage: "arrow.counterclockwise") {
                dictationHotkey = .dictationDefault
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .help(Text("Reset to Default"))
            }
            HotkeyRecorder(hotkey: $dictationHotkey)
          }
        } label: {
          Label {
            Text("Dictation Shortcut")
            Text("The shortcut used to start dictation.")
          } icon: {
            Image(systemName: "keyboard")
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("General"))
    // The user may change Login Items in System Settings while this pane is open.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      launchAtLoginStatus = LaunchAtLogin.status
    }
  }

  private var launchAtLogin: Binding<Bool> {
    Binding {
      launchAtLoginStatus.isRegistered
    } set: { enabled in
      LaunchAtLogin.setEnabled(enabled)
      launchAtLoginStatus = LaunchAtLogin.status
    }
  }
}

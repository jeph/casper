import AVFoundation
import AppKit
import SwiftUI

struct PermissionsView: View {
  @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

  var body: some View {
    Form {
      Section {
        LabeledContent {
          microphoneControl
        } label: {
          Label {
            Text("Microphone")
            Text("Casper uses the microphone to hear what you dictate.")
          } icon: {
            Image(systemName: "mic")
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Permissions"))
    // The user may change access in System Settings while this pane is open.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
  }

  @ViewBuilder
  private var microphoneControl: some View {
    switch microphoneStatus {
    case .authorized:
      Label("Allowed", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .notDetermined:
      Button("Allow Access") {
        Task {
          await AVCaptureDevice.requestAccess(for: .audio)
          microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
      }
    case .restricted:
      Text("Blocked by a device policy")
        .foregroundStyle(.secondary)
    case .denied:
      openSystemSettingsButton
    @unknown default:
      openSystemSettingsButton
    }
  }

  private var openSystemSettingsButton: some View {
    Button("Open System Settings") {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}

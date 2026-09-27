import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

struct PermissionsView: View {
  @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
  @State private var isAccessibilityTrusted = AXIsProcessTrusted()

  var body: some View {
    Form {
      Section {
        LabeledContent {
          // Stacked so the outgoing button and the incoming status overlap while they crossfade.
          ZStack(alignment: .trailing) {
            microphoneControl
              .transition(Self.statusTransition)
          }
          .animation(.easeInOut(duration: 0.2), value: microphoneStatus)
        } label: {
          Label {
            Text("Microphone")
            Text("Casper uses the microphone to hear what you dictate.")
          } icon: {
            Image(systemName: "mic")
          }
        }
        LabeledContent {
          ZStack(alignment: .trailing) {
            accessibilityControl
              .transition(Self.statusTransition)
          }
          .animation(.easeInOut(duration: 0.2), value: isAccessibilityTrusted)
        } label: {
          Label {
            Text("Accessibility")
            Text("Casper uses accessibility to type what you dictate into other apps.")
          } icon: {
            Image(systemName: "accessibility")
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Permissions"))
    // The user may change access in System Settings while this pane is open.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshStatus()
    }
    // macOS doesn't tell Casper when access is granted in System Settings, so check until everything is allowed,
    // rather than waiting for the user to come back to Casper.
    .task(id: isEverythingAllowed) {
      guard !isEverythingAllowed else { return }
      while (try? await Task.sleep(for: .milliseconds(500))) != nil {
        refreshStatus()
      }
    }
  }

  /// Slides a control in from the left and out to the right while fading it, the way the Voice Models page's
  /// controls glide when switching models.
  private static let statusTransition = AnyTransition.asymmetric(
    insertion: .opacity.combined(with: .offset(x: -20)),
    removal: .opacity.combined(with: .offset(x: 20))
  )

  private var isEverythingAllowed: Bool { microphoneStatus == .authorized && isAccessibilityTrusted }

  private func refreshStatus() {
    microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    isAccessibilityTrusted = AXIsProcessTrusted()
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

  @ViewBuilder
  private var accessibilityControl: some View {
    if isAccessibilityTrusted {
      Label("Allowed", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else {
      Button("Allow Access") {
        // Shows the system prompt that adds Casper to Accessibility in System Settings. The literal is the value of
        // `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a global mutable variable.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      }
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

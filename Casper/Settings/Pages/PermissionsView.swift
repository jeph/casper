import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

struct PermissionsView: View {
  @Environment(Permissions.self) private var permissions

  var body: some View {
    Form {
      Section {
        LabeledContent {
          // Stacked so the outgoing button and the incoming status overlap while they crossfade.
          ZStack(alignment: .trailing) {
            microphoneControl
              .transition(Self.statusTransition)
          }
          .animation(.easeInOut(duration: 0.2), value: permissions.microphone)
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
          .animation(.easeInOut(duration: 0.2), value: permissions.isAccessibilityTrusted)
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
  }

  /// Slides a control in from the left and out to the right while fading it, the way the Voice Models page's
  /// controls glide when switching models.
  private static let statusTransition = AnyTransition.asymmetric(
    insertion: .opacity.combined(with: .offset(x: -20)),
    removal: .opacity.combined(with: .offset(x: 20))
  )

  @ViewBuilder
  private var microphoneControl: some View {
    switch permissions.microphone {
    case .authorized:
      Label("Allowed", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .notDetermined:
      Button("Allow Access") {
        Task {
          await AVCaptureDevice.requestAccess(for: .audio)
          permissions.refresh()
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
    if permissions.isAccessibilityTrusted {
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

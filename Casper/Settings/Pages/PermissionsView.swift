import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

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
          .labelStyle(.settings)
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
          .labelStyle(.settings)
        }
      }
      // Dictation works without notifications, so they're apart from the access it needs.
      Section {
        LabeledContent {
          ZStack(alignment: .trailing) {
            notificationsControl
              .transition(Self.statusTransition)
          }
          .animation(.easeInOut(duration: 0.2), value: permissions.notifications)
        } label: {
          Label {
            Text("Notifications")
            Text("Casper tells you when it adds a word to the dictionary from your corrections.")
          } icon: {
            Image(systemName: "bell")
          }
          .labelStyle(.settings)
        }
      }
    }
    .formStyle(.grouped)
    .task { await permissions.watch() }
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
      openSystemSettingsButton(pane: "com.apple.preference.security?Privacy_Microphone")
    @unknown default:
      openSystemSettingsButton(pane: "com.apple.preference.security?Privacy_Microphone")
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

  /// Nothing until macOS has said whether notifications are allowed, since a button that turns into "Allowed" a moment
  /// later would flicker.
  @ViewBuilder
  private var notificationsControl: some View {
    if let status = permissions.notifications {
      switch status {
      case .authorized, .provisional:
        Label("Allowed", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case .notDetermined:
        Button("Allow Notifications") {
          Task {
            // Banners only, as `LearnedWordNotifier` asks: Casper never plays a sound.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            await permissions.refreshNotifications()
          }
        }
      case .denied:
        openSystemSettingsButton(pane: Self.notificationsPane)
      @unknown default:
        openSystemSettingsButton(pane: Self.notificationsPane)
      }
    }
  }

  /// Casper's own pane in System Settings > Notifications.
  private static var notificationsPane: String {
    "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
  }

  /// Opens a pane of System Settings, such as `com.apple.preference.security?Privacy_Microphone`.
  private func openSystemSettingsButton(pane: String) -> some View {
    Button("Open System Settings") {
      if let url = URL(string: "x-apple.systempreferences:\(pane)") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}

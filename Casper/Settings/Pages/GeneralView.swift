import AppKit
import ServiceManagement
import SwiftUI

struct GeneralView: View {
  @State private var launchAtLoginStatus = LaunchAtLogin.status
  @AppStorage(DictationMode.storageKey) private var dictationMode = DictationMode.defaultValue
  @AppStorage(VoiceBubble.visibleStorageKey) private var showsVoiceBubble = true
  @AppStorage(VoiceBubble.sizeStorageKey) private var voiceBubbleSize = VoiceBubbleMetrics.defaultSize
  @AppStorage(SettingsPane.advancedEnabledStorageKey) private var showsAdvancedSettings = false

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
        DictationShortcutRow()
        Picker(selection: $dictationMode) {
          ForEach(DictationMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        } label: {
          Label {
            Text("Shortcut Mode")
            Text(dictationMode.explanation)
          } icon: {
            Image(systemName: "hand.tap")
          }
        }
      }
      Section {
        KeepAlivePicker(storageKey: KeepAlive.microphoneStorageKey) {
          Label {
            Text("Keep Microphone On")
            Text("How long the mic stays on after your last dictation. Mic reactivation adds a recording delay.")
          } icon: {
            Image(systemName: "timer")
          }
        }
      }
      Section {
        Toggle(isOn: $showsVoiceBubble) {
          Label {
            Text("Show Voice Bubble")
            Text("A bubble on screen that shows when Casper is listening. Drag it to move it.")
          } icon: {
            Image(systemName: "waveform.circle")
          }
        }
        LabeledContent {
          Slider(value: voiceBubbleSizeValue, in: sizeRange, step: 1) {
            Text("Voice Bubble Size")
          } minimumValueLabel: {
            GhostLogo()
              .frame(height: 9)
              .foregroundStyle(.secondary)
          } maximumValueLabel: {
            GhostLogo()
              .frame(height: 15)
              .foregroundStyle(.secondary)
          }
          .labelsHidden()
          .frame(width: 180)
        } label: {
          Label {
            Text("Voice Bubble Size")
            Text("How large the voice bubble is on screen.")
          } icon: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
          }
        }
        .disabled(!showsVoiceBubble)
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
        Toggle(isOn: $showsAdvancedSettings) {
          Label {
            Text("Show Advanced Settings")
          } icon: {
            Image(systemName: "wrench.and.screwdriver")
          }
        }
      }
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
    // The user may change Login Items in System Settings while this pane is open.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      launchAtLoginStatus = LaunchAtLogin.status
    }
  }

  private var sizeRange: ClosedRange<Double> {
    Double(VoiceBubbleMetrics.sizes.lowerBound)...Double(VoiceBubbleMetrics.sizes.upperBound)
  }

  private var voiceBubbleSizeValue: Binding<Double> {
    Binding {
      Double(voiceBubbleSize)
    } set: { value in
      voiceBubbleSize = Int(value.rounded())
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

import AVFoundation
import AppKit
import ApplicationServices
import Observation

/// Whether Casper has the access dictation needs: the microphone to hear the user, and Accessibility to type.
///
/// macOS doesn't tell Casper when access changes in System Settings, so while anything is missing this checks every
/// second. Once everything is allowed, it checks again when Casper becomes active or the dictation hotkey is pressed,
/// which is when access turned off since would matter, and every second while a view showing access runs `watch()`.
@MainActor
@Observable
final class Permissions {
  private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
  private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
  @ObservationIgnored private var polling: Task<Void, Never>?

  init() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    pollWhileMissing()
  }

  var isMicrophoneAllowed: Bool { microphone == .authorized }
  var isEverythingAllowed: Bool { isMicrophoneAllowed && isAccessibilityTrusted }

  func refresh() {
    // Assigning an unchanged value would still redraw every view that shows it.
    let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    if microphone != self.microphone {
      self.microphone = microphone
    }
    let isAccessibilityTrusted = AXIsProcessTrusted()
    if isAccessibilityTrusted != self.isAccessibilityTrusted {
      self.isAccessibilityTrusted = isAccessibilityTrusted
    }
    pollWhileMissing()
  }

  /// Checks every second until cancelled, so a view showing access follows it being turned off in System Settings while
  /// Casper stays in the background.
  func watch() async {
    repeat {
      refresh()
    } while (try? await Task.sleep(for: .seconds(1))) != nil
  }

  private func pollWhileMissing() {
    guard !isEverythingAllowed, polling == nil else { return }
    polling = Task { [weak self] in
      while (try? await Task.sleep(for: .seconds(1))) != nil {
        guard let self else { return }
        refresh()
        if isEverythingAllowed {
          polling = nil
          return
        }
      }
    }
  }
}

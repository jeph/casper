import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that shows a hotkey and, when clicked, records the next key combination as the new hotkey.
///
/// While recording, Escape cancels and the modifier keys being held are shown. Key presses in the recorder's window
/// are consumed, so a combination like ⌘Q is recorded instead of quitting the app. Recording stops when that window
/// stops being the key window, so key presses meant for Casper's other windows reach them.
struct HotkeyRecorder: View {
  @Binding var hotkey: Hotkey
  @State private var isRecording = false
  @State private var heldModifiers: NSEvent.ModifierFlags = []
  @State private var eventMonitor: Any?
  @State private var recordingWindow: ObjectIdentifier?

  var body: some View {
    Button {
      if isRecording {
        stopRecording()
      } else {
        startRecording()
      }
    } label: {
      Text(label)
        .foregroundStyle(isRecording ? .secondary : .primary)
        .frame(minWidth: 110)
    }
    .accessibilityValue(Text(hotkey.displayName))
    .onDisappear(perform: stopRecording)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
      stopRecording()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
      if isRecording, (notification.object as AnyObject?).map(ObjectIdentifier.init) == recordingWindow {
        stopRecording()
      }
    }
  }

  private var label: String {
    guard isRecording else { return hotkey.displayName }
    guard heldModifiers.isEmpty else { return Hotkey.symbols(for: heldModifiers) }
    return String(localized: "Type Shortcut", comment: "Placeholder in the shortcut field while it waits for a key.")
  }

  private func startRecording() {
    isRecording = true
    // The click that started recording made the recorder's window the key window.
    recordingWindow = NSApp.keyWindow.map(ObjectIdentifier.init)
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      guard event.window.map(ObjectIdentifier.init) == recordingWindow else {
        stopRecording()
        return event
      }
      record(event)
      return nil
    }
  }

  private func record(_ event: NSEvent) {
    if event.type == .flagsChanged {
      heldModifiers = event.modifierFlags.intersection(Hotkey.supportedModifiers)
      return
    }
    guard !event.isARepeat else { return }
    let modifiers = event.modifierFlags.intersection(Hotkey.supportedModifiers)
    if event.keyCode == kVK_Escape && modifiers.isEmpty {
      stopRecording()
    } else if let recorded = Hotkey(event: event) {
      hotkey = recorded
      stopRecording()
    } else {
      NSSound.beep()
    }
  }

  private func stopRecording() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
    eventMonitor = nil
    isRecording = false
    recordingWindow = nil
    heldModifiers = []
  }
}

import AppKit
import Carbon.HIToolbox
import OSLog

/// Reports when the dictation hotkey is pressed and released, whichever app is in front.
///
/// Carbon hot keys need neither Input Monitoring nor Accessibility permission. macOS delivers the key presses to
/// Casper instead of the frontmost app. The hotkey is registered again whenever it's changed in Settings.
@MainActor
final class GlobalHotkey {
  private let onPress: () -> Void
  private let onRelease: () -> Void
  private var registered: Hotkey?
  private var hotKeyRef: EventHotKeyRef?

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "GlobalHotkey")
  /// The four-character code "CSPR", which identifies Casper's hot keys to Carbon.
  private static let signature: OSType = 0x4353_5052

  init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
    self.onPress = onPress
    self.onRelease = onRelease
    let eventTypes = [
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    // Casper keeps one instance for its whole run, so the handler is never removed and can hold it unretained.
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      Self.handleEvent,
      eventTypes.count,
      eventTypes,
      Unmanaged.passUnretained(self).toOpaque(),
      nil
    )
    if status != noErr {
      Self.logger.error("Couldn't install the hotkey handler: \(status)")
    }
    registerStoredHotkey()
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.registerStoredHotkey() }
    }
  }

  private static let handleEvent: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let address = Int(bitPattern: userData)
    // Carbon calls event handlers on the main thread.
    MainActor.assumeIsolated {
      guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
      let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
      if isPress {
        hotkey.onPress()
      } else {
        hotkey.onRelease()
      }
    }
    return noErr
  }

  private func registerStoredHotkey() {
    let hotkey =
      UserDefaults.standard.string(forKey: Hotkey.dictationStorageKey).flatMap(Hotkey.init(rawValue:))
      ?? .dictationDefault
    guard hotkey != registered else { return }
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    registered = hotkey
    let status = RegisterEventHotKey(
      UInt32(hotkey.keyCode),
      Self.carbonModifiers(hotkey.modifiers),
      EventHotKeyID(signature: Self.signature, id: 1),
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    if status != noErr {
      // Another app has most likely registered the same shortcut.
      Self.logger.error("Couldn't register the dictation hotkey \(hotkey.rawValue): \(status)")
    }
  }

  private static func carbonModifiers(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
    [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
      .filter { modifiers.contains($0.0) }
      .reduce(0) { $0 | UInt32($1.1) }
  }
}

import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: one key plus modifier keys.
struct Hotkey: Equatable, Sendable {
  /// The `UserDefaults` key the dictation hotkey is stored under.
  static let dictationStorageKey = "dictationHotkey"
  static let dictationDefault = Hotkey(keyCode: UInt16(kVK_Space), modifiers: .option)

  /// The modifier keys a hotkey can use; other flags, such as Caps Lock, are ignored.
  static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

  /// The key's virtual key code, one of the `kVK_` constants, which names a physical key in any keyboard layout.
  let keyCode: UInt16
  let modifiers: NSEvent.ModifierFlags

  init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    self.keyCode = keyCode
    self.modifiers = modifiers.intersection(Self.supportedModifiers)
  }

  /// Creates a hotkey from a key press, or returns `nil` if the combination would get in the way of normal typing.
  ///
  /// A hotkey needs Command, Option, or Control, because Shift alone changes what a key types. Function keys work
  /// on their own.
  init?(event: NSEvent) {
    self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    guard !modifiers.isDisjoint(with: [.command, .option, .control]) || Self.functionKeys[Int(keyCode)] != nil else {
      return nil
    }
  }

  /// The shortcut as macOS shows it in menus, for example "⌥Space".
  @MainActor var displayName: String { Self.symbols(for: modifiers) + keyName }

  /// Modifier symbols in the order macOS menus use.
  static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
    [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
      .filter { modifiers.contains($0.0) }
      .map(\.1)
      .joined()
  }

  @MainActor private var keyName: String {
    let key = Int(keyCode)
    if key == kVK_Space {
      return String(localized: "Space", comment: "Name of the Space bar in a keyboard shortcut, as in ⌥Space.")
    }
    if let symbol = Self.keySymbols[key] {
      return symbol
    }
    if let number = Self.functionKeys[key] {
      return "F\(number)"
    }
    return Self.characterInCurrentLayout(keyCode)?.uppercased()
      ?? String(localized: "Key \(keyCode)", comment: "Fallback name for a key with no printable character.")
  }

  private static let keySymbols = [
    kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
  ]

  private static let functionKeys = [
    kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10,
    kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15, kVK_F16: 16, kVK_F17: 17, kVK_F18: 18,
    kVK_F19: 19, kVK_F20: 20,
  ]

  /// The character the key types in the user's current keyboard layout, so a key shows as "Z" on QWERTZ too.
  @MainActor private static func characterInCurrentLayout(_ keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var characters = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = data.withUnsafeBytes { bytes in
      UCKeyTranslate(
        bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysMask),
        &deadKeyState,
        characters.count,
        &length,
        &characters
      )
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
  }
}

extension Hotkey: RawRepresentable {
  /// Reads the stored form "keyCode:modifiers", for example "49:524288" for ⌥Space.
  init?(rawValue: String) {
    let parts = rawValue.split(separator: ":")
    guard parts.count == 2, let keyCode = UInt16(parts[0]), let modifiers = UInt(parts[1]) else { return nil }
    self.init(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
  }

  var rawValue: String { "\(keyCode):\(modifiers.rawValue)" }
}

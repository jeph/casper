import SwiftUI

/// The Dictation Shortcut setting: the shortcut, which a click records anew, and a button that resets it once changed.
struct DictationShortcutRow: View {
  @AppStorage(Hotkey.dictationStorageKey) private var dictationHotkey = Hotkey.dictationDefault

  var body: some View {
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

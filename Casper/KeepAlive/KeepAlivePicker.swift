import SwiftUI

/// Chooses how long something dictation needs stays ready after the last dictation.
struct KeepAlivePicker<Label: View>: View {
  @AppStorage private var setting: KeepAlive
  private let label: Label

  /// Creates a picker for the keep-alive setting stored under `storageKey`.
  init(storageKey: String, @ViewBuilder label: () -> Label) {
    _setting = AppStorage(wrappedValue: KeepAlive.defaultValue, storageKey)
    self.label = label()
  }

  var body: some View {
    Picker(selection: $setting) {
      ForEach(KeepAlive.allCases) { option in
        Text(option.title).tag(option)
      }
    } label: {
      label
    }
  }
}

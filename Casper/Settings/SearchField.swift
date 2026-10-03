import AppKit
import SwiftUI

/// AppKit's search field, for searching within a Settings page.
///
/// `.searchable` puts its field in the window's toolbar, which in the Settings window holds the page tabs, and the
/// page goes blank there.
struct SearchField: NSViewRepresentable {
  @Binding var text: String
  let prompt: String

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    field.placeholderString = prompt
    if field.stringValue != text {
      field.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    private let text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      text.wrappedValue = field.stringValue
    }
  }
}

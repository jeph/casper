import AppKit
import SwiftUI

extension View {
  /// Stops the list this is applied to from drawing its own selection highlight, so rows can draw one that looks the
  /// same whether or not the list has keyboard focus.
  ///
  /// A Mac list highlights selected rows in the accent color while it has focus and in gray once focus moves elsewhere,
  /// such as to a search field, and SwiftUI has no way to choose one.
  func systemSelectionHighlightHidden() -> some View {
    background(SelectionHighlightRemover())
  }
}

/// Finds the table that draws a SwiftUI list and turns off its selection highlight.
private struct SelectionHighlightRemover: NSViewRepresentable {
  func makeNSView(context: Context) -> Marker {
    Marker()
  }

  func updateNSView(_ view: Marker, context: Context) {}

  final class Marker: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // The list's table joins the window alongside this view, so it's looked for once both are in place.
      DispatchQueue.main.async { [weak self] in
        self?.nearestTable()?.selectionHighlightStyle = .none
      }
    }

    /// The table in the closest ancestor that has one, which is the list this view is the background of.
    private func nearestTable() -> NSTableView? {
      var ancestor = superview
      while let view = ancestor {
        if let table = Self.table(in: view) {
          return table
        }
        ancestor = view.superview
      }
      return nil
    }

    private static func table(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView {
        return table
      }
      return view.subviews.lazy.compactMap(table(in:)).first
    }
  }
}

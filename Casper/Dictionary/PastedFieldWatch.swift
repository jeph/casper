import ApplicationServices

/// Follows the text field Casper pasted into, through Accessibility, until the user is done editing it.
///
/// The watch only reads: it never sets an attribute of the other app's elements, so it can't change how that app
/// behaves. It ends when focus leaves the field, the field is emptied (a sent message) or closed, its time is up, or
/// the task waiting on it is cancelled, such as by the next paste.
@MainActor
final class PastedFieldWatch {
  /// How long a slow app may take to answer an Accessibility request before the watch gives up on it, so a hung app
  /// can't hold up Casper's main thread.
  private static let messagingTimeout: Float = 0.5

  private let field: AXUIElement
  private let observer: AXObserver
  /// The field's text when last read while it still held text.
  private var latestText: String
  private var isEnded = false
  private var waiting: CheckedContinuation<String, Never>?

  /// Starts watching the focused element of the app with this process ID, if it's a text field that holds the pasted
  /// text.
  init?(processID: pid_t, pasted: String) {
    let app = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    // The type ID check makes the cast safe; Core Foundation types can't be cast conditionally.
    let field = unsafeDowncast(focused, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(field, Self.messagingTimeout)
    let pasted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let text = Self.text(of: field), text.contains(pasted) else { return nil }

    var observer: AXObserver?
    let callback: AXObserverCallback = { _, _, notification, refcon in
      guard let refcon else { return }
      // Accessibility calls back on the run loop the observer was added to, which is the main one.
      MainActor.assumeIsolated {
        Unmanaged<PastedFieldWatch>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String)
      }
    }
    guard AXObserverCreate(processID, callback, &observer) == .success, let observer else { return nil }
    self.field = field
    self.observer = observer
    latestText = text

    let refcon = Unmanaged.passUnretained(self).toOpaque()
    for notification in [kAXValueChangedNotification, kAXUIElementDestroyedNotification] {
      AXObserverAddNotification(observer, field, notification as CFString, refcon)
    }
    AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString, refcon)
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
  }

  /// Waits for the watch to end and returns the field's last text.
  ///
  /// Cancelling the waiting task ends the watch.
  func edited(within limit: Duration) async -> String {
    let timeout = Task { [weak self] in
      try? await Task.sleep(for: limit)
      self?.end(readingAgain: true)
    }
    defer { timeout.cancel() }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !isEnded else {
          continuation.resume(returning: latestText)
          return
        }
        waiting = continuation
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.end(readingAgain: true) }
    }
  }

  private func handle(_ notification: String) {
    switch notification {
    case kAXValueChangedNotification:
      guard let text = Self.text(of: field) else { return }
      // An emptied field, such as a chat message that was sent, is done with.
      guard !text.isEmpty else {
        end(readingAgain: false)
        return
      }
      latestText = text
    case kAXUIElementDestroyedNotification:
      end(readingAgain: false)
    default:
      end(readingAgain: true)
    }
  }

  /// Stops observing, reading the field once more unless it's gone or empty, since some apps don't report every
  /// change.
  private func end(readingAgain: Bool) {
    guard !isEnded else { return }
    isEnded = true
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    if readingAgain, let text = Self.text(of: field), !text.isEmpty {
      latestText = text
    }
    waiting?.resume(returning: latestText)
    waiting = nil
  }

  /// The element's text, or `nil` if it has none Accessibility can read, as with password fields.
  private static func text(of element: AXUIElement) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }
}

import ApplicationServices

/// Follows the text field Casper pasted into, through Accessibility, reporting its text each time the user pauses
/// after changing it.
///
/// The watch only reads: it never sets an attribute of the other app's elements, so it can't change how that app
/// behaves. It carries on when focus moves elsewhere, so a fix made after the user comes back to the field still
/// counts. It ends when the field changes while it doesn't have focus, which is the app reusing it for other content,
/// such as Notes showing another note, rather than the user typing. It also ends when the field is emptied (a sent
/// message) or closed, when Casper pastes into it again, or when its time is up.
@MainActor
final class PastedFieldWatch {
  /// How long a slow app may take to answer an Accessibility request before the watch gives up on it, so a hung app
  /// can't hold up Casper's main thread.
  private static let messagingTimeout: Float = 0.5

  private let app: AXUIElement
  private let field: AXUIElement
  private let observer: AXObserver
  /// The field's text when last read while it still held text.
  private var latestText: String
  /// Whether `latestText` changed since it was last reported.
  private var hasUnreportedChange = false
  private var isEnded = false
  private var reports: AsyncStream<String>.Continuation?
  /// Reports the text once the user has paused for long enough, restarted by every change.
  private var pauseTimer: Task<Void, Never>?
  private var limitTimer: Task<Void, Never>?
  private var pause = Duration.zero

  /// The focused element of the app with this process ID, the field a paste into the app goes to.
  static func focusedField(ofProcess processID: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(app, messagingTimeout)
    return focusedElement(of: app)
  }

  /// Starts watching the field Casper pasted into in the app with this process ID, if it holds the pasted text.
  init?(field: AXUIElement, processID: pid_t, pasted: String) {
    let app = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
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
    self.app = app
    self.field = field
    self.observer = observer
    latestText = text

    let refcon = Unmanaged.passUnretained(self).toOpaque()
    for notification in [kAXValueChangedNotification, kAXUIElementDestroyedNotification] {
      AXObserverAddNotification(observer, field, notification as CFString, refcon)
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
  }

  /// The field's text each time the user pauses after changing it.
  ///
  /// A report comes once the field has gone `pause` without changing, and once more as the watch ends if the text
  /// changed since the last report. The watch ends after `limit` at most.
  ///
  /// Call it once per watch.
  func edits(pause: Duration, limit: Duration) -> AsyncStream<String> {
    self.pause = pause
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    reports = continuation
    limitTimer = Task { [weak self] in
      guard (try? await Task.sleep(for: limit)) != nil else { return }
      self?.end(readingAgain: true)
    }
    return stream
  }

  /// Ends the watch if Casper is pasting into the field it follows, reporting the field as it was before the paste.
  ///
  /// The field isn't read again, since the app may show the pasted text already, which would read as the user's edit.
  /// Returns whether the watch ended.
  func endBeforePaste(into field: AXUIElement) -> Bool {
    guard !isEnded, CFEqual(field, self.field) else { return false }
    end(readingAgain: false)
    return true
  }

  private func handle(_ notification: String) {
    // A field that changes while it doesn't have focus wasn't typed in by the user, but reused by the app.
    guard notification == kAXValueChangedNotification, let focused = Self.focusedElement(of: app),
      CFEqual(focused, field)
    else {
      end(readingAgain: false)
      return
    }
    guard let text = Self.text(of: field) else { return }
    // An emptied field, such as a chat message that was sent, is done with.
    guard !text.isEmpty else {
      end(readingAgain: false)
      return
    }
    changed(to: text)
  }

  private func changed(to text: String) {
    guard text != latestText else { return }
    latestText = text
    hasUnreportedChange = true
    pauseTimer?.cancel()
    pauseTimer = Task { [weak self, pause] in
      guard (try? await Task.sleep(for: pause)) != nil else { return }
      self?.report()
    }
  }

  private func report() {
    guard hasUnreportedChange else { return }
    hasUnreportedChange = false
    reports?.yield(latestText)
  }

  /// Stops observing and reports the last change, reading the field once more unless it's gone or empty, since some
  /// apps don't report every change.
  private func end(readingAgain: Bool) {
    guard !isEnded else { return }
    isEnded = true
    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    pauseTimer?.cancel()
    limitTimer?.cancel()
    if readingAgain, let text = Self.text(of: field), !text.isEmpty, text != latestText {
      latestText = text
      hasUnreportedChange = true
    }
    report()
    reports?.finish()
    reports = nil
  }

  /// The app's focused element, the one keystrokes go to even while the app is in the background.
  private static func focusedElement(of app: AXUIElement) -> AXUIElement? {
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    // The type ID check makes the cast safe; Core Foundation types can't be cast conditionally.
    return unsafeDowncast(focused, to: AXUIElement.self)
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

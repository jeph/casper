import AppKit
import SwiftUI

/// Shows the voice bubble in a floating panel above other windows, on every Space, while the setting is on.
///
/// The panel never becomes key or activates Casper, so dictation keeps typing into the app in front, including while
/// the bubble is dragged. Its position is saved as the ghost's center and kept on screen.
@MainActor
final class VoiceBubble {
  /// The `UserDefaults` key for whether the voice bubble is shown, on unless turned off.
  static let visibleStorageKey = "showsVoiceBubble"
  private static let centerStorageKey = "voiceBubbleCenter"

  private let panel: VoiceBubblePanel
  private let placement = VoiceBubblePlacement()

  init(status: DictationStatus) {
    panel = VoiceBubblePanel(size: VoiceBubbleView.panelSize)
    let hostingView = NSHostingView(rootView: VoiceBubbleView(status: status, placement: placement))
    // The panel keeps its size as the bubble grows and shrinks inside it.
    hostingView.sizingOptions = []
    panel.contentView = hostingView
    move(toCenter: UserDefaults.standard.string(forKey: Self.centerStorageKey).map(NSPointFromString))
    let center = NotificationCenter.default
    center.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.panelMoved() }
    }
    center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.move(toCenter: self?.ghostCenter) }
    }
    center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.updateVisibility() }
    }
    updateVisibility()
  }

  private func updateVisibility() {
    let isVisible = UserDefaults.standard.object(forKey: Self.visibleStorageKey) as? Bool ?? true
    guard isVisible != panel.isVisible else { return }
    if isVisible {
      panel.orderFrontRegardless()
    } else {
      panel.orderOut(nil)
    }
  }

  private var ghostCenter: NSPoint { NSPoint(x: panel.frame.midX, y: panel.frame.midY) }

  /// Keeps the ghost on screen after a drag, and saves where it is.
  private func panelMoved() {
    let center = ghostCenter
    move(toCenter: center)
    UserDefaults.standard.set(NSStringFromPoint(ghostCenter), forKey: Self.centerStorageKey)
  }

  /// Puts the ghost's center at the given point, pulled onto the nearest screen, or at the bottom center of the main
  /// screen when there's no point.
  private func move(toCenter requested: NSPoint?) {
    guard let screen = requested.flatMap(Self.nearestScreen) ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let radius = VoiceBubbleView.diameter / 2
    let center = requested ?? NSPoint(x: visible.midX, y: visible.minY + radius + 24)
    let clamped = NSPoint(
      x: min(max(center.x, visible.minX + radius), visible.maxX - radius),
      y: min(max(center.y, visible.minY + radius), visible.maxY - radius)
    )
    // The grown bubble reaches right of the ghost; past the screen's edge, it slides back by the difference.
    placement.recordingShift = max(clamped.x + VoiceBubbleView.reach - visible.maxX, 0)
    let size = VoiceBubbleView.panelSize
    let frame = NSRect(
      x: clamped.x - size.width / 2,
      y: clamped.y - size.height / 2,
      width: size.width,
      height: size.height
    )
    if frame != panel.frame {
      panel.setFrame(frame, display: true)
    }
  }

  private static func nearestScreen(to point: NSPoint) -> NSScreen? {
    NSScreen.screens.min { distance(from: point, to: $0.visibleFrame) < distance(from: point, to: $1.visibleFrame) }
  }

  private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
    hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
  }
}

/// A borderless, transparent panel that floats above other windows without ever taking focus, and moves when dragged.
private final class VoiceBubblePanel: NSPanel {
  init(size: CGSize) {
    super
      .init(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    backgroundColor = .clear
    isOpaque = false
    // The bubble draws its own shadow; a window shadow would outline the whole transparent panel.
    hasShadow = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// Any press on the bubble drags it; the window server moves the panel, so Casper doesn't activate.
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown {
      performDrag(with: event)
    } else {
      super.sendEvent(event)
    }
  }
}

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
  /// The `UserDefaults` key for the voice bubble's size, one of `VoiceBubbleMetrics.sizes`.
  static let sizeStorageKey = "voiceBubbleSize"
  private static let centerStorageKey = "voiceBubbleCenter"

  private let panel: VoiceBubblePanel
  private let layout = VoiceBubbleLayout(metrics: VoiceBubbleMetrics(size: storedSize))

  init(status: DictationStatus) {
    panel = VoiceBubblePanel(size: layout.metrics.panelSize)
    let hostingView = NSHostingView(rootView: VoiceBubbleView(status: status, layout: layout))
    // The panel keeps its size as the bubble grows and shrinks inside it.
    hostingView.sizingOptions = []
    panel.contentView = hostingView
    move(toCenter: Self.savedCenter)
    panel.onDragEnd = { [weak self] in self?.dragEnded() }
    let center = NotificationCenter.default
    center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.move(toCenter: Self.savedCenter ?? self?.ghostCenter) }
    }
    center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateVisibility()
        self?.updateSize()
      }
    }
    updateVisibility()
  }

  private static var storedSize: Int {
    UserDefaults.standard.object(forKey: sizeStorageKey) as? Int ?? VoiceBubbleMetrics.defaultSize
  }

  /// Where the user last dragged the ghost's center, which may be off screen now; the bubble is placed from here
  /// whenever the screens or its size change, so it returns to that spot when it fits again.
  private static var savedCenter: NSPoint? {
    UserDefaults.standard.string(forKey: centerStorageKey).map(NSPointFromString)
  }

  /// Resizes the bubble when the setting changes, around the ghost's saved center rather than where it was pulled to
  /// fit on screen, so changing the size back puts the bubble back where it was.
  private func updateSize() {
    let metrics = VoiceBubbleMetrics(size: Self.storedSize)
    guard metrics != layout.metrics else { return }
    layout.metrics = metrics
    move(toCenter: Self.savedCenter ?? ghostCenter)
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

  /// Settles the bubble on screen where the user dropped it, and saves that spot.
  ///
  /// This waits for the drag to end, so the bubble follows the pointer freely, including across displays, and only
  /// settles once dropped. Only drags are saved, so moves by the system, such as when a display is disconnected, don't
  /// replace where the user put it.
  private func dragEnded() {
    move(toCenter: ghostCenter)
    UserDefaults.standard.set(NSStringFromPoint(ghostCenter), forKey: Self.centerStorageKey)
  }

  /// Puts the ghost's center at the given point, pulled onto the nearest screen, or at the bottom center of the main
  /// screen when there's no point.
  private func move(toCenter requested: NSPoint?) {
    guard let screen = requested.flatMap(Self.nearestScreen) ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let radius = layout.metrics.diameter / 2
    let center = requested ?? NSPoint(x: visible.midX, y: visible.minY + radius + 24)
    // Sized as when hovered, which grows the bubble, so it stays fully on screen under the pointer too.
    let hoveredRadius = radius * VoiceBubbleMetrics.hoverScale
    let clamped = NSPoint(
      x: min(max(center.x, visible.minX + hoveredRadius), visible.maxX - hoveredRadius),
      y: min(max(center.y, visible.minY + hoveredRadius), visible.maxY - hoveredRadius)
    )
    // The grown bubble reaches right of the ghost, and hovering widens it from its left end; past the screen's edge,
    // it slides back by the difference.
    let hoverScale = VoiceBubbleMetrics.hoverScale
    let hoveredRightEdge = clamped.x - radius + (radius + layout.metrics.reach) * hoverScale
    layout.recordingShift = max(hoveredRightEdge - visible.maxX, 0)
    // The callout goes below the bubble when there's no room above it, and lines up with the ghost's edge rather than
    // its center when centering it would cross the screen's edge.
    layout.showsCalloutBelow = clamped.y + hoveredRadius + VoiceBubbleMetrics.calloutRoom > visible.maxY
    let calloutHalfWidth = VoiceBubbleMetrics.calloutMaxWidth / 2
    layout.calloutAlignment =
      if clamped.x - calloutHalfWidth < visible.minX {
        .leading
      } else if clamped.x + calloutHalfWidth > visible.maxX {
        .trailing
      } else {
        .center
      }
    let size = layout.metrics.panelSize
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

  /// Called when a drag that moved the bubble ends.
  var onDragEnd: (@MainActor () -> Void)?
  /// Where the pointer is from the panel's origin, while a drag is in progress.
  private var dragOffset: NSPoint?
  private var dragStartOrigin = NSPoint.zero

  /// Any press on the bubble drags it, without activating Casper.
  ///
  /// The panel moves itself rather than handing the drag to the window server with `performDrag(with:)`. A window the
  /// window server drags stays on the display the drag started on until it's all the way across, so the bubble
  /// disappeared as it crossed onto the next display.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      let pointer = convertPoint(toScreen: event.locationInWindow)
      dragOffset = NSPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
      dragStartOrigin = frame.origin
    case .leftMouseDragged:
      guard let dragOffset else { return }
      let pointer = convertPoint(toScreen: event.locationInWindow)
      setFrameOrigin(NSPoint(x: pointer.x - dragOffset.x, y: pointer.y - dragOffset.y))
    case .leftMouseUp:
      guard dragOffset != nil else { return }
      dragOffset = nil
      if frame.origin != dragStartOrigin {
        onDragEnd?()
      }
    default:
      super.sendEvent(event)
    }
  }
}

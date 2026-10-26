import AppKit
import IOKit.pwr_mgt

/// Finds the app a screen shows in full screen and whether it's playing video, so the voice bubble can stay out of the
/// way of full-screen video but not of a full-screen terminal or editor.
///
/// An app counts as full screen when it's alone in the current Space of the screen's display, a native full-screen
/// Space; apps side by side in Split View don't count. An app counts as playing video while it keeps the display
/// awake, which browsers and video players do only while video plays.
///
/// macOS has no public way to read another app's Spaces, so this uses the window server's private
/// `CGSCopyManagedDisplaySpaces`, as tiling window managers do. Should a later macOS remove it, no app counts as full
/// screen and the bubble always shows.
enum FullScreenVideo {
  /// The app the screen shows in full screen, alone in its Space.
  @MainActor
  static func app(on screen: NSScreen) -> pid_t? {
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
      let displayUUID = CFUUIDCreateString(nil, uuid) as String?,
      let mainConnection, let copyManagedDisplaySpaces,
      let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
    else { return nil }
    return app(onDisplay: displayUUID, in: displays)
  }

  /// Whether the app keeps the display awake, as apps playing video do.
  static func isPlaying(in app: pid_t) -> Bool {
    var assertionsByProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&assertionsByProcess) == kIOReturnSuccess,
      let assertionsByProcess = assertionsByProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else { return false }
    return keepsDisplayAwake(app, assertions: assertionsByProcess.values.flatMap(\.self))
  }

  /// The app alone in the current Space of a display, from the window server's description of each display's Spaces.
  ///
  /// When "Displays have separate Spaces" is off, all displays share one entry, identified as `Main`.
  static func app(onDisplay displayUUID: String, in displays: [[String: Any]]) -> pid_t? {
    guard
      let display = displays.first(where: { [displayUUID, "Main"].contains($0["Display Identifier"] as? String) }),
      let currentSpaceID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
      let spaces = display["Spaces"] as? [[String: Any]],
      let currentSpace = spaces.first(where: { $0["ManagedSpaceID"] as? Int == currentSpaceID }),
      // Only full-screen Spaces lay out tiles, one for each app, or two in Split View.
      let tiles = (currentSpace["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]],
      tiles.count == 1
    else { return nil }
    return (tiles[0]["pid"] as? NSNumber)?.int32Value
  }

  /// Whether one of the power assertions, as `IOPMCopyAssertionsByProcess` describes them, keeps the display awake for
  /// the app, made either by the app or by another process on its behalf.
  ///
  /// Any process can keep the display awake, as `caffeinate` does, so only the app's own assertions count.
  static func keepsDisplayAwake(_ app: pid_t, assertions: [[String: Any]]) -> Bool {
    assertions.contains { assertion in
      // The true type folds older names, such as the `NoDisplaySleepAssertion` Chrome makes, into the current one.
      guard assertion["AssertionTrueType"] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep,
        assertion["AssertLevel"] as? Int != Int(kIOPMAssertionLevelOff)
      else { return false }
      return [assertion["AssertPID"], assertion["AssertionOnBehalfOfPID"]]
        .contains { ($0 as? NSNumber)?.int32Value == app }
    }
  }

  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

  private static let mainConnection = privateFunction("CGSMainConnectionID", as: MainConnectionID.self)
  private static let copyManagedDisplaySpaces = privateFunction(
    "CGSCopyManagedDisplaySpaces",
    as: CopyManagedDisplaySpaces.self
  )

  private static func privateFunction<Function>(_ name: String, as type: Function.Type) -> Function? {
    dlsym(dlopen(nil, RTLD_NOW), name).map { unsafeBitCast($0, to: type) }
  }
}

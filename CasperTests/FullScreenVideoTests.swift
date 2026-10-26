import Foundation
import Testing

/// The Spaces and power assertions here follow what macOS 27 reports for QuickTime Player, Safari and Chrome playing
/// video in full screen, cut down to the keys that matter.
struct FullScreenVideoTests {
  private static let display = "6BA48C26-AD38-41B1-971F-33E124D1165F"
  private static let otherDisplay = "9C3CC937-130F-4394-A06B-4632C3B7E9C7"
  private static let player: pid_t = 23927
  private static let terminal: pid_t = 4120
  private static let caffeinate: pid_t = 97920

  @Test func findsTheAppAloneInTheDisplaysFullScreenSpace() {
    let displays = [
      Self.display(Self.display, current: 467, spaces: [Self.desktop(1), Self.fullScreen(467, [Self.player])])
    ]
    #expect(FullScreenVideo.app(onDisplay: Self.display, in: displays) == Self.player)
  }

  @Test func ignoresFullScreenSpacesThatArentShowing() {
    let displays = [
      Self.display(Self.display, current: 1, spaces: [Self.desktop(1), Self.fullScreen(467, [Self.player])])
    ]
    #expect(FullScreenVideo.app(onDisplay: Self.display, in: displays) == nil)
  }

  @Test func ignoresFullScreenSpacesOnOtherDisplays() {
    let displays = [
      Self.display(Self.display, current: 1, spaces: [Self.desktop(1)]),
      Self.display(Self.otherDisplay, current: 467, spaces: [Self.fullScreen(467, [Self.player])]),
    ]
    #expect(FullScreenVideo.app(onDisplay: Self.display, in: displays) == nil)
  }

  @Test func ignoresAppsSideBySideInSplitView() {
    let displays = [
      Self.display(Self.display, current: 467, spaces: [Self.fullScreen(467, [Self.player, Self.terminal])])
    ]
    #expect(FullScreenVideo.app(onDisplay: Self.display, in: displays) == nil)
  }

  /// With "Displays have separate Spaces" off, every display shares the Spaces of one entry.
  @Test func findsTheAppWhenDisplaysShareSpaces() {
    let displays = [Self.display("Main", current: 467, spaces: [Self.fullScreen(467, [Self.player])])]
    #expect(FullScreenVideo.app(onDisplay: Self.display, in: displays) == Self.player)
  }

  @Test func appKeepingTheDisplayAwakeIsPlaying() {
    let assertions = [Self.assertion(by: Self.player, type: "PreventUserIdleDisplaySleep")]
    #expect(FullScreenVideo.keepsDisplayAwake(Self.player, assertions: assertions))
  }

  /// Chrome asks under an older name, which the true type gives as the current one.
  @Test func olderNamesForKeepingTheDisplayAwakeCount() {
    var chrome = Self.assertion(by: Self.player, type: "PreventUserIdleDisplaySleep")
    chrome["AssertType"] = "NoDisplaySleepAssertion"
    #expect(FullScreenVideo.keepsDisplayAwake(Self.player, assertions: [chrome]))
  }

  @Test func anotherProcessKeepingTheDisplayAwakeOnTheAppsBehalfCounts() {
    var assertion = Self.assertion(by: 428, type: "PreventUserIdleDisplaySleep")
    assertion["AssertionOnBehalfOfPID"] = Self.player
    #expect(FullScreenVideo.keepsDisplayAwake(Self.player, assertions: [assertion]))
  }

  /// `caffeinate` keeps the display awake for everyone, which says nothing about the full-screen app.
  @Test func otherProcessesKeepingTheDisplayAwakeDontCount() {
    let assertions = [Self.assertion(by: Self.caffeinate, type: "PreventUserIdleDisplaySleep")]
    #expect(!FullScreenVideo.keepsDisplayAwake(Self.terminal, assertions: assertions))
  }

  /// Chrome keeps the Mac awake while it plays audio, which a full-screen app may do without showing video.
  @Test func keepingOnlyTheMacAwakeDoesntCount() {
    let assertions = [Self.assertion(by: Self.player, type: "PreventUserIdleSystemSleep")]
    #expect(!FullScreenVideo.keepsDisplayAwake(Self.player, assertions: assertions))
  }

  @Test func assertionsTurnedOffDontCount() {
    var assertion = Self.assertion(by: Self.player, type: "PreventUserIdleDisplaySleep")
    assertion["AssertLevel"] = 0
    #expect(!FullScreenVideo.keepsDisplayAwake(Self.player, assertions: [assertion]))
  }

  private static func display(_ identifier: String, current: Int, spaces: [[String: Any]]) -> [String: Any] {
    ["Display Identifier": identifier, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
  }

  private static func desktop(_ id: Int) -> [String: Any] {
    ["ManagedSpaceID": id, "type": 0]
  }

  private static func fullScreen(_ id: Int, _ apps: [pid_t]) -> [String: Any] {
    [
      "ManagedSpaceID": id,
      "type": 4,
      "pid": apps[0],
      "TileLayoutManager": ["TileSpaces": apps.map { ["pid": $0, "TileType": "Primary"] }],
    ]
  }

  private static func assertion(by pid: pid_t, type: String) -> [String: Any] {
    ["AssertPID": pid, "AssertionTrueType": type, "AssertType": type, "AssertLevel": 255]
  }
}

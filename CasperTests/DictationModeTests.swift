import Testing

struct DictationModeTests {
  @Test(arguments: DictationMode.allCases)
  func pressWhileIdleStartsRecording(mode: DictationMode) {
    #expect(mode.action(for: .press, isRecording: false, isStopping: false) == .startRecording)
  }

  @Test(arguments: DictationMode.allCases)
  func pressDuringStopTailContinuesRecording(mode: DictationMode) {
    #expect(mode.action(for: .press, isRecording: true, isStopping: true) == .continueRecording)
  }

  /// A press while dictation isn't ready starts nothing, so its release has no recording to stop.
  @Test(arguments: DictationMode.allCases)
  func releaseWithoutRecordingDoesNothing(mode: DictationMode) {
    #expect(mode.action(for: .release, isRecording: false, isStopping: false) == nil)
  }

  @Test func holdStopsOnRelease() {
    #expect(DictationMode.hold.action(for: .release, isRecording: true, isStopping: false) == .stopRecording)
  }

  @Test func holdIgnoresReleaseDuringStopTail() {
    #expect(DictationMode.hold.action(for: .release, isRecording: true, isStopping: true) == nil)
  }

  /// Switching from toggle to hold mid-recording leaves the recording running until the next release.
  @Test func holdIgnoresPressWhileRecording() {
    #expect(DictationMode.hold.action(for: .press, isRecording: true, isStopping: false) == nil)
  }

  @Test func toggleKeepsRecordingOnRelease() {
    #expect(DictationMode.toggle.action(for: .release, isRecording: true, isStopping: false) == nil)
  }

  @Test func toggleStopsOnSecondPress() {
    #expect(DictationMode.toggle.action(for: .press, isRecording: true, isStopping: false) == .stopRecording)
  }
}

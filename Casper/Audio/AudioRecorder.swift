import AVFoundation
import Foundation
import OSLog
import Synchronization

nonisolated private let logger = Logger(subsystem: "io.jeph.Casper", category: "AudioRecorder")

/// Records from the input device chosen in Settings as mono samples at a speech model's sample rate, or from the
/// system default while none is chosen or the chosen one is unplugged.
///
/// The microphone can be turned on before recording and left on between recordings, so a recording starts without
/// waiting for the device to turn on. While the microphone is on and nothing is recording, its audio is discarded.
/// When the device to record from changes, the microphone moves to it right away, and a recording in progress
/// continues on it.
@MainActor
final class AudioRecorder {
  /// The loudness of the recording in progress.
  let meter = AudioLevelMeter()
  private let recording: Recording
  private let microphone: Microphone

  init(sampleRate: Double) {
    recording = Recording(sampleRate: sampleRate, meter: meter)
    microphone = Microphone(recording: recording)
    // Moving as soon as the choice or the connected devices change, rather than at the next recording, keeps an
    // unplugged device from staying selected, and gives a device that's slow to turn on, such as Bluetooth
    // headphones, time to start before the user speaks.
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.updateMicrophoneIfOpen() }
    }
    AudioInputDevices.observeChanges { [weak self] in self?.updateMicrophoneIfOpen() }
  }

  /// Whether the microphone is on, or turning on.
  var isOpen: Bool { microphone.isWanted.withLock { $0 } }
  var isRecording: Bool { recording.isActive }

  /// Turns the microphone on, if it isn't already, without recording.
  func open() {
    microphone.isWanted.withLock { $0 = true }
    updateMicrophone()
  }

  func close() {
    microphone.isWanted.withLock { $0 = false }
    updateMicrophone()
  }

  /// Starts recording, turning the microphone on first if needed.
  ///
  /// This returns without waiting for the microphone, which records from when it's on. A device that couldn't be
  /// turned on is tried again, and again after short delays if it still fails.
  func start() {
    recording.begin()
    microphone.isWanted.withLock { $0 = true }
    Task { [microphone] in await microphone.recordingStarted() }
  }

  /// Stops recording and returns the samples recorded since `start()`, leaving the microphone on.
  func stop() -> [Float] {
    recording.end()
  }

  private func updateMicrophoneIfOpen() {
    if isOpen {
      updateMicrophone()
    }
  }

  private func updateMicrophone() {
    Task { [microphone] in await microphone.update() }
  }
}

/// Keeps a capture session running on the device to record from while the microphone is wanted, sending its audio to
/// the recording.
///
/// A capture session records from only the device it's given. AVAudioEngine, which this replaced, follows the system
/// default input on its own, and turns it on when it changes, which switches Bluetooth headphones to their headset
/// profile and makes them sound like a phone call. A session also converts the device's audio to the recording's
/// format itself, whatever rate the device changes to.
///
/// Turning a session on or off can block for seconds, such as while Bluetooth headphones switch to their headset
/// profile, so it runs on its own queue instead of the main thread, where it would hold up the hotkey and the voice
/// bubble.
private actor Microphone {
  private enum MicrophoneError: Error {
    /// AVFoundation doesn't offer the device for capture, though Core Audio lists it.
    case notCapturable
  }

  /// A running capture session, the device it records from, and what watches it for errors.
  private struct Session {
    let captureSession: AVCaptureSession
    let deviceUID: String
    let errorObserver: any NSObjectProtocol
  }

  /// How long to wait before each new try at a device that couldn't be turned on, such as Bluetooth headphones that
  /// are still switching to their headset profile.
  private static let retryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]

  /// Whether the microphone should be on.
  ///
  /// Callers set this before asking for an update, so updates running in any order end with the latest setting.
  nonisolated let isWanted = Mutex(false)
  private let recording: Recording
  private let capture: Capture
  private let queue = DispatchSerialQueue(label: "io.jeph.Casper.Microphone", qos: .userInitiated)
  /// Where sessions deliver audio, apart from `queue` so turning a session on or off doesn't hold up audio.
  private let sampleQueue = DispatchSerialQueue(label: "io.jeph.Casper.Microphone.samples", qos: .userInitiated)
  private var session: Session?
  /// The device to record from when the microphone was last updated, or `nil` if there was none, so a device that
  /// goes away and comes back with the same UID counts as a change.
  private var targetDeviceUID: String?
  /// The device that last couldn't be turned on, or stopped working.
  ///
  /// Apart from the delayed retries, it isn't tried again until a recording starts or the device to record from
  /// changes. Otherwise every settings change would try it again.
  private var failedDeviceUID: String?
  /// Counts series of delayed retries.
  ///
  /// A series starts when a recording starts or the device to record from changes, and replaces the one before, whose
  /// pending retries are dropped.
  private var retrySeries = 0
  /// How many delayed retries the current series has left, so a device that keeps failing isn't retried endlessly.
  private var retriesLeft = retryDelays.count

  nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

  init(recording: Recording) {
    self.recording = recording
    capture = Capture(recording: recording)
  }

  /// Turns the microphone on for a recording that just started, trying again a device that couldn't be turned on.
  func recordingStarted() {
    startRetrySeries()
    update(retryingFailedDevice: true)
  }

  /// Turns the microphone on or off, or moves it to the device to record from, as needed.
  ///
  /// - Parameter retryingFailedDevice: Whether to try again to turn on a device that couldn't be turned on.
  func update(retryingFailedDevice: Bool = false) {
    guard isWanted.withLock({ $0 }) else { return close() }
    let deviceUID = AudioInputDevices.recordingDeviceUID()
    if deviceUID != targetDeviceUID {
      targetDeviceUID = deviceUID
      failedDeviceUID = nil
      startRetrySeries()
    }
    guard let deviceUID else {
      logger.error("There's no microphone to record from")
      return close()
    }
    if let session {
      if session.deviceUID == deviceUID, session.captureSession.isRunning {
        return
      }
    } else if deviceUID == failedDeviceUID, !retryingFailedDevice {
      return
    }
    close()
    open(on: deviceUID)
  }

  private func open(on deviceUID: String) {
    let captureSession: AVCaptureSession
    do {
      captureSession = try makeCaptureSession(on: deviceUID)
    } catch {
      logger.error("Couldn't turn the microphone on for device \(deviceUID, privacy: .public): \(error)")
      return failed(on: deviceUID)
    }
    let sessionID = ObjectIdentifier(captureSession)
    // Posted when the session fails to start, or stops after starting, such as when the device fails.
    let errorObserver = NotificationCenter.default.addObserver(
      forName: AVCaptureSession.runtimeErrorNotification,
      object: captureSession,
      queue: nil
    ) { [weak self] notification in
      let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
      Task { await self?.captureFailed(sessionID, error) }
    }
    captureSession.startRunning()
    guard captureSession.isRunning else {
      logger.error("Couldn't turn the microphone on for device \(deviceUID, privacy: .public)")
      NotificationCenter.default.removeObserver(errorObserver)
      return failed(on: deviceUID)
    }
    session = Session(captureSession: captureSession, deviceUID: deviceUID, errorObserver: errorObserver)
    failedDeviceUID = nil
    logger.info("Turned the microphone on, recording from device \(deviceUID, privacy: .public)")
  }

  /// A session that records from the device into the recording, in the recording's format.
  private func makeCaptureSession(on deviceUID: String) throws -> AVCaptureSession {
    // AVFoundation identifies audio devices by their Core Audio UIDs.
    guard let device = AVCaptureDevice(uniqueID: deviceUID) else { throw MicrophoneError.notCapturable }
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: recording.sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(capture, queue: sampleQueue)
    let captureSession = AVCaptureSession()
    // Adding an input or output the session can't take raises an exception, which Swift can't catch.
    guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else {
      throw MicrophoneError.notCapturable
    }
    captureSession.addInput(input)
    captureSession.addOutput(output)
    return captureSession
  }

  private func captureFailed(_ sessionID: ObjectIdentifier, _ error: AVError?) {
    logger.error("The microphone failed: \(String(describing: error), privacy: .public)")
    guard let session, ObjectIdentifier(session.captureSession) == sessionID else { return }
    close()
    failed(on: session.deviceUID)
  }

  /// Remembers that the device couldn't be turned on or stopped working, and tries it again after a delay while the
  /// current series has retries left.
  private func failed(on deviceUID: String) {
    failedDeviceUID = deviceUID
    guard retriesLeft > 0 else { return }
    let delay = Self.retryDelays[Self.retryDelays.count - retriesLeft]
    retriesLeft -= 1
    let series = retrySeries
    Task { [weak self] in
      try? await Task.sleep(for: delay)
      await self?.retry(deviceUID, series: series)
    }
  }

  private func retry(_ deviceUID: String, series: Int) {
    guard series == retrySeries, session == nil, failedDeviceUID == deviceUID else { return }
    update(retryingFailedDevice: true)
  }

  private func startRetrySeries() {
    retrySeries += 1
    retriesLeft = Self.retryDelays.count
  }

  private func close() {
    guard let session else { return }
    self.session = nil
    NotificationCenter.default.removeObserver(session.errorObserver)
    session.captureSession.stopRunning()
  }
}

/// The samples of the recording in progress, kept apart from any capture session so the recording continues when the
/// microphone moves to another device.
private final class Recording: Sendable {
  private struct State {
    /// The samples recorded so far, or `nil` while not recording.
    var samples: [Float]?
    /// Counts recordings, so audio captured during one isn't added to the next.
    var number = 0
  }

  /// The sample rate, in hertz, of the recorded samples.
  let sampleRate: Double
  private let meter: AudioLevelMeter
  private let state = Mutex(State())

  init(sampleRate: Double, meter: AudioLevelMeter) {
    self.sampleRate = sampleRate
    self.meter = meter
  }

  var isActive: Bool {
    state.withLock { $0.samples != nil }
  }

  /// The number of the recording in progress, or `nil` while not recording.
  var number: Int? {
    state.withLock { $0.samples == nil ? nil : $0.number }
  }

  func begin() {
    meter.reset()
    state.withLock { state in
      state.number += 1
      state.samples = []
    }
  }

  /// Stops recording and returns what was recorded.
  func end() -> [Float] {
    state.withLock { state in
      defer { state.samples = nil }
      return state.samples ?? []
    }
  }

  /// Adds samples captured during recording `number`, unless it has ended.
  func append(_ samples: UnsafeBufferPointer<Float>, to number: Int) {
    state.withLock { state in
      guard state.number == number, let recordedCount = state.samples?.count else { return }
      state.samples?.append(contentsOf: samples)
      if let recorded = state.samples {
        meter.measure(recorded[recordedCount...], sampleRate: sampleRate)
      }
    }
  }
}

/// Adds a capture session's audio, already in the recording's format, to the recording while something is recording,
/// and discards it the rest of the time.
private final class Capture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, Sendable {
  private let recording: Recording

  init(recording: Recording) {
    self.recording = recording
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let number = recording.number else { return }
    do {
      try sampleBuffer.withAudioBufferList { buffers, _ in
        // Mono, interleaved audio arrives in a single buffer.
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let samples = UnsafeBufferPointer(
          start: data.assumingMemoryBound(to: Float.self),
          count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        )
        recording.append(samples, to: number)
      }
    } catch {
      logger.error("Couldn't read the microphone's audio: \(error)")
    }
  }
}

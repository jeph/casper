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
  /// turned on is tried again.
  func start() {
    recording.begin()
    microphone.isWanted.withLock { $0 = true }
    Task { [microphone] in await microphone.update(retryingFailedDevice: true) }
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

/// Keeps an audio engine running on the device to record from while the microphone is wanted, sending its audio to
/// the recording.
///
/// Turning an engine on or off can block for seconds, such as while Bluetooth headphones switch to their headset
/// profile, so the engine runs on its own queue instead of the main thread, where it would hold up the hotkey and
/// the voice bubble.
private actor Microphone {
  private enum MicrophoneError: Error {
    case noInput
    case unsupportedFormat(AVAudioFormat)
  }

  /// Whether the microphone should be on.
  ///
  /// Callers set this before asking for an update, so updates running in any order end with the latest setting.
  nonisolated let isWanted = Mutex(false)
  private let recording: Recording
  private let queue = DispatchSerialQueue(label: "io.jeph.Casper.Microphone", qos: .userInitiated)
  /// The running engine and the observer that restarts it when the audio configuration changes.
  private var session: (engine: AVAudioEngine, observer: any NSObjectProtocol)?
  /// The device that last couldn't be turned on.
  ///
  /// It isn't tried again until a recording starts or the device to record from changes. Otherwise every settings
  /// change, and the device list changes that turning an engine on causes itself, would try it again.
  private var failedDeviceID: AudioObjectID?

  nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

  init(recording: Recording) {
    self.recording = recording
  }

  /// Turns the engine on or off, or moves it to the device to record from, as needed.
  ///
  /// - Parameters:
  ///   - restartingEngine: Whether the engine stopped for an audio configuration change and needs its input read
  ///     again, if it stays on the same device.
  ///   - retryingFailedDevice: Whether to try again to turn on a device that couldn't be turned on.
  func update(restartingEngine: Bool = false, retryingFailedDevice: Bool = false) {
    guard isWanted.withLock({ $0 }) else { return close() }
    guard let deviceID = AudioInputDevices.recordingDeviceID() else {
      logger.error("There's no microphone to record from")
      return close()
    }
    if let session {
      // Compared with the device the engine is on now rather than the one it was given, because a device that goes
      // away while in use leaves the engine running on the system default, and may come back with the same ID.
      if session.engine.inputNode.auAudioUnit.deviceID == deviceID {
        if restartingEngine || !session.engine.isRunning {
          restart()
        }
        return
      }
    } else if deviceID == failedDeviceID, !retryingFailedDevice {
      return
    }
    close()
    open(on: deviceID)
  }

  private func open(on deviceID: AudioObjectID) {
    let engine = AVAudioEngine()
    let engineID = ObjectIdentifier(engine)
    // Posted when the device's format changes, or it goes away. Choosing the device below also causes one, shortly
    // after the engine starts.
    let observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil
    ) { [weak self] _ in
      Task { await self?.configurationChanged(engineID) }
    }
    do {
      // The device has to be chosen before the input's format is read, because the format comes from the device.
      try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
      try installCapture(on: engine)
      engine.prepare()
      try engine.start()
      session = (engine, observer)
      failedDeviceID = nil
      logger.info("Turned the microphone on, recording from device \(deviceID)")
    } catch {
      logger.error("Couldn't turn the microphone on for device \(deviceID): \(error)")
      failedDeviceID = deviceID
      NotificationCenter.default.removeObserver(observer)
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
  }

  private func configurationChanged(_ engineID: ObjectIdentifier) {
    guard let session, ObjectIdentifier(session.engine) == engineID else { return }
    update(restartingEngine: true)
  }

  /// Restarts the engine with its input's current format.
  ///
  /// The same engine is restarted rather than a new one opened, because choosing the device on a new engine causes
  /// another configuration change, which would repeat this endlessly.
  private func restart() {
    guard let session else { return }
    session.engine.inputNode.removeTap(onBus: 0)
    do {
      try installCapture(on: session.engine)
      try session.engine.start()
    } catch {
      logger.error("Couldn't turn the microphone back on after an audio configuration change: \(error)")
      failedDeviceID = session.engine.inputNode.auAudioUnit.deviceID
      close()
    }
  }

  private func close() {
    guard let session else { return }
    self.session = nil
    NotificationCenter.default.removeObserver(session.observer)
    session.engine.inputNode.removeTap(onBus: 0)
    session.engine.stop()
  }

  /// Sends the engine's input, in the device's current format, to the recording.
  ///
  /// The tap takes the hardware format rather than the input node's output format, because the output format keeps
  /// the previous sample rate after the engine moves to another device or the device's rate changes, such as when a
  /// video call opens the same microphone. A tap at that stale rate receives no audio, and installing one while the
  /// rates differ raises an exception that ends the app.
  private func installCapture(on engine: AVAudioEngine) throws {
    let input = engine.inputNode
    let hardwareFormat = input.inputFormat(forBus: 0)
    guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else { throw MicrophoneError.noInput }
    guard
      let recordingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: recording.sampleRate,
        channels: 1,
        interleaved: false
      ),
      let converter = AVAudioConverter(from: hardwareFormat, to: recordingFormat)
    else { throw MicrophoneError.unsupportedFormat(hardwareFormat) }
    converter.downmix = true
    let capture = Capture(converter: converter, recording: recording)
    input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat, block: capture.tapBlock())
  }
}

/// The samples of the recording in progress, kept apart from any engine so the recording continues when the
/// microphone moves to another device.
private final class Recording: Sendable {
  private struct State {
    /// The samples recorded so far, or `nil` while not recording.
    var samples: [Float]?
    /// Counts recordings, so audio converted during one isn't added to the next.
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

  /// Adds samples converted during recording `number`, unless it has ended.
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

/// Converts one engine's audio for the recording while something is recording, and discards it the rest of the time.
private final class Capture: Sendable {
  private struct State {
    let converter: AVAudioConverter
    /// The number of the recording the converter last converted audio for.
    var recordingNumber: Int?
  }

  private let state: Mutex<State>
  private let recording: Recording

  init(converter: sending AVAudioConverter, recording: Recording) {
    state = Mutex(State(converter: converter))
    self.recording = recording
  }

  /// A tap block created outside any actor, because AVAudioEngine calls it on its own thread.
  nonisolated func tapBlock() -> AVAudioNodeTapBlock {
    { [self] buffer, _ in append(buffer) }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    guard let number = recording.number else { return }
    state.withLock { state in
      if state.recordingNumber != number {
        // Clears the resampler's memory of audio from before this recording.
        state.converter.reset()
        state.recordingNumber = number
      }
      let outputFormat = state.converter.outputFormat
      let ratio = outputFormat.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
      guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity),
        Self.convert(buffer, with: state.converter, into: output),
        let channel = output.floatChannelData?[0]
      else { return }
      recording.append(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)), to: number)
    }
  }

  /// Hands the converter exactly one buffer, returning whether it converted without an error.
  ///
  /// `.noDataNow` keeps the resampler's state for the next buffer, where `.endOfStream` would reset it.
  private static func convert(
    _ buffer: AVAudioPCMBuffer,
    with converter: AVAudioConverter,
    into output: AVAudioPCMBuffer
  ) -> Bool {
    var isConsumed = false
    let status = converter.convert(to: output, error: nil) { _, status in
      if isConsumed {
        status.pointee = .noDataNow
        return nil
      }
      isConsumed = true
      status.pointee = .haveData
      return buffer
    }
    return status != .error
  }
}

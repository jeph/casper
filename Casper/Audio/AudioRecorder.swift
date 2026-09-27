import AVFoundation
import AudioToolbox
import Foundation
import OSLog
import Synchronization

/// Records from the input device chosen in Settings as mono samples at a speech model's sample rate.
///
/// The microphone can be opened before recording and left open between recordings, so a recording starts without
/// waiting for the device to turn on. While the microphone is open and nothing is recording, its audio is discarded.
@MainActor
final class AudioRecorder {
  enum RecordingError: Error {
    case noInput
    case unsupportedFormat(AVAudioFormat)
  }

  /// The sample rate, in hertz, of the recorded samples.
  let sampleRate: Double
  /// The loudness of the recording in progress.
  let meter = AudioLevelMeter()

  /// The open microphone: its engine, the device it uses (`nil` for the system default), the capture its audio goes
  /// to, and the observer that rebuilds the engine when the audio configuration changes.
  private var session:
    (engine: AVAudioEngine, deviceID: AudioObjectID?, capture: Capture, observer: any NSObjectProtocol)?
  /// What was recorded before the microphone failed partway through a recording, kept for `stop()` so the recording
  /// still ends normally.
  private var interruptedRecording: [Float]?

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "AudioRecorder")

  init(sampleRate: Double) {
    self.sampleRate = sampleRate
    // Switches to a newly chosen input device right away, rather than keeping the previous one on.
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.reopenIfDeviceChanged() }
    }
  }

  var isOpen: Bool { session != nil }
  var isRecording: Bool { interruptedRecording != nil || session?.capture.isRecording == true }

  /// Turns the microphone on, if it isn't already, without recording.
  func open() throws {
    guard session == nil else { return }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let deviceID = AudioInputDevices.chosenDeviceID()
    // The device has to be chosen before the input's format is read, because the format comes from the device.
    if var deviceID, let audioUnit = input.audioUnit {
      AudioUnitSetProperty(
        audioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioObjectID>.size)
      )
    }
    let capture = try installCapture(on: engine)
    engine.prepare()
    try engine.start()
    // Posted when the device's format changes, or the system default changes while it's in use; the engine has
    // stopped by then. Choosing the device above also causes one, shortly after the engine starts.
    let observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.restart() }
    }
    session = (engine, deviceID, capture, observer)
  }

  /// Sends the engine's input, in its current format, to a new capture.
  private func installCapture(on engine: AVAudioEngine) throws -> Capture {
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecordingError.noInput }
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      ),
      let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    else { throw RecordingError.unsupportedFormat(inputFormat) }
    converter.downmix = true
    let capture = Capture(converter: converter, meter: meter)
    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: capture.tapBlock())
    return capture
  }

  /// Restarts the engine after macOS stopped it for an audio configuration change, continuing any recording.
  ///
  /// The same engine is restarted rather than a new one opened, because choosing the device on a new engine causes
  /// another configuration change, which would repeat this endlessly.
  private func restart() {
    guard let session else { return }
    let recorded = session.capture.isRecording ? session.capture.end() : nil
    session.engine.inputNode.removeTap(onBus: 0)
    do {
      let capture = try installCapture(on: session.engine)
      try session.engine.start()
      self.session = (session.engine, session.deviceID, capture, session.observer)
      if let recorded {
        capture.begin(continuing: recorded)
      }
    } catch {
      Self.logger.error("Couldn't turn the microphone back on after an audio configuration change: \(error)")
      interruptedRecording = recorded
      close()
    }
  }

  /// Turns the microphone off, ending any recording in progress.
  func close() {
    guard let session else { return }
    self.session = nil
    NotificationCenter.default.removeObserver(session.observer)
    session.engine.inputNode.removeTap(onBus: 0)
    session.engine.stop()
  }

  /// Starts recording, turning the microphone on first if needed.
  func start() throws {
    reopenIfDeviceChanged()
    try open()
    session?.capture.begin()
  }

  /// Stops recording and returns the samples recorded since `start()`, leaving the microphone on if it still is.
  func stop() -> [Float] {
    if let interruptedRecording {
      self.interruptedRecording = nil
      return interruptedRecording
    }
    return session?.capture.end() ?? []
  }

  private func reopenIfDeviceChanged() {
    guard let session, session.deviceID != AudioInputDevices.chosenDeviceID() else { return }
    reopen()
  }

  /// Rebuilds the engine on the current device, continuing any recording in progress.
  private func reopen() {
    let recorded = session.flatMap { $0.capture.isRecording ? $0.capture.end() : nil }
    close()
    do {
      try open()
      if let recorded {
        session?.capture.begin(continuing: recorded)
      }
    } catch {
      Self.logger.error("Couldn't turn the microphone back on after an audio device change: \(error)")
      interruptedRecording = recorded
    }
  }
}

/// Converts audio arriving from the microphone while recording, and discards it the rest of the time.
private final class Capture: Sendable {
  private struct State {
    let converter: AVAudioConverter
    /// The samples recorded so far, or `nil` while not recording.
    var samples: [Float]?
  }

  private let state: Mutex<State>
  private let meter: AudioLevelMeter

  init(converter: sending AVAudioConverter, meter: AudioLevelMeter) {
    state = Mutex(State(converter: converter))
    self.meter = meter
  }

  var isRecording: Bool {
    state.withLock { $0.samples != nil }
  }

  /// A tap block created outside the main actor, because AVAudioEngine calls it on its own thread.
  nonisolated func tapBlock() -> AVAudioNodeTapBlock {
    { [self] buffer, _ in append(buffer) }
  }

  /// Starts recording, after any samples already recorded on an engine this one replaced.
  func begin(continuing samples: [Float] = []) {
    if samples.isEmpty {
      meter.reset()
    }
    state.withLock { state in
      // Clears the resampler's memory of audio from before this recording.
      state.converter.reset()
      state.samples = samples
    }
  }

  /// Stops recording and returns what was recorded.
  func end() -> [Float] {
    state.withLock { state in
      let samples = state.samples ?? []
      state.samples = nil
      return samples
    }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    state.withLock { state in
      guard state.samples != nil else { return }
      let outputFormat = state.converter.outputFormat
      let ratio = outputFormat.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
      guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
      // Each call hands the converter exactly one buffer. `.noDataNow` keeps the resampler's state for the next
      // buffer, where `.endOfStream` would reset it.
      nonisolated(unsafe) var isConsumed = false
      var error: NSError?
      state.converter.convert(to: output, error: &error) { _, status in
        if isConsumed {
          status.pointee = .noDataNow
          return nil
        }
        isConsumed = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, let channel = output.floatChannelData?[0] else { return }
      let converted = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
      state.samples?.append(contentsOf: converted)
      meter.measure(converted, sampleRate: outputFormat.sampleRate)
    }
  }
}

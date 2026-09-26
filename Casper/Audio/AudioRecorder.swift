import AVFoundation
import AudioToolbox
import SwiftUI
import Synchronization

/// Records from the input device chosen in Settings as mono samples at a given sample rate.
@MainActor
final class AudioRecorder {
  enum RecordingError: Error {
    case noInput
    case unsupportedFormat(AVAudioFormat)
  }

  private var engine: AVAudioEngine?
  private var recording: Recording?

  /// Starts recording, replacing any recording in progress.
  func start(sampleRate: Double) throws {
    _ = stop()
    let engine = AVAudioEngine()
    let input = engine.inputNode
    // The device has to be chosen before the input's format is read, because the format comes from the device.
    if var deviceID = Self.chosenDeviceID(), let audioUnit = input.audioUnit {
      AudioUnitSetProperty(
        audioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioObjectID>.size)
      )
    }
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
    let recording = Recording(converter: converter)
    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: recording.tapBlock())
    engine.prepare()
    try engine.start()
    self.engine = engine
    self.recording = recording
  }

  /// Stops recording and returns the samples recorded since `start(sampleRate:)`, or none if nothing was recording.
  func stop() -> [Float] {
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    defer { recording = nil }
    return recording?.samples() ?? []
  }

  /// The chosen input device, or `nil` for the system default, which is also used while the chosen one is unplugged.
  private static func chosenDeviceID() -> AudioObjectID? {
    guard let uid = UserDefaults.standard.string(forKey: InputDevicePicker<EmptyView>.uidStorageKey), !uid.isEmpty
    else { return nil }
    return AudioInputDevices.deviceID(forUID: uid)
  }
}

/// Converts audio arriving on Core Audio's real-time thread and collects it until the recording stops.
private final class Recording: Sendable {
  private struct State {
    let converter: AVAudioConverter
    var samples: [Float] = []
  }

  private let state: Mutex<State>

  init(converter: sending AVAudioConverter) {
    state = Mutex(State(converter: converter))
  }

  /// A tap block created outside the main actor, because AVAudioEngine calls it on its own thread.
  nonisolated func tapBlock() -> AVAudioNodeTapBlock {
    { [self] buffer, _ in append(buffer) }
  }

  func samples() -> [Float] {
    state.withLock { $0.samples }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    state.withLock { state in
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
      state.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
  }
}

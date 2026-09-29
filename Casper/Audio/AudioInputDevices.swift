import CoreAudio
import Foundation
import OSLog
import Observation

/// A microphone or other audio input, identified by its Core Audio UID, which stays the same across restarts.
struct AudioInputDevice: Hashable, Identifiable, Sendable {
  let uid: String
  let name: String

  var id: String { uid }
}

/// The audio inputs connected to the Mac, kept current as devices are plugged in or the system default changes.
@MainActor
@Observable
final class AudioInputDevices {
  static let shared = AudioInputDevices()

  private(set) var devices: [AudioInputDevice] = []
  /// The input selected in System Settings > Sound, if there is one.
  private(set) var systemDefault: AudioInputDevice?

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "AudioInputDevices")
  /// The `UserDefaults` key for the chosen device's UID; empty or missing means the system default.
  nonisolated static let uidStorageKey = "inputDeviceUID"
  /// The `UserDefaults` key for the chosen device's name, shown while the device is unplugged.
  nonisolated static let nameStorageKey = "inputDeviceName"

  private init() {
    refresh()
    Self.observeChanges { [weak self] in self?.refresh() }
  }

  /// Calls `handler` on the main thread whenever an input device is plugged in or unplugged, or the system default
  /// input changes.
  static func observeChanges(_ handler: @escaping @MainActor () -> Void) {
    let system = AudioObjectID(kAudioObjectSystemObject)
    for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
      var address = address(selector)
      let status = AudioObjectAddPropertyListenerBlock(system, &address, .main) { _, _ in
        MainActor.assumeIsolated { handler() }
      }
      if status != noErr {
        logger.error("Couldn't watch audio device property \(selector): \(status)")
      }
    }
  }

  private func refresh() {
    let system = AudioObjectID(kAudioObjectSystemObject)
    devices = Self.values(from: system, selector: kAudioHardwarePropertyDevices)
      .filter { Self.hasInput($0) && !Self.isHidden($0) }
      .compactMap(Self.device)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    systemDefault = Self.values(from: system, selector: kAudioHardwarePropertyDefaultInputDevice)
      .first
      .flatMap(Self.device)
  }

  /// The input to record from: the chosen device while it's connected, and otherwise the system default. `nil` when
  /// there's no input at all.
  nonisolated static func recordingDeviceID() -> AudioObjectID? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let systemDefault = values(from: system, selector: kAudioHardwarePropertyDefaultInputDevice)
      .first { $0 != kAudioObjectUnknown }
    guard let uid = UserDefaults.standard.string(forKey: uidStorageKey), !uid.isEmpty else { return systemDefault }
    return deviceID(forUID: uid) ?? systemDefault
  }

  /// The Core Audio ID of the device with this UID, or `nil` if it isn't connected.
  nonisolated private static func deviceID(forUID uid: String) -> AudioObjectID? {
    var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
    var qualifier = uid as CFString
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &qualifier) {
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        UInt32(MemoryLayout<CFString>.size),
        $0,
        &size,
        &id
      )
    }
    guard status == noErr, id != kAudioObjectUnknown else { return nil }
    return id
  }

  /// The device's nominal sample rate in hertz, or `nil` if it can't be read, such as after it's unplugged.
  nonisolated static func sampleRate(of id: AudioObjectID) -> Double? {
    var address = address(kAudioDevicePropertyNominalSampleRate)
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return nil }
    return rate
  }

  private static func device(_ id: AudioObjectID) -> AudioInputDevice? {
    guard let uid = string(from: id, selector: kAudioDevicePropertyDeviceUID),
      let name = string(from: id, selector: kAudioObjectPropertyName)
    else { return nil }
    return AudioInputDevice(uid: uid, name: name)
  }

  private static func hasInput(_ id: AudioObjectID) -> Bool {
    var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func isHidden(_ id: AudioObjectID) -> Bool {
    values(from: id, selector: kAudioDevicePropertyIsHidden).first == 1
  }

  /// A property made of 32-bit values, such as device IDs and flags.
  nonisolated private static func values(
    from id: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> ArraySlice<UInt32> {
    var address = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var values = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.stride)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &values) == noErr else { return [] }
    // The property can shrink between reading its size and its data, such as when a device is unplugged.
    return values.prefix(Int(size) / MemoryLayout<UInt32>.stride)
  }

  private static func string(from id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var address = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    guard status == noErr else { return nil }
    return value?.takeRetainedValue() as String?
  }

  nonisolated private static func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
}

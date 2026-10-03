import Foundation
import MLX

/// MLX's pool of freed GPU buffers, which it keeps for reuse instead of returning their memory to macOS.
///
/// A dictation leaves about a gigabyte there, and a long one several, held until its model unloads. Releasing the
/// pool after each transcription and refine returns that memory, and the next one takes slightly longer, since it gets
/// fresh memory from macOS instead of reusing buffers. Releasing only frees buffers no array uses, so a persona's
/// cached prompt survives it.
enum BufferCache {
  /// The `UserDefaults` key for whether the pool is released after each transcription and refine, off unless turned on.
  static let releaseStorageKey = "releasesBufferCache"

  static var isReleaseEnabled: Bool {
    UserDefaults.standard.bool(forKey: releaseStorageKey)
  }

  /// Returns the pool's memory to macOS, if the user turned that on.
  static func releaseIfEnabled() {
    guard isReleaseEnabled else { return }
    MLX.Memory.clearCache()
  }
}

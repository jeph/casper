import Accelerate
import Synchronization

/// The loudness of recorded audio in short slices, kept for a moment so it can be shown as it's spoken.
///
/// The recorder measures audio on its own thread as it arrives, and the voice bubble reads the recent slices each
/// frame, so nothing crosses to the main thread per slice.
final class AudioLevelMeter: Sendable {
  /// A slice of audio's RMS amplitude, from 0 for silence to 1 for full scale, and when it ended.
  struct Level: Sendable {
    let time: ContinuousClock.Instant
    let value: Float
  }

  /// The length of audio each level measures, in seconds.
  static let sliceSeconds = 0.02
  static let sliceDuration = Duration.seconds(sliceSeconds)
  /// How far back levels are kept: longer than the voice bubble shows, plus the moments its oldest bar is scaled to.
  private static let retention = Duration.seconds(5)

  private let levels = Mutex<[Level]>([])

  /// Forgets the levels of the previous recording.
  func reset() {
    levels.withLock { $0.removeAll(keepingCapacity: true) }
  }

  /// Measures samples that just arrived, as slices that end now.
  func measure(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
    guard let base = samples.baseAddress, !samples.isEmpty else { return }
    let sliceLength = max(1, Int(sampleRate * Self.sliceSeconds))
    let sliceCount = max(1, samples.count / sliceLength)
    let now = ContinuousClock.now
    var measured: [Level] = []
    measured.reserveCapacity(sliceCount)
    for slice in 0..<sliceCount {
      let start = slice * sliceLength
      let length = slice == sliceCount - 1 ? samples.count - start : sliceLength
      var rms: Float = 0
      vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(length))
      measured.append(
        Level(time: now - Self.sliceDuration * (sliceCount - 1 - slice), value: min(rms, 1))
      )
    }
    levels.withLock { levels in
      levels.append(contentsOf: measured)
      let oldest = now - Self.retention
      if let firstKept = levels.firstIndex(where: { $0.time >= oldest }), firstKept > 0 {
        levels.removeFirst(firstKept)
      }
    }
  }

  /// The levels measured since the given time, oldest first.
  func levels(since time: ContinuousClock.Instant) -> [Level] {
    levels.withLock { levels in
      guard let first = levels.firstIndex(where: { $0.time >= time }) else { return [] }
      return Array(levels[first...])
    }
  }
}

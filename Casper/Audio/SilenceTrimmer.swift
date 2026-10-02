import Accelerate
import Foundation

/// Shortens the silence in a recording before it's transcribed: before the first sound, after the last, and in pauses
/// longer than `longestPause`.
///
/// Transcription takes longer the more audio it's given, and silence is audio too. Only stretches that stay near the
/// recording's quietest level count as silence, and each keeps some of its length, so the quiet start or end of a word
/// next to a pause survives, and so does the pause the model reads a sentence break from.
struct SilenceTrimmer: Sendable {
  /// The `UserDefaults` key for whether recordings are trimmed, on unless turned off.
  ///
  /// It's an advanced setting, so trimming can be turned off if it causes problems.
  static let enabledStorageKey = "trimsSilence"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  /// The longest a pause is left, in seconds, half of it from each side of the pause.
  ///
  /// In evaluation, half a second gave as few errors overall as untrimmed audio and saved the most time of the limits
  /// tried, though it clipped the first sound of a word next to a pause slightly more often.
  var longestPause = 0.5
  /// How much of the silence before the first sound and after the last is kept, in seconds.
  ///
  /// Parakeet starts the transcript with a lowercase letter three times as often when less silence comes before the
  /// first word, as if the recording started mid-sentence.
  var edgeSilence = 1.0
  /// How far above the quietest tenth of the recording a stretch can be, in decibels, and still be silence.
  var silenceMargin = 6.0
  /// How much louder than silence the loudest sounds must be, in decibels, for the recording to be trimmed at all.
  ///
  /// Below this, speech can't be told from the background by loudness, and the recording is left as it is.
  var minimumContrast = 20.0

  /// The length of the slices whose loudness is measured, in seconds.
  private static let sliceDuration = 0.01
  /// How long the audio on either side of a cut fades into the other, in seconds, so the cut doesn't click.
  private static let crossfadeDuration = 0.01

  /// Returns the recording with its silence shortened, or unchanged if it has none to shorten.
  func trim(_ samples: [Float], sampleRate: Double) -> [Float] {
    let kept = keptRanges(of: samples, sampleRate: sampleRate)
    guard kept.count > 1 || kept.first != samples.indices else { return samples }
    let crossfadeLength = Int(Self.crossfadeDuration * sampleRate)
    var trimmed: [Float] = []
    trimmed.reserveCapacity(kept.reduce(0) { $0 + $1.count })
    trimmed.append(contentsOf: samples[kept[0]])
    for range in kept.dropFirst() {
      // The end of the audio so far fades out as the start of the next range fades in, keeping the loudness of the
      // background even across the cut.
      let fadeStart = trimmed.count - crossfadeLength
      for offset in 0..<crossfadeLength {
        let angle = Float.pi / 2 * Float(offset + 1) / Float(crossfadeLength + 1)
        let fadingIn = samples[range.lowerBound + offset] * sin(angle)
        trimmed[fadeStart + offset] = trimmed[fadeStart + offset] * cos(angle) + fadingIn
      }
      trimmed.append(contentsOf: samples[(range.lowerBound + crossfadeLength)..<range.upperBound])
    }
    return trimmed
  }

  /// The ranges of samples to keep, in order.
  func keptRanges(of samples: [Float], sampleRate: Double) -> [Range<Int>] {
    let sliceLength = Int(Self.sliceDuration * sampleRate)
    let levels = Self.sliceLevels(of: samples, sliceLength: sliceLength)
    guard levels.count > 1 else { return [samples.indices] }
    let sorted = levels.sorted()
    let quietest = sorted[sorted.count / 10]
    let loudest = sorted[sorted.count * 99 / 100]
    guard loudest - quietest >= minimumContrast else { return [samples.indices] }
    let isSilent = levels.map { $0 < quietest + silenceMargin }
    guard let firstSound = isSilent.firstIndex(of: false), let lastSound = isSilent.lastIndex(of: false) else {
      return [samples.indices]
    }

    let edgeSlices = Int(edgeSilence / Self.sliceDuration)
    let pauseSideSlices = Int(longestPause / 2 / Self.sliceDuration)
    let crossfadeSlices = Int((Self.crossfadeDuration / Self.sliceDuration).rounded(.up))
    var kept: [Range<Int>] = []
    var keptStart = max(0, firstSound - edgeSlices)
    var searchStart = firstSound
    while let pauseStart = isSilent[searchStart...lastSound].firstIndex(of: true) {
      // The last sound isn't silent, so every pause before it ends.
      let pauseEnd = isSilent[pauseStart...lastSound].firstIndex(of: false) ?? lastSound
      // Each side keeps its share of the pause, plus the audio the crossfade overlaps, so the pause comes out as long
      // as `longestPause`.
      if pauseEnd - pauseStart > 2 * pauseSideSlices + crossfadeSlices {
        kept.append(keptStart..<(pauseStart + pauseSideSlices + crossfadeSlices))
        keptStart = pauseEnd - pauseSideSlices
      }
      searchStart = pauseEnd
    }
    kept.append(keptStart..<min(levels.count, lastSound + 1 + edgeSlices))
    return kept.map { ($0.lowerBound * sliceLength)..<min(samples.count, $0.upperBound * sliceLength) }
  }

  /// The loudness of each slice of the recording in decibels, the last slice possibly shorter than the rest.
  private static func sliceLevels(of samples: [Float], sliceLength: Int) -> [Double] {
    stride(from: 0, to: samples.count, by: sliceLength)
      .map { start in
        let meanSquare = vDSP.meanSquare(samples[start..<min(start + sliceLength, samples.count)])
        // The floor keeps digital silence finite.
        return 10 * log10(max(Double(meanSquare), 1e-12))
      }
  }
}

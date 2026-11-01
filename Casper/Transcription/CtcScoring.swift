import CoreML
import Foundation

/// The steps of scoring audio with the word spotter's CTC model around running it: the samples it reads, the logits it
/// writes, and joining the log-probabilities of overlapping windows.
///
/// They repeat what FluidAudio's `CtcKeywordSpotter.spotKeywordsWithLogProbs` does, from
/// `CtcKeywordSpotter+Inference.swift` in FluidAudio 0.17.7 (https://github.com/FluidInference/FluidAudio), but copy
/// samples and logits through memory rather than an `NSNumber` at a time, which took about 100 ms of its 110 per
/// window. FluidAudio is licensed under the Apache License, Version 2.0, which `Acknowledgements.txt` includes.
enum CtcScoring {
  enum ScoringError: Error {
    /// The model takes or writes arrays of a shape or type it shouldn't.
    case unexpectedModel
  }

  /// The samples as an array of the shape and type the mel spectrogram model takes, which must hold exactly as many.
  static func audioArray(
    _ samples: ArraySlice<Float>,
    shape: [NSNumber],
    dataType: MLMultiArrayDataType
  ) throws -> MLMultiArray {
    guard shape.reduce(1, { $0 * $1.intValue }) == samples.count else { throw ScoringError.unexpectedModel }
    let array = try MLMultiArray(shape: shape, dataType: dataType)
    switch dataType {
    case .float16:
      array.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
        for (index, sample) in zip(buffer.indices, samples) {
          buffer[index] = Float16(sample)
        }
      }
    case .float32:
      array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
        _ = buffer.update(fromContentsOf: samples)
      }
    default:
      throw ScoringError.unexpectedModel
    }
    return array
  }

  /// The logits of each frame, from the encoder's output shaped [1, frames, tokens] or [1, tokens, 1, frames].
  static func logits(of output: MLMultiArray) throws -> [[Float]] {
    let shape = output.shape.map(\.intValue)
    let strides = output.strides.map(\.intValue)
    let (frameCount, tokenCount, frameStride, tokenStride) =
      switch shape.count {
      case 3: (shape[1], shape[2], strides[1], strides[2])
      case 4: (shape[3], shape[1], strides[3], strides[1])
      default: throw ScoringError.unexpectedModel
      }
    func read<Element: BinaryFloatingPoint & MLShapedArrayScalar>(_: Element.Type) -> [[Float]] {
      output.withUnsafeBufferPointer(ofType: Element.self) { buffer in
        (0..<frameCount)
          .map { frame in
            (0..<tokenCount).map { token in Float(buffer[frame * frameStride + token * tokenStride]) }
          }
      }
    }
    switch output.dataType {
    case .float16: return read(Float16.self)
    case .float32: return read(Float.self)
    default: throw ScoringError.unexpectedModel
    }
  }

  /// The log-probabilities of samples padded to whole windows, joined where windows overlap as FluidAudio joins them,
  /// and the length of a frame in seconds.
  ///
  /// - Parameters:
  ///   - samples: Audio filling `window` samples and then a whole number of `stride`s.
  ///   - window: How many samples the model reads at once.
  ///   - stride: How far each window starts after the one before, less than `window` so they overlap.
  ///   - sampleRate: The audio's sample rate, in hertz.
  ///   - logProbs: The log-probabilities of each frame of one window.
  /// - Returns: Every frame's log-probabilities, with the frames two windows share averaged in probability, and the
  ///   length of a frame in seconds, or no frames and 0 if no window had any.
  /// - Throws: The error `logProbs` throws.
  static func joinedWindows(
    of samples: [Float],
    window: Int,
    stride: Int,
    sampleRate: Double,
    logProbs: (ArraySlice<Float>) async throws -> [[Float]]
  ) async rethrows -> (logProbs: [[Float]], frameDuration: Double) {
    var joined: [[Float]] = []
    var overlapFrames = 0
    var frameDuration = 0.0
    for start in Swift.stride(from: 0, to: samples.count - window + 1, by: stride) {
      let windowLogProbs = try await logProbs(samples[start..<(start + window)])
      guard !windowLogProbs.isEmpty else { continue }
      guard !joined.isEmpty else {
        joined = windowLogProbs
        frameDuration = Double(window) / Double(windowLogProbs.count) / sampleRate
        overlapFrames = Int(Double(window - stride) / sampleRate / frameDuration)
        continue
      }
      // The frames both windows heard are averaged in probability, the rest of this window's appended.
      let overlap = min(overlapFrames, joined.count, windowLogProbs.count)
      for index in 0..<overlap {
        let joinedIndex = joined.count - overlap + index
        joined[joinedIndex] = meanInProbability(joined[joinedIndex], windowLogProbs[index])
      }
      joined += windowLogProbs[overlap...]
    }
    return (joined, frameDuration)
  }

  /// The mean of two frames' probabilities, as log-probabilities.
  private static func meanInProbability(_ first: [Float], _ second: [Float]) -> [Float] {
    zip(first, second)
      .map { first, second in
        let largest = max(first, second)
        guard largest != -.infinity else { return -.infinity }
        return largest + logf(expf(first - largest) + expf(second - largest)) - logf(2)
      }
  }
}

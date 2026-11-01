import CoreML
import Foundation
import Testing

struct CtcScoringTests {
  /// The encoder writes [1, tokens, 1, frames], so each frame's logits are a column.
  @Test func readsFramesFromTokensByFrames() throws {
    let output = try MLMultiArray(shape: [1, 3, 1, 2], dataType: .float16)
    for token in 0..<3 {
      for frame in 0..<2 {
        output[[0, token, 0, frame] as [NSNumber]] = NSNumber(value: token * 10 + frame)
      }
    }
    #expect(try CtcScoring.logits(of: output) == [[0, 10, 20], [1, 11, 21]])
  }

  /// Rows can be padded past their last element, so positions come from the strides.
  @Test func readsFramesByTokensThroughStrides() throws {
    let storage = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    storage.initialize(from: [0, 1, 2, 99, 4, 5, 6, 99], count: 8)
    let output = try MLMultiArray(
      dataPointer: storage,
      shape: [1, 2, 3],
      dataType: .float32,
      strides: [8, 4, 1],
      deallocator: { $0.deallocate() }
    )
    #expect(try CtcScoring.logits(of: output) == [[0, 1, 2], [4, 5, 6]])
  }

  @Test func rejectsOtherOutputs() throws {
    #expect(throws: CtcScoring.ScoringError.self) {
      try CtcScoring.logits(of: MLMultiArray(shape: [2, 3], dataType: .float32))
    }
    #expect(throws: CtcScoring.ScoringError.self) {
      try CtcScoring.logits(of: MLMultiArray(shape: [1, 2, 3], dataType: .int32))
    }
  }

  @Test func writesSamplesInTheModelsType() throws {
    let samples: [Float] = [0.1, -0.5, 0.333]
    let half = try CtcScoring.audioArray(samples[...], shape: [3], dataType: .float16)
    #expect((0..<3).map { half[$0].floatValue } == samples.map { Float(Float16($0)) })
    let single = try CtcScoring.audioArray(samples[...], shape: [1, 3], dataType: .float32)
    #expect((0..<3).map { single[$0].floatValue } == samples)
  }

  @Test func rejectsSamplesThatDontFitTheModel() {
    #expect(throws: CtcScoring.ScoringError.self) {
      try CtcScoring.audioArray([0, 0][...], shape: [3], dataType: .float32)
    }
    #expect(throws: CtcScoring.ScoringError.self) {
      try CtcScoring.audioArray([0, 0, 0][...], shape: [3], dataType: .int32)
    }
  }

  @Test func keepsASingleWindowsFrames() async {
    let frames: [[Float]] = [[-1], [-2], [-3], [-4], [-5]]
    let joined = await CtcScoring.joinedWindows(of: Self.samples(10), window: 10, stride: 6, sampleRate: 10) { _ in
      frames
    }
    #expect(joined.logProbs == frames)
    #expect(joined.frameDuration == 0.2)
  }

  /// Windows of 10 samples start every 6, so at 5 frames a window, the last 2 frames of each are heard again as the
  /// next one's first 2, and the two are averaged in probability: 0.2 and 0.6 become 0.4.
  @Test func averagesTheFramesWindowsShare() async {
    let framesByStart: [Float: [[Float]]] = [
      0: [[0], [1], [2], [logf(0.2)], [-.infinity]],
      6: [[logf(0.6)], [-.infinity], [6], [logf(0.5)], [logf(0.5)]],
      12: [[logf(0.5)], [logf(0.5)], [12], [13], [14]],
    ]
    var starts: [Float] = []
    let joined = await CtcScoring.joinedWindows(of: Self.samples(22), window: 10, stride: 6, sampleRate: 10) {
      window in
      starts.append(window.first ?? -1)
      return framesByStart[window.first ?? -1] ?? []
    }
    #expect(starts == [0, 6, 12])
    let expected: [Float] = [0, 1, 2, logf(0.4), -.infinity, 6, logf(0.5), logf(0.5), 12, 13, 14]
    let logProbs = joined.logProbs.map { $0.first ?? .nan }
    #expect(logProbs.count == expected.count)
    for (logProb, expected) in zip(logProbs, expected) {
      #expect(logProb == expected || abs(logProb - expected) < 1e-6)
    }
    #expect(joined.frameDuration == 0.2)
  }

  @Test func passesOnTheModelsError() async {
    await #expect(throws: CtcScoring.ScoringError.self) {
      try await CtcScoring.joinedWindows(of: Self.samples(10), window: 10, stride: 6, sampleRate: 10) { _ in
        throw CtcScoring.ScoringError.unexpectedModel
      }
    }
  }

  /// Samples numbered by their index, so a window's first sample says where it starts.
  private static func samples(_ count: Int) -> [Float] {
    (0..<count).map(Float.init)
  }
}

import AudioCommon
import FluidAudio
import Foundation
import Qwen3ASR

/// Transcribes every recording in a manifest as it is and trimmed with each longest pause, timing both steps.
///
/// Usage: TrimEval <parakeet|qwen3> <manifest.jsonl> <results.jsonl> <longest pauses, comma-separated>
///        [--margin dB] [--contrast dB] [--edge seconds] [--limit N] [--ids id,id]

struct Item: Decodable {
  let id: String
  let audio: String
}

struct Result: Encodable {
  let id: String
  let variant: String
  let inputSeconds: Double
  let outputSeconds: Double
  let trimMilliseconds: Double
  let transcribeMilliseconds: Double
  let kept: [[Double]]
  let text: String
}

protocol Model {
  func transcribe(_ samples: [Float]) async throws -> String
}

final class Parakeet: Model {
  let manager = AsrManager()
  var decoderLayers = 0

  func load(from directory: URL) async throws {
    let models = try await AsrModels.loadLocal(from: directory, version: .ultra)
    try await manager.loadModels(models)
    decoderLayers = models.version.decoderLayers
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    var state = TdtDecoderState.make(decoderLayers: decoderLayers)
    return try await manager.transcribe(samples, decoderState: &state).text
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Casper's own Qwen3 transcriber, so the evaluation runs the app's code, including its limit on transcript length.
final class Qwen3: Model {
  let transcriber: Qwen3Transcriber

  init(directory: URL) async throws {
    transcriber = Qwen3Transcriber(
      model: try await Qwen3ASRModel.fromPretrained(
        modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-5bit", cacheDir: directory, offlineMode: true))
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    try await transcriber.transcribe(samples, sampleRate: 16_000)
  }
}

func milliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func option(_ name: String) -> String? {
  guard let index = CommandLine.arguments.firstIndex(of: name) else { return nil }
  return CommandLine.arguments[index + 1]
}

let arguments = CommandLine.arguments
let modelName = arguments[1]
let manifest = URL(fileURLWithPath: arguments[2])
let output = URL(fileURLWithPath: arguments[3])
let pauses = arguments[4].split(separator: ",").map { Double($0)! }

var baseTrimmer = SilenceTrimmer()
if let margin = option("--margin") { baseTrimmer.silenceMargin = Double(margin)! }
if let contrast = option("--contrast") { baseTrimmer.minimumContrast = Double(contrast)! }
if let edge = option("--edge") { baseTrimmer.edgeSilence = Double(edge)! }
let repeats = option("--repeat").map { Int($0)! } ?? 1
let limit = option("--limit").map { Int($0)! } ?? .max
let onlyIDs = option("--ids").map { Set($0.split(separator: ",").map(String.init)) }

var items = try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n")
  .map { try JSONDecoder().decode(Item.self, from: Data($0.utf8)) }
if let onlyIDs { items = items.filter { onlyIDs.contains($0.id) } }
items = Array(items.prefix(limit))

let model: any Model
switch modelName {
case "parakeet":
  let parakeet = Parakeet()
  try await parakeet.load(
    from: URL.applicationSupportDirectory.appending(path: "Casper/Models/parakeet-ultra-coreml"))
  model = parakeet
case "qwen3":
  model = try await Qwen3(directory: URL(fileURLWithPath: "/tmp/casper-trim-eval/models/Qwen3-ASR-0.6B-MLX-5bit"))
default:
  fatalError("unknown model \(modelName)")
}

func samples(of item: Item) throws -> [Float] {
  let data = try Data(contentsOf: URL(fileURLWithPath: item.audio))
  return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

// Warm up so the first measured transcription doesn't pay for compiling or loading anything.
let warmUp = try samples(of: items[0])
for _ in 0..<3 { _ = try await model.transcribe(warmUp) }

FileManager.default.createFile(atPath: output.path, contents: nil)
let handle = try FileHandle(forWritingTo: output)
let encoder = JSONEncoder()
let clock = ContinuousClock()
let variants: [Double?] = [nil] + pauses.map { $0 }

for (number, item) in items.enumerated() {
  let recording = try samples(of: item)
  // Rotating the order spreads any drift in speed evenly over the variants.
  let offset = number % variants.count
  for variant in variants[offset...] + variants[..<offset] {
    var input = recording
    var kept: [[Double]] = [[0, Double(recording.count) / 16_000]]
    var trimTime = Duration.zero
    if let variant {
      var trimmer = baseTrimmer
      trimmer.longestPause = variant
      let start = clock.now
      input = trimmer.trim(recording, sampleRate: 16_000)
      trimTime = clock.now - start
      kept = trimmer.keptRanges(of: recording, sampleRate: 16_000).map {
        [Double($0.lowerBound) / 16_000, Double($0.upperBound) / 16_000]
      }
    }
    var text = ""
    var times: [Duration] = []
    for _ in 0..<repeats {
      let start = clock.now
      text = try await model.transcribe(input)
      times.append(clock.now - start)
    }
    let transcribeTime = times.sorted()[times.count / 2]
    let result = Result(
      id: item.id, variant: variant.map { String($0) } ?? "original",
      inputSeconds: Double(recording.count) / 16_000, outputSeconds: Double(input.count) / 16_000,
      trimMilliseconds: milliseconds(trimTime), transcribeMilliseconds: milliseconds(transcribeTime),
      kept: kept, text: text)
    handle.write(try encoder.encode(result) + Data("\n".utf8))
  }
  if number % 50 == 0 { print("\(number)/\(items.count)") }
}
try handle.close()

// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "TrimEval",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.4", traits: []),
    .package(url: "https://github.com/soniqo/speech-swift", exact: "0.0.28"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.6"),
  ],
  targets: [
    .executableTarget(
      name: "TrimEval",
      dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "Qwen3ASR", package: "speech-swift"),
        .product(name: "AudioCommon", package: "speech-swift"),
        .product(name: "MLX", package: "mlx-swift"),
      ]
    )
  ],
  swiftLanguageModes: [.v5]
)

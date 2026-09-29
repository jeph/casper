# Silence trimming evaluation

Measures what `Casper/Audio/SilenceTrimmer.swift` does to transcripts and transcription time.

1. Download LibriSpeech [test-clean](https://www.openslr.org/12) and the punctuated [LibriSpeech-PC](https://www.openslr.org/145) `test-clean.json`.
2. Build the recordings: `uv run build_dataset.py --librispeech <LibriSpeech/test-clean> --punctuated <test-clean.json> --out <dataset>`. Each joins one to three utterances with silence before, between, and after them, adds thinking pauses between words, and renders it quiet, with fan noise at 20 and 10 dB SNR, with background talkers, with a soft voice, and with a soft first 1.5 seconds. One recording in five has no pauses.
3. Build the harness with Xcode, since command-line SwiftPM can't build MLX's Metal shaders: `xcodebuild -scheme TrimEval -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath <build> -skipPackagePluginValidation -skipMacroValidation build` from `Harness`. Then run the models: `<build>/Build/Products/Release/TrimEval <parakeet|qwen3> <dataset>/manifest.jsonl results.jsonl 0.5,1.0 [--edge seconds] [--repeat N]`. Parakeet loads from Casper's installed `parakeet-ultra-coreml`; Qwen3-ASR loads from the path in `main.swift`.
4. Summarize: `uv run analyze.py <dataset>/manifest.jsonl results.jsonl`. "speech cut" counts audio the clean utterances had speech in that ended up in a cut; it errs toward flagging, so compare it with the word error rate.

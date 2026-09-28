# Casper

**Private, on-device dictation for the Mac.** Hold a shortcut, say what you mean, and clean, punctuated text appears wherever you're typing. Speech recognition and cleanup both run on your Mac, so your voice never leaves it.

Casper is a native macOS app written in Swift, built to get the most out of Apple silicon: speech models run on the Neural Engine or on the GPU with MLX, and cleanup runs on a local language model.

## Why Casper

- **Private by design.** Transcription and cleanup happen on your Mac, with no account and no cloud service. The only thing Casper downloads is the models you pick, from Hugging Face, and each file is checked against its published SHA-256 checksum.
- **A real Mac app.** Casper is built with Swift, SwiftUI and AppKit. It has no Electron, no bundled browser and no Python runtime. It lives in your menu bar, launches at login, and follows the macOS conventions you expect.
- **Made for Apple silicon.** Parakeet speech models run on the Neural Engine through Core ML. Qwen3-ASR speech models and the cleanup models run on the GPU with MLX, Apple's machine learning framework.
- **You never wait for the last dictation.** Start the next one while the previous one is still being processed. Each dictation moves through the pipeline as soon as it can, and the text still arrives in the order you spoke it.
- **Cleanup that keeps your words.** A local language model removes filler words and false starts, fixes punctuation, and handles self-corrections, so "send it Thursday, no wait, Friday" becomes "Send it Friday." It turns spoken punctuation, numbers, dates and prices into written form. When you dictate a question, Casper types the question instead of answering it. You can turn cleanup off to get the raw transcript.
- **Works wherever you type.** Text goes in through a paste, which works in nearly every app, including browsers, Electron apps and terminals. Casper puts your clipboard back afterward and marks the dictated text so clipboard managers don't save it.

## Built for speed

Casper is designed so dictation feels instant, from the moment you press the shortcut to the moment the text lands.

- **Models load while you talk.** Pressing the shortcut starts loading the models in the background, so they're usually ready by the time you finish speaking. You can keep the microphone and models ready between dictations for anywhere from no time at all to as long as Casper is running.
- **Neural Engine and GPU working together.** With a Parakeet speech model, the Neural Engine transcribes your latest dictation while the GPU cleans up the one before it.
- **Speculative decoding.** A cleaned-up transcript mostly repeats the transcript, so Casper guesses the next words from what you said and has the model check several of them in a single pass. This technique, called prompt lookup decoding, produces exactly the same text as decoding one word at a time, just faster. It's used with the Qwen3 cleanup models; Qwen3.5 and Qwen3.8 are built in a way that doesn't support it.
- **The cleanup instructions are read once.** The model processes the cleanup instructions when it loads and reuses that work for every dictation, so it only has to read your words.
- **No extended thinking.** Models that can think before they answer, such as Qwen3.5, have it turned off, since cleanup doesn't need it and it would slow every dictation down.

## Features

- **Push to talk** with any global shortcut (⌥Space by default). The shortcut doesn't need Input Monitoring permission. Recording continues for a moment after you let go so your last word isn't cut off, and pressing the shortcut again during that moment keeps the same recording going.
- **Voice bubble.** A small floating ghost shows a live waveform while you speak and animates while Casper transcribes. It stays above your windows on every Space, never takes focus from the app you're typing in, and remembers where you dragged it, even across displays. If something dictation needs is missing, such as a permission or a model, the bubble says what's wrong, and clicking it opens the Settings page that fixes it.
- **Microphone choice.** Use the system default or pick a specific input. Casper follows devices as they're plugged in and removed, and keeps recording through audio configuration changes.
- **Model library.** Download speech and language models in the sizes and precisions that suit your Mac, switch between them, and delete the ones you don't use. Downloads are verified before they're installed, so a failed download never leaves a half-installed model.
- **Respects your Mac.** Casper supports Reduce Motion and non-QWERTY keyboard layouts, and all of its text lives in String Catalogs, ready for translation.

## Models

| Speech model | Runs on | Languages |
|---|---|---|
| Parakeet TDT v3 and Parakeet Ultra (0.6B) | Neural Engine | 25 European languages |
| Qwen3-ASR (0.6B and 1.7B, 5-bit and 8-bit) | GPU, with MLX | 30 languages and 22 Chinese dialects, detected automatically |

| Cleanup model | Sizes | Languages |
|---|---|---|
| Qwen3 | 0.6B to 14B | 119 languages and dialects |
| Qwen3.5 | 0.8B to 9B | 201 languages and dialects |
| Qwen3.8 | 27B | 201 languages and dialects |

All cleanup models are 4-bit MLX conversions. Downloads range from about 350 MB to 16 GB, so you can match the model to your Mac's memory.

## Requirements

- A Mac with Apple silicon, running macOS 15 or later
- Microphone access, to hear you
- Accessibility access, to paste the text into the app you're using

## Build from source

There's no prebuilt release yet. To build Casper you need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't committed.

```sh
make run       # generate the project, build, and launch
make build     # generate and build only
make generate  # generate Casper.xcodeproj to work in Xcode
make lint      # check formatting with swift-format
make format    # apply swift-format
```

Settings opens the first time Casper launches. Grant microphone and Accessibility access, download a speech model, and download a cleanup model or turn off **Refine Transcripts** on the General page. Then hold ⌥Space and start talking.

## Translations

All user-facing text lives in String Catalogs: `Casper/Resources/Localizable.xcstrings` for the app and `Casper/Resources/InfoPlist.xcstrings` for system text such as the microphone permission prompt. Write UI text as string literals in SwiftUI (`Text("…")`, `Button("…")`), and Xcode adds them to the catalog when you build in Xcode. To add a language, open a catalog in Xcode and click **+** in the language list.

## Acknowledgments

Casper started as a native take on [OpenWhispr](https://github.com/OpenWhispr/openwhispr), and its cleanup prompt is adapted from OpenWhispr's.

## License

[MIT](LICENSE). Licenses and notices for the third-party code compiled into Casper are in [`Casper/Resources/Acknowledgements.txt`](Casper/Resources/Acknowledgements.txt), which ships inside the app.

# Casper

**Private, on-device dictation for the Mac.** Hold a shortcut, say what you mean, and clean, punctuated text appears wherever you're typing. Speech recognition and cleanup both run on your Mac, so your voice never leaves it.

Casper is a native macOS app written in Swift, built to get the most out of Apple silicon: speech models run on the Neural Engine or on the GPU with MLX, and cleanup runs on a local language model.

## Why Casper

- **Private by design.** Transcription and cleanup happen on your Mac, with no account and no cloud service. The only thing Casper downloads is the models you pick, from Hugging Face, and each file is checked against its published checksum.
- **A real Mac app.** Casper is built with Swift, SwiftUI and AppKit. It has no Electron, no bundled browser and no Python runtime. It lives in your menu bar, launches at login, and follows the macOS conventions you expect.
- **Made for Apple silicon.** Parakeet speech models run on the Neural Engine through Core ML. Qwen3-ASR speech models and the cleanup models run on the GPU with MLX, Apple's machine learning framework.
- **You never wait for the last dictation.** Start the next one while the previous one is still being processed. Each dictation moves through the pipeline as soon as it can, and the text still arrives in the order you spoke it.
- **Cleanup that keeps your words.** A local language model removes filler words and false starts, fixes punctuation, and handles self-corrections, so "send it Thursday, no wait, Friday" becomes "Send it Friday." It turns spoken punctuation, numbers, dates and prices into written form. When you dictate a question, Casper types the question instead of answering it. You can turn cleanup off to get the raw transcript.
- **Works wherever you type.** Text goes in through a paste, which works in nearly every app, including browsers, Electron apps and terminals. Casper puts your clipboard back afterward and marks the dictated text so clipboard managers that honor the [nspasteboard.org](http://nspasteboard.org) conventions skip it.

## Built for speed

Casper is designed so dictation feels instant, from the moment you press the shortcut to the moment the text lands.

- **Models stay loaded.** The speech and language models load when Casper starts and stay in memory, so no dictation waits for them. Switching models loads the new one in the background. You can also keep the microphone on between dictations for anywhere from no time at all to as long as Casper is running.
- **Neural Engine and GPU working together.** With a Parakeet speech model, the Neural Engine transcribes your latest dictation while the GPU cleans up the one before it.
- **Speculative decoding.** A cleaned-up transcript mostly repeats the transcript, so Casper guesses the next words from what you said and has the model check several of them in a single pass. This technique, called prompt lookup decoding, produces exactly the same text as decoding one word at a time, just faster. It's used with the Qwen3 cleanup models; Qwen3.5 and Qwen3.8 are built in a way that doesn't support it.
- **The cleanup instructions are read once.** The model processes the prompts of the default persona and of every persona pinned to a running app when it loads, and again in the background when you change a persona or a pin or open a pinned app, then reuses that work for every dictation, so it only has to read your words. A persona's processed prompt takes from tens of megabytes to over a gigabyte for a long one, so Casper drops it once no running app uses it.
- **No extended thinking.** Models that can think before they answer, such as Qwen3.5, have it turned off, since cleanup doesn't need it and it would slow every dictation down.

## Features

- **Hold or toggle** with any global shortcut (⌥Space by default). Hold the shortcut while you speak, or switch **Shortcut Mode** on the General page to press it once to start and again to stop. The shortcut doesn't need Input Monitoring permission. Recording continues for a moment after you stop so your last word isn't cut off, and pressing the shortcut again during that moment keeps the same recording going.
- **Personas.** Choose how cleanup writes on the Refine page: **Formal** fixes grammar and punctuation into polished writing, and **Casual** writes like a text message. The Options tab sets the default persona and pins personas to apps, so dictating into Slack can use Casual while Mail uses Formal; an app has one persona, and a persona can be pinned to any number of apps. Casper picks the persona of the app in front when you start dictating. On the Personas tab, create your own personas with a name, description, icon, and up to 5,000 words of instructions, or duplicate a built-in one to start from its prompt written out as instructions. Deleting a persona also deletes its app pins. Your own persona's instructions are its whole prompt: the model gets them and your transcript between `<transcript>` tags, nothing else.
- **History.** The History page in Settings lists every dictation, newest first, with exactly the text Casper typed: the cleaned-up text when Refine Transcripts is on, and the raw transcript when it's off. Search finds dictations by the words in them, highlighting each match. Select one or more dictations to copy or delete them, using the buttons under the list, the right-click menu, or the Delete key. The history is a database on your Mac, in `~/Library/Application Support/Casper/`, and is never sent anywhere. It's on by default. Turning off **Enable History** stops saving new dictations and offers to delete the ones already saved.
- **Dictionary.** Add names, brands and jargon on the Dictionary page so the speech model writes them the way you spell them. Qwen3-ASR reads your words as it transcribes. Parakeet can't be steered while it transcribes, so a second, 103 MB English model from FluidAudio, downloaded with Parakeet, checks the transcript against your voice and swaps in dictionary words where they fit better; it keeps the punctuation and capitalization Parakeet wrote. Each word can also list **Sounds Like** spellings, how Casper writes it when it gets it wrong, such as "Neve" for Niamh: Casper replaces those exact spellings with the word whatever the model, capitalizing it like the text it replaces. Changes apply to the next dictation without reloading the model, and the list stays fast with tens of thousands of words.
- **Automatically Add to Dictionary.** When you fix a word Casper typed, such as changing "Shivan" to "Siobhan", Casper can add your spelling to the dictionary. After each paste it watches the text field it pasted into, without changing anything there, and checks your edits each time you stop typing for 5 seconds. It keeps watching for a minute after the paste, even if you move elsewhere and come back, or paste more dictations into other fields, and stops sooner if Casper pastes into the same field again, if the field is emptied or closed, or if the app shows something else in it, such as another note. It skips everyday words, rewrites, and replacements spelled too differently from what Casper typed to be a mishearing of it. Then it transcribes the same recording again with your spelling in the dictionary, and only adds the word if the speech model now writes it in the same spot, so edits that change what you said, like "Friday" to "Thursday", are left out. The word is added with what Casper typed, such as "Shivan", as its Sounds Like spelling, so later dictations write your spelling there. This second transcription waits until Casper is otherwise idle, and starting a dictation stops it, so dictation doesn't wait for it. Recordings for it are kept in memory only, until the check is done. Each added word gets a silent notification with an **Undo** button; clicking the notification opens the Dictionary page. It's on by default and can be turned off with **Automatically Add to Dictionary** on the Dictionary page, and it only runs while the dictionary is on. Fields that don't expose their text to Accessibility, such as some terminals and Electron apps, aren't watched.
- **Voice bubble.** A small floating ghost shows a live waveform while you speak and animates while Casper transcribes. It stays above your windows on every Space, doesn't take focus from the app you're typing in, and remembers where you dragged it, even across displays. It fades out while an app in full screen on its display plays video, and comes back a few seconds after the video stops, as soon as you leave the video, or when you start dictating. Full-screen apps that aren't playing video, such as a terminal, keep the bubble. Clicking it while Casper is idle opens Settings, even when the menu bar icon is hidden. If something dictation needs is missing, such as a permission or a model, the bubble says what's wrong, and clicking it opens the Settings page that fixes it.
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
- Optionally, notifications, to tell you when a word is added to the dictionary from your corrections. Allow them on the Permissions page.

## Install

Casper is alpha software. Every change to `main` publishes a new release, numbered 0.0.x, signed with a Developer ID certificate and notarized by Apple.

With [Homebrew](https://brew.sh):

```sh
brew install --cask jeph/tap/casper
```

Or download `Casper-<version>.dmg` from the [latest release](https://github.com/jeph/casper/releases/latest), open it, and drag Casper to Applications.

The first time Casper launches, a short setup walks you through it: choose a voice model and a language model, which start downloading right away, allow microphone and Accessibility access, optionally allow notifications, and learn to dictate with ⌥Space or a shortcut of your own. Finishing setup opens Settings. Until you finish, setup starts over each time Casper launches.

## Build from source

To build Casper you need Xcode 27 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't committed, except for `Package.resolved`, which pins every package version.

```sh
make run       # generate the project, build, and launch
make build     # generate and build a debug app
make test      # run the unit tests
make archive   # build the optimized, stripped release app into build/Casper.xcarchive
make generate  # generate Casper.xcodeproj to work in Xcode
make lint      # check formatting with swift-format
make format    # apply swift-format
```

### Signing local builds

macOS ties Casper's Microphone and Accessibility permissions to the app's signature. Without a certificate, builds are signed ad hoc, the signature changes every time, and you have to grant both permissions again after each build. To avoid that, add a signing certificate to your keychain once:

1. In Xcode, open **Settings › Accounts** and sign in with your Apple ID.
2. Select your team, click **Manage Certificates**, then click **+** and choose **Developer ID Application** if your team is in the Apple Developer Program, or **Apple Development** otherwise.

After that, `make build`, `make run`, and `make archive` find the certificate and sign with it; there's nothing to configure. They prefer Developer ID, whose signature also matches the published releases, then Apple Development. If you have several certificates and want a specific one, set `LOCAL_SIGNING_IDENTITY` to its SHA-1 hash from `security find-identity -v -p codesigning`, in your environment or on the command line; set it to `-` to sign ad hoc.

## Translations

All user-facing text lives in String Catalogs: `Casper/Resources/Localizable.xcstrings` for the app and `Casper/Resources/InfoPlist.xcstrings` for system text such as the microphone permission prompt. Write UI text as string literals in SwiftUI (`Text("…")`, `Button("…")`), and Xcode adds them to the catalog when you build in Xcode. To add a language, open a catalog in Xcode and click **+** in the language list.

## Acknowledgments

Casper started as a native take on [OpenWhispr](https://github.com/OpenWhispr/openwhispr). Its formal cleanup prompt grew out of OpenWhispr's, and the way it finds your corrections in a text field is adapted from OpenWhispr's correction learner.

## License

[MIT](LICENSE). Licenses and notices for the third-party code compiled into Casper are in [`Casper/Resources/Acknowledgements.txt`](Casper/Resources/Acknowledgements.txt), which ships inside the app.

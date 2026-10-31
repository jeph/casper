import SwiftUI

struct AdvancedView: View {
  @AppStorage(SilenceTrimmer.enabledStorageKey) private var trimsSilence = true
  @AppStorage(LiveDictation.enabledStorageKey) private var transcribesWhileRecording = true
  @AppStorage(LiveDictation.openWordsStorageKey) private var openWords = LiveDictation.defaultOpenWords
  @AppStorage(TranscriptRefiner.enabledStorageKey) private var refinesTranscripts = true
  @AppStorage(PromptLookupTokenIterator.enabledStorageKey) private var promptLookupDecoding = true
  @AppStorage(PromptLookupTokenIterator.mostGuessesStorageKey) private var mostGuesses =
    PromptLookupTokenIterator.defaultMostGuesses
  @AppStorage(BufferCache.releaseStorageKey) private var releasesBufferCache = false

  var body: some View {
    Form {
      Section {
        Label {
          Text("Change these settings only if you know exactly what they do.")
          Text("Bad values can make Casper slower or less reliable.")
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
        }
      }
      Section {
        Toggle(isOn: $transcribesWhileRecording) {
          Label {
            Text("Transcribe While Recording")
            Text(
              "Transcribe and refine Parakeet dictations while you speak, so text arrives sooner after you stop. Personas that rewrite a whole dictation, such as into an email, may work better with this off."
            )
          } icon: {
            Image(systemName: "waveform.badge.mic")
          }
        }
        Toggle(isOn: $trimsSilence) {
          Label {
            Text("Trim Silence")
            Text(
              "Shorten silence and long pauses in recordings so they're transcribed faster. Can inadvertently trim voices in quiet or loud environments."
            )
          } icon: {
            Image(systemName: "scissors")
          }
        }
      } header: {
        Text("Transcription")
      }
      Section {
        LabeledContent {
          HStack {
            if openWords != LiveDictation.defaultOpenWords {
              Button("Reset to Default", systemImage: "arrow.counterclockwise") {
                openWords = LiveDictation.defaultOpenWords
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .help(Text("Reset to Default"))
            }
            Picker("Words Refined Again", selection: $openWords) {
              ForEach(LiveDictation.openWordsChoices, id: \.self) { count in
                Text(count, format: .number).tag(count)
              }
            }
            .labelsHidden()
            .fixedSize()
          }
        } label: {
          Label {
            Text("Words Refined Again")
            Text(
              "When transcribing while recording, at least this many of the latest refined words are refined again with the next sentences, so taking something back can still change them. Higher values are more accurate but slower."
            )
          } icon: {
            Image(systemName: "arrow.uturn.backward")
          }
        }
        .disabled(!transcribesWhileRecording)
        Toggle(isOn: $promptLookupDecoding) {
          Label {
            Text("Speculative Decoding")
            Text("Refine faster using token speculation on supported models.")
          } icon: {
            Image(systemName: "bolt")
          }
        }
        LabeledContent {
          HStack {
            if mostGuesses != PromptLookupTokenIterator.defaultMostGuesses {
              Button("Reset to Default", systemImage: "arrow.counterclockwise") {
                mostGuesses = PromptLookupTokenIterator.defaultMostGuesses
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .help(Text("Reset to Default"))
            }
            Picker("Guesses per Pass", selection: $mostGuesses) {
              ForEach(PromptLookupTokenIterator.mostGuessesRange, id: \.self) { count in
                Text(count, format: .number).tag(count)
              }
            }
            .labelsHidden()
            .fixedSize()
          }
        } label: {
          Label {
            Text("Guesses per Pass")
            Text(
              "The most tokens guessed at once. Higher values may improve inference speeds on higher end Macs and slow inference speeds on lower end Macs."
            )
          } icon: {
            Image(systemName: "number")
          }
        }
        .disabled(!promptLookupDecoding)
      } header: {
        Text("Refining")
      }
      .disabled(!refinesTranscripts)
      Section {
        Toggle(isOn: $releasesBufferCache) {
          Label {
            Text("Release Buffer Cache")
            Text("Reduces average memory usage at the cost of some slight latency.")
          } icon: {
            Image(systemName: "memorychip")
          }
        }
      } header: {
        Text("Memory")
      }
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
  }
}

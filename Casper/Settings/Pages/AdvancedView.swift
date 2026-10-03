import SwiftUI

struct AdvancedView: View {
  @AppStorage(SilenceTrimmer.enabledStorageKey) private var trimsSilence = true
  @AppStorage(TranscriptRefiner.enabledStorageKey) private var refinesTranscripts = true
  @AppStorage(PromptLookupTokenIterator.enabledStorageKey) private var promptLookupDecoding = true
  @AppStorage(PromptLookupTokenIterator.mostGuessesStorageKey) private var mostGuesses =
    PromptLookupTokenIterator.defaultMostGuesses
  @AppStorage(BufferCache.releaseStorageKey) private var releasesBufferCache = true

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

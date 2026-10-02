import SwiftUI

struct AdvancedView: View {
  @AppStorage(TranscriptRefiner.enabledStorageKey) private var refinesTranscripts = true
  @AppStorage(PromptLookupTokenIterator.enabledStorageKey) private var promptLookupDecoding = true
  @AppStorage(PromptLookupTokenIterator.mostGuessesStorageKey) private var mostGuesses =
    PromptLookupTokenIterator.defaultMostGuesses

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
        Toggle(isOn: $promptLookupDecoding) {
          Label {
            Text("Prompt Lookup Decoding")
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
              "The most tokens guessed at once. More can refine faster on Macs with more powerful GPUs, but each guess makes every pass slower, so on other Macs they can slow refining down."
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
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
  }
}

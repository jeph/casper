import SwiftUI

/// A sheet that adds a word to the dictionary or edits one.
struct WordEditor: View {
  @Environment(DictionaryStore.self) private var dictionary
  @Environment(\.dismiss) private var dismiss
  private let word: DictionaryWord
  private let isNew: Bool
  @State private var text: String
  /// The Sounds Like spellings as typed, separated by commas.
  @State private var soundsLike: String

  init(word: DictionaryWord, isNew: Bool) {
    self.word = word
    self.isNew = isNew
    _text = State(initialValue: word.text)
    _soundsLike = State(initialValue: word.soundsLike.joined(separator: ", "))
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(isNew ? "Add Word" : "Edit Word")
        .font(.headline)
        .padding(.top, 14)
      Form {
        Section {
          TextField("Word", text: $text, prompt: Text("Required"))
          TextField("Sounds Like", text: $soundsLike, prompt: Text("Optional"))
        } footer: {
          if isTaken {
            Text("“\(trimmedText)” is already in your dictionary.")
              .foregroundStyle(.red)
          } else {
            Text(
              "Spell the word as it should appear. Sounds Like is how Casper writes it when it gets it wrong, such as “Neve” for Niamh. Casper replaces those with the word. Separate several with commas."
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      Divider()
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button(isNew ? "Add" : "Save") {
          dictionary.save(
            DictionaryWord(id: word.id, text: text, soundsLike: soundsLike.split(separator: ",").map(String.init))
          )
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(trimmedText.isEmpty || isTaken)
      }
      .padding(16)
    }
    .frame(width: 480, height: 262)
  }

  private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var isTaken: Bool { dictionary.isTaken(trimmedText, exceptBy: word.id) }
}

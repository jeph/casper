import SwiftUI

/// The words in the user's dictionary, with search, a selection to edit or delete, and a switch for the dictionary.
///
/// The whole dictionary is kept in memory and listed at once: it's short strings, and the list only makes the rows on
/// screen, so it stays fast with tens of thousands of words.
struct DictionaryView: View {
  @Environment(DictionaryStore.self) private var dictionary
  @AppStorage(DictionaryStore.enabledStorageKey) private var isEnabled = true

  @State private var query = ""
  @State private var selection = Set<DictionaryWord.ID>()
  /// The word open in the editor, which is a new one if the dictionary doesn't have it yet.
  @State private var editing: DictionaryWord?
  @State private var confirmsDeletingSelection = false

  /// The page's margin around both cards.
  private static let margin: CGFloat = 16
  /// How far the search field and the list sit inside the words card.
  private static let cardInset: CGFloat = 8

  var body: some View {
    VStack(spacing: 12) {
      enableCard
      wordsCard
    }
    .padding(Self.margin)
    // A click anywhere on the page outside the list's rows and controls clears the selection.
    .background {
      Color.clear
        .contentShape(.rect)
        .onTapGesture { selection.removeAll() }
    }
    .sheet(item: $editing) { word in
      WordEditor(word: word, isNew: !dictionary.words.contains { $0.id == word.id })
    }
    // Words a new search hides would otherwise stay selected, and be edited or deleted unseen.
    .onChange(of: query) {
      selection.removeAll()
    }
    .alert(Text(deleteTitle), isPresented: $confirmsDeletingSelection) {
      Button("Delete", role: .destructive) {
        delete(selection)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This can't be undone.")
    }
  }

  // MARK: Cards

  private var enableCard: some View {
    HStack(spacing: 12) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("Use Dictionary")
          Text("Help Casper recognize names, brands, and jargon.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "character.book.closed")
      }
      .labelStyle(.settings)
      Spacer(minLength: 0)
      Toggle("Use Dictionary", isOn: $isEnabled)
        .toggleStyle(.switch)
        .labelsHidden()
    }
    .padding(.horizontal, Self.cardInset * 2)
    .padding(.vertical, 10)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  private var wordsCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !dictionary.words.isEmpty {
        SearchField(text: $query, prompt: String(localized: "Search \(dictionary.words.count.formatted()) Words"))
          .padding(.bottom, Self.cardInset)
      }
      List(selection: $selection) {
        content
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .systemSelectionHighlightHidden()
      .contextMenu(forSelectionType: DictionaryWord.ID.self) { ids in
        if !ids.isEmpty {
          actions(for: ids)
        }
      } primaryAction: { ids in
        edit(ids)
      }
      .onDeleteCommand { requestDelete(selection) }
      .onExitCommand { selection.removeAll() }
      if !dictionary.words.isEmpty {
        Divider()
          .padding(.horizontal, -Self.cardInset)
        footer
          .padding(.top, Self.cardInset)
          .padding(.horizontal, Self.cardInset)
          // A click on the footer outside its buttons clears the selection, like one outside the card.
          .contentShape(.rect)
          .onTapGesture { selection.removeAll() }
      }
    }
    .padding(Self.cardInset)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  /// Add Word, or what can be done with the selected words while there are any, in the same place so the list
  /// doesn't move when the selection changes.
  private var footer: some View {
    HStack(spacing: 12) {
      if selection.isEmpty {
        Spacer()
        addButton
      } else {
        Text("\(selection.count) Selected")
          .foregroundStyle(.secondary)
        Spacer()
        actions(for: selection)
      }
    }
  }

  private var addButton: some View {
    Button("Add Word", systemImage: "plus") {
      editing = DictionaryWord(text: "")
    }
  }

  // MARK: List

  @ViewBuilder
  private var content: some View {
    if dictionary.words.isEmpty {
      ContentUnavailableView {
        Label("No Words", systemImage: "character.book.closed")
      } description: {
        Text("Add names, brands, and jargon that Casper doesn't recognize.")
      } actions: {
        Button("Add Word") {
          editing = DictionaryWord(text: "")
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 40)
      .selectionDisabled()
      .listRowSeparator(.hidden)
    } else if filteredWords.isEmpty {
      ContentUnavailableView.search(text: query)
        .frame(maxWidth: .infinity)
        .selectionDisabled()
        .listRowSeparator(.hidden)
    } else {
      ForEach(filteredWords) { word in
        WordRow(word: word)
          .tag(word.id)
          // The gray a Mac list uses for a selection while it doesn't have focus, so it looks the same either way.
          .listRowBackground(
            selection.contains(word.id) ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : nil
          )
      }
    }
  }

  /// The words whose spelling or Sounds Like spellings contain the search.
  private var filteredWords: [DictionaryWord] {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return dictionary.words }
    return dictionary.words.filter { word in
      word.text.localizedCaseInsensitiveContains(query)
        || word.soundsLike.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  // MARK: Actions

  /// Edit, for a single word, and Delete, the same in the selection bar and the right-click menu.
  @ViewBuilder
  private func actions(for ids: Set<DictionaryWord.ID>) -> some View {
    if ids.count == 1 {
      Button("Edit", systemImage: "pencil") {
        edit(ids)
      }
    }
    Button("Delete", systemImage: "trash", role: .destructive) {
      requestDelete(ids)
    }
  }

  private func edit(_ ids: Set<DictionaryWord.ID>) {
    guard ids.count == 1, let word = dictionary.words.first(where: { ids.contains($0.id) }) else { return }
    editing = word
  }

  /// Selects the words and asks before deleting them, however many there are.
  private func requestDelete(_ ids: Set<DictionaryWord.ID>) {
    guard !ids.isEmpty else { return }
    selection = ids
    confirmsDeletingSelection = true
  }

  /// The delete confirmation's title: the word itself, such as "Delete “Siobhan”?", or how many words, such as
  /// "Delete 3 Words?", which an alert shows without inflecting it.
  private var deleteTitle: String {
    if selection.count == 1, let word = dictionary.words.first(where: { selection.contains($0.id) }) {
      return String(localized: "Delete “\(word.text)”?")
    }
    return String(AttributedString(localized: "Delete ^[\(selection.count) Word](inflect: true)?").characters)
  }

  private func delete(_ ids: Set<DictionaryWord.ID>) {
    guard !ids.isEmpty else { return }
    dictionary.delete(ids)
    selection.subtract(ids)
  }
}

private struct WordRow: View {
  let word: DictionaryWord

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(word.text)
      if !word.soundsLike.isEmpty {
        Text("Sounds like \(word.soundsLike.formatted(.list(type: .or)))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

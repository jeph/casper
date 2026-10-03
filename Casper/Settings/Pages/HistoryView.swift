import AppKit
import OSLog
import SwiftUI

/// Every dictation in the history, newest first, with search and a selection to copy or delete.
///
/// The list loads a page at a time as it scrolls, so a long history doesn't slow the page down.
struct HistoryView: View {
  @Environment(DictationHistory.self) private var history
  @AppStorage(DictationHistory.enabledStorageKey) private var isEnabled = true

  @State private var query = ""
  /// The dictations read so far, newest first, which grows a page at a time as the list scrolls.
  @State private var loaded: [Dictation] = []
  @State private var hasMore = true
  /// Counts the times the list started over, so dictations read for an earlier list aren't added to the new one.
  @State private var listGeneration = 0
  /// The page being read, cancelled when a new search starts over so its dictations don't land in the new list.
  @State private var pageLoad: Task<Void, Never>?
  @State private var loadError: String?
  @State private var matchCount = 0
  @State private var selection = Set<Int64>()
  @State private var showsCopied = false
  @State private var confirmsDeletingSelection = false
  @State private var asksToDeleteHistory = false
  @State private var deleteError: String?
  /// The list's width, and the part of it rows get, which is narrower when the Mac shows scroll bars all the time.
  @State private var listWidth: CGFloat = 0
  @State private var rowWidth: CGFloat = 0

  private static let pageSize = 50
  /// The page's side margin, so both cards and the selection bar share the same edges.
  private static let margin: CGFloat = 16
  /// How far the search field and the list sit inside the history card.
  ///
  /// Rows add the same again before their text, which lines it up with the Enable History card's text.
  private static let cardInset: CGFloat = 8

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "History")

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 12) {
        enableHistoryCard
        historyCard
      }
      .padding(Self.margin)
      selectionBar
    }
    // A click anywhere on the page outside the list's rows and controls clears the selection.
    .background {
      Color.clear
        .contentShape(.rect)
        .onTapGesture { selection.removeAll() }
    }
    .alert("Delete Your Dictation History?", isPresented: $asksToDeleteHistory) {
      Button("Delete History", role: .destructive) {
        Task { await deleteAll() }
      }
      Button("Keep History", role: .cancel) {}
    } message: {
      Text(
        "Casper will stop saving new dictations. You can also delete the \(history.count.formatted()) dictations already saved on this Mac. This can't be undone."
      )
    }
    .alert(Text(deleteTitle), isPresented: $confirmsDeletingSelection) {
      Button("Delete", role: .destructive) {
        let ids = selection
        Task { await delete(ids) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This can't be undone.")
    }
    .alert("Couldn't Delete Dictations", isPresented: showsDeleteError) {
      Button("OK") {}
    } message: {
      Text(deleteError ?? "")
    }
    .task(id: query) {
      // A search waits for typing to pause, and starts over from the newest match.
      if !query.isEmpty {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
      }
      await reload()
    }
    .onChange(of: history.saves) {
      Task { await showNewDictations() }
    }
  }

  // MARK: Cards

  private var enableHistoryCard: some View {
    HStack(spacing: 12) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("Enable History")
          Text("Keep a copy of every dictation.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "clock.arrow.circlepath")
      }
      .labelStyle(.settings)
      Spacer(minLength: 0)
      Toggle("Enable History", isOn: enablesHistory)
        .toggleStyle(.switch)
        .labelsHidden()
    }
    .padding(.horizontal, Self.cardInset * 2)
    .padding(.vertical, 10)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  private var historyCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      if history.count > 0 || !query.isEmpty {
        searchArea
      }
      List(selection: $selection) {
        content
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .systemSelectionHighlightHidden()
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.containerSize.width
      } action: { _, width in
        rowWidth = width
      }
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { width in
        listWidth = width
      }
      .contextMenu(forSelectionType: Int64.self) { ids in
        if !ids.isEmpty {
          actions(for: ids)
        }
      }
      .onDeleteCommand { requestDelete(selection) }
      .onExitCommand { selection.removeAll() }
    }
    .padding(Self.cardInset)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  /// The search field spans the list's rows, leaving out a scroll bar that's always shown, with the result count
  /// under it so the field never narrows.
  private var searchArea: some View {
    VStack(alignment: .leading, spacing: 6) {
      SearchField(text: $query, prompt: String(localized: "Search \(history.count.formatted()) Dictations"))
      if !query.isEmpty && matchCount > 0 {
        Text(matchCount == 1 ? "1 Result" : "\(matchCount.formatted()) Results")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .padding(.leading, Self.cardInset)
      }
    }
    .padding(.trailing, scrollerWidth)
    .padding(.bottom, Self.cardInset)
  }

  // MARK: List

  @ViewBuilder
  private var content: some View {
    if let loadError {
      ContentUnavailableView {
        Label("Couldn't Load History", systemImage: "exclamationmark.triangle")
      } description: {
        Text(loadError)
      }
      .frame(maxWidth: .infinity)
      .selectionDisabled()
      .listRowSeparator(.hidden)
    } else if loaded.isEmpty && !hasMore {
      emptyState
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .selectionDisabled()
        .listRowSeparator(.hidden)
    } else {
      ForEach(days, id: \.day) { group in
        Section {
          ForEach(group.dictations) { dictation in
            DictationRow(dictation: dictation, query: query)
              .tag(dictation.id)
              // The gray a Mac list uses for a selection while it doesn't have focus, so it looks the same either way.
              .listRowBackground(
                selection.contains(dictation.id)
                  ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : nil
              )
          }
        } header: {
          Self.title(for: group.day)
        }
      }
      if hasMore {
        loadingFooter
          .selectionDisabled()
          .listRowSeparator(.hidden)
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if !query.isEmpty {
      ContentUnavailableView.search(text: query)
    } else {
      ContentUnavailableView {
        Label("No Dictations", systemImage: "text.bubble")
      } description: {
        Text(
          isEnabled
            ? "Text you dictate appears here, exactly as Casper typed it."
            : "Turn on history to keep the text you dictate."
        )
      }
    }
  }

  /// Loads the next page whenever it's in view, including after deletions empty the list, so scrolling never stops
  /// at a button.
  private var loadingFooter: some View {
    HStack(spacing: 6) {
      ProgressView()
        .controlSize(.small)
      Text(loaded.isEmpty ? "Loading dictations…" : "Loading older dictations…")
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .task(id: loaded.count) {
      await loadMore()
    }
  }

  private var days: [(day: Date, dictations: [Dictation])] {
    let calendar = Calendar.current
    var groups: [(day: Date, dictations: [Dictation])] = []
    for dictation in loaded {
      let day = calendar.startOfDay(for: dictation.date)
      if groups.last?.day == day {
        groups[groups.count - 1].dictations.append(dictation)
      } else {
        groups.append((day, [dictation]))
      }
    }
    return groups
  }

  private static func title(for day: Date) -> Text {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) {
      return Text("Today")
    }
    if calendar.isDateInYesterday(day) {
      return Text("Yesterday")
    }
    if let days = calendar.dateComponents([.day], from: day, to: .now).day, days < 7 {
      return Text(day, format: .dateTime.weekday(.wide))
    }
    return Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
  }

  // MARK: Selection bar

  @ViewBuilder
  private var selectionBar: some View {
    if !selection.isEmpty {
      HStack(spacing: 12) {
        Text("\(selection.count) Selected")
          .foregroundStyle(.secondary)
        Spacer()
        actions(for: selection)
      }
      .padding(.horizontal, Self.margin)
      .padding(.vertical, 10)
      .background(.bar)
      .overlay(alignment: .top) { Divider() }
    }
  }

  // MARK: Actions

  /// Room the list keeps for a scroll bar that's always shown, which the search field leaves out too.
  private var scrollerWidth: CGFloat {
    rowWidth > 0 ? max(0, listWidth - rowWidth) : 0
  }

  private var enablesHistory: Binding<Bool> {
    Binding {
      isEnabled
    } set: { enabled in
      isEnabled = enabled
      if !enabled && history.count > 0 {
        asksToDeleteHistory = true
      }
    }
  }

  private var showsDeleteError: Binding<Bool> {
    Binding {
      deleteError != nil
    } set: { isPresented in
      if !isPresented {
        deleteError = nil
      }
    }
  }

  /// Copies dictations oldest first, in the order they were spoken, separated by blank lines.
  ///
  /// History never leaves this Mac, so the copy isn't offered to other devices through Universal Clipboard.
  private func copy(_ ids: Set<Int64>) {
    let text = loaded.filter { ids.contains($0.id) }.reversed().map(\.text).joined(separator: "\n\n")
    let pasteboard = NSPasteboard.general
    pasteboard.prepareForNewContents(with: .currentHostOnly)
    pasteboard.setString(text, forType: .string)
    showsCopied = true
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      showsCopied = false
    }
  }

  /// Copy and Delete, the same in the selection bar and the right-click menu however many dictations they act on.
  @ViewBuilder
  private func actions(for ids: Set<Int64>) -> some View {
    Button {
      copy(ids)
    } label: {
      // Sized for both titles and icons, with the one shown centered, so switching to Copied doesn't resize the
      // button or the selection bar, which would nudge the history card above it.
      ZStack {
        Label("Copy", systemImage: "doc.on.doc").hidden()
        Label("Copied", systemImage: "checkmark").hidden()
        Label(showsCopied ? "Copied" : "Copy", systemImage: showsCopied ? "checkmark" : "doc.on.doc")
      }
    }
    .contentTransition(.symbolEffect(.replace))
    Button("Delete", systemImage: "trash", role: .destructive) {
      requestDelete(ids)
    }
  }

  /// Selects the dictations and asks before deleting them, however many there are.
  private func requestDelete(_ ids: Set<Int64>) {
    guard !ids.isEmpty else { return }
    selection = ids
    confirmsDeletingSelection = true
  }

  /// Deletes dictations from the history and the list.
  ///
  /// The loading footer tops the list back up if it comes into view.
  private func delete(_ ids: Set<Int64>) async {
    do {
      try await history.delete(ids)
    } catch {
      Self.logger.error("Couldn't delete dictations from the history: \(error)")
      deleteError = String(describing: error)
      return
    }
    withAnimation {
      loaded.removeAll { ids.contains($0.id) }
    }
    selection.subtract(ids)
    if !query.isEmpty {
      matchCount = (try? await history.count(matching: query)) ?? matchCount
    }
  }

  private func deleteAll() async {
    do {
      try await history.deleteAll()
    } catch {
      Self.logger.error("Couldn't delete the history: \(error)")
      deleteError = String(describing: error)
    }
    await reload()
  }

  /// The delete confirmation's title, such as "Delete 1 Dictation?", which an alert shows without inflecting it.
  private var deleteTitle: String {
    String(AttributedString(localized: "Delete ^[\(selection.count) Dictation](inflect: true)?").characters)
  }

  /// Starts the list over from the newest dictation that matches the search.
  private func reload() async {
    pageLoad?.cancel()
    pageLoad = nil
    listGeneration += 1
    loaded = []
    hasMore = true
    loadError = nil
    selection.removeAll()
    if !query.isEmpty {
      matchCount = (try? await history.count(matching: query)) ?? 0
    }
    await loadMore()
  }

  private func loadMore() async {
    guard hasMore, pageLoad == nil, loadError == nil else { return }
    let query = query
    let cursor = loaded.last
    let load = Task {
      do {
        let page = try await history.page(matching: query, before: cursor, limit: Self.pageSize)
        guard !Task.isCancelled else { return }
        loaded += page
        hasMore = page.count == Self.pageSize
      } catch {
        guard !Task.isCancelled else { return }
        Self.logger.error("Couldn't read the history: \(error)")
        loadError = String(describing: error)
      }
      pageLoad = nil
    }
    pageLoad = load
    await load.value
  }

  /// Lists dictations saved while the page is open above the ones already there.
  ///
  /// Saves can arrive faster than they're read, so reads overlap and some dictations come back from more than one of
  /// them; only the ones not listed yet are added. Dictations are saved in the order they were spoken, so those are
  /// always newer than every listed one. A read is dropped if the search changed or the list started over in the
  /// meantime, since it was made for a list that's no longer shown.
  private func showNewDictations() async {
    guard let newest = loaded.first else {
      await reload()
      return
    }
    let searched = query
    let generation = listGeneration
    do {
      let newer = try await history.dictations(matching: searched, after: newest)
      guard query == searched, listGeneration == generation else { return }
      let listed = Set(loaded.map(\.id))
      let unlisted = newer.filter { !listed.contains($0.id) }
      guard !unlisted.isEmpty else { return }
      withAnimation {
        loaded.insert(contentsOf: unlisted, at: 0)
      }
      matchCount += unlisted.count
    } catch {
      Self.logger.error("Couldn't read new dictations from the history: \(error)")
    }
  }
}

private struct DictationRow: View {
  let dictation: Dictation
  let query: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(highlighted)
        .fixedSize(horizontal: false, vertical: true)
      Text(dictation.date, format: .dateTime.hour().minute())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  /// The text with the searched words marked, the way Find marks matches in other Mac apps.
  private var highlighted: AttributedString {
    var text = AttributedString(dictation.text)
    for match in HistorySearch.matches(of: query, in: dictation.text) {
      guard let range = Range(match, in: text) else { continue }
      text[range].backgroundColor = .yellow
      text[range].foregroundColor = .black
    }
    return text
  }
}

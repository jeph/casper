import Foundation
import Testing

@MainActor
final class DictionaryStoreTests {
  private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  private let suiteName = UUID().uuidString
  private let defaults: UserDefaults

  init() {
    defaults = UserDefaults(suiteName: suiteName) ?? .standard
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  private var fileURL: URL { directory.appending(path: "Dictionary.json") }

  private func makeStore() -> DictionaryStore {
    DictionaryStore(fileURL: fileURL, defaults: defaults)
  }

  @Test func startsEmpty() {
    #expect(makeStore().words.isEmpty)
  }

  @Test func keepsWordsInAlphabeticalOrderAcrossLaunches() {
    let store = makeStore()
    for text in ["Tailscale", "aoife", "MLX", "Jeph"] {
      store.save(DictionaryWord(text: text))
    }
    #expect(store.words.map(\.text) == ["aoife", "Jeph", "MLX", "Tailscale"])
    #expect(makeStore().words == store.words)
  }

  @Test func savingTidiesTheWordAndItsSoundsLikeSpellings() {
    let store = makeStore()
    store.save(
      DictionaryWord(
        text: "  Tailscale \n",
        soundsLike: [" tail   scale ", "", "Tail Scale", "Tailscale", "tailscale"]
      )
    )
    #expect(store.words.first?.text == "Tailscale")
    // Repeats regardless of case go, and so does a spelling identical to the word, but not one differing in case.
    #expect(store.words.first?.soundsLike == ["tail scale", "tailscale"])
  }

  @Test func emptyWordsArentSaved() {
    let store = makeStore()
    store.save(DictionaryWord(text: "  \n", soundsLike: ["Jeff"]))
    #expect(store.words.isEmpty)
  }

  @Test func wordsAreTakenIgnoringCaseAndSurroundingSpaces() {
    let store = makeStore()
    let jeph = DictionaryWord(text: "Jeph")
    store.save(jeph)
    #expect(store.isTaken(" jeph ", exceptBy: nil))
    #expect(!store.isTaken("JEPH", exceptBy: jeph.id))
    #expect(!store.isTaken("Jephs", exceptBy: nil))
    store.save(DictionaryWord(text: "JEPH", soundsLike: ["Jeff"]))
    #expect(store.words == [jeph])
  }

  @Test func savingAnExistingWordReplacesIt() {
    let store = makeStore()
    let word = DictionaryWord(text: "Neve")
    store.save(word)
    store.save(DictionaryWord(id: word.id, text: "Niamh", soundsLike: ["Neve"]))
    #expect(store.words == [DictionaryWord(id: word.id, text: "Niamh", soundsLike: ["Neve"])])
    #expect(makeStore().words == store.words)
  }

  @Test func deletedWordsStayDeleted() {
    let store = makeStore()
    let jeph = DictionaryWord(text: "Jeph")
    let niamh = DictionaryWord(text: "Niamh")
    let qwen = DictionaryWord(text: "Qwen")
    for word in [jeph, niamh, qwen] {
      store.save(word)
    }
    store.delete([jeph.id, qwen.id])
    #expect(store.words == [niamh])
    #expect(makeStore().words == [niamh])
  }

  @Test func dictationsGetNoWordsWhileTheDictionaryIsOff() {
    let store = makeStore()
    let jeph = DictionaryWord(text: "Jeph")
    store.save(jeph)
    #expect(store.isEnabled)
    #expect(store.wordsForDictation == [jeph])
    defaults.set(false, forKey: DictionaryStore.enabledStorageKey)
    #expect(store.wordsForDictation.isEmpty)
    #expect(store.words == [jeph])
  }

  @Test func correctionsAreLearnedOnlyWhileBothSwitchesAreOn() {
    let store = makeStore()
    #expect(store.learnsCorrections)
    defaults.set(false, forKey: DictionaryStore.enabledStorageKey)
    #expect(!store.learnsCorrections)
    defaults.set(true, forKey: DictionaryStore.enabledStorageKey)
    defaults.set(false, forKey: DictionaryStore.learnsCorrectionsStorageKey)
    #expect(!store.learnsCorrections)
  }

  @Test func deletingBySpellingIgnoresCaseAndKeepsOtherWords() {
    let store = makeStore()
    let sinead = DictionaryWord(text: "Sinead")
    store.save(DictionaryWord(text: "Siobhan", soundsLike: ["Shivan"]))
    store.save(sinead)
    store.delete(spelled: "siobhan")
    #expect(store.words == [sinead])
    #expect(makeStore().words == [sinead])
    // A spelling only listed as Sounds Like, or not in the dictionary at all, deletes nothing.
    store.save(DictionaryWord(text: "Niamh", soundsLike: ["Neve"]))
    store.delete(spelled: "Neve")
    store.delete(spelled: "Saoirse")
    #expect(store.words.map(\.text) == ["Niamh", "Sinead"])
  }

  @Test func anUnreadableFileStartsEmpty() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: fileURL)
    #expect(makeStore().words.isEmpty)
  }
}

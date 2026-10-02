import Foundation
import Testing

@MainActor
final class PersonaStoreTests {
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

  private var fileURL: URL { directory.appending(path: "Personas.json") }

  private func makeStore() -> PersonaStore {
    PersonaStore(fileURL: fileURL, defaults: defaults)
  }

  private func custom(_ name: String) -> RefinePersona {
    RefinePersona(id: UUID().uuidString, name: name, summary: "", systemImage: "star", instructions: "Write \(name).")
  }

  @Test func startsWithTheBuiltInPersonasAndFormalChosen() {
    let store = makeStore()
    #expect(store.personas == RefinePersona.builtIns)
    #expect(store.selected == .formal)
  }

  @Test func builtInPersonasCantBeChanged() {
    var edited = RefinePersona.casual
    edited.instructions = "Write in lowercase."
    let store = makeStore()
    store.save(edited)
    #expect(store.personas == RefinePersona.builtIns)
    #expect(makeStore().personas == RefinePersona.builtIns)
  }

  /// A file with built-in personas in it, such as one saved when they could be edited, still loads the user's own.
  @Test func builtInPersonasInTheFileAreIgnored() throws {
    var edited = RefinePersona.casual
    edited.instructions = "Write in lowercase."
    let slack = custom("Slack")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode([edited, slack]).write(to: fileURL)
    #expect(makeStore().personas == RefinePersona.builtIns + [slack])
  }

  @Test func userPersonasFollowTheBuiltInsInTheOrderAdded() {
    let store = makeStore()
    let slack = custom("Slack")
    let email = custom("Email")
    store.save(slack)
    store.save(email)
    #expect(makeStore().personas == RefinePersona.builtIns + [slack, email])
  }

  @Test func savingTrimsNameAndSummary() {
    let store = makeStore()
    var persona = custom("Slack")
    persona.name = "  Slack \n"
    persona.summary = " Work chat. "
    store.save(persona)
    #expect(store.personas.last?.name == "Slack")
    #expect(store.personas.last?.summary == "Work chat.")
  }

  @Test func namesAreTakenIgnoringCaseAndSurroundingSpaces() {
    let store = makeStore()
    #expect(store.isNameTaken(" formal ", exceptBy: nil))
    #expect(store.isNameTaken("CASUAL", exceptBy: RefinePersona.formal.id))
    #expect(!store.isNameTaken("Formal", exceptBy: RefinePersona.formal.id))
    #expect(!store.isNameTaken("Formality", exceptBy: nil))
  }

  @Test func duplicatesGetTheFirstFreeCopyName() {
    let store = makeStore()
    let first = store.duplicate(.formal)
    let second = store.duplicate(.formal)
    #expect(first.name == "Formal Copy")
    #expect(second.name == "Formal Copy 2")
    #expect(first.instructions == RefinePersona.formal.instructions)
    #expect(!first.isBuiltIn)
    #expect(first.id != second.id)
  }

  /// A long name is shortened so the copy suffix and number still fit, rather than cutting them off.
  @Test func duplicateNamesStayWithinTheNameLimit() {
    let store = makeStore()
    let long = custom(String(repeating: "a", count: RefinePersona.nameLimit))
    store.save(long)
    let first = store.duplicate(long)
    let second = store.duplicate(long)
    #expect(first.name.count == RefinePersona.nameLimit)
    #expect(second.name.count == RefinePersona.nameLimit)
    #expect(first.name.hasSuffix("a Copy"))
    #expect(second.name.hasSuffix("a Copy 2"))
  }

  @Test func deletingTheChosenPersonaChoosesFormal() {
    let store = makeStore()
    let slack = custom("Slack")
    store.save(slack)
    store.selectedID = slack.id

    store.delete(slack)

    #expect(store.selected == .formal)
    #expect(makeStore().personas == RefinePersona.builtIns)
  }

  @Test func builtInPersonasCantBeDeleted() {
    let store = makeStore()
    store.delete(.casual)
    #expect(store.personas == RefinePersona.builtIns)
  }

  @Test func chosenPersonaIsRestoredOnLaunch() {
    let store = makeStore()
    let slack = custom("Slack")
    store.save(slack)
    store.selectedID = slack.id
    #expect(makeStore().selected == slack)
  }

  @Test func unknownChosenPersonaFallsBackToFormal() {
    defaults.set("deleted", forKey: RefinePersona.storageKey)
    #expect(makeStore().selected == .formal)
  }

  @Test func unreadableFileLeavesTheBuiltInPersonas() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: fileURL)
    #expect(makeStore().personas == RefinePersona.builtIns)
  }
}

struct RefinePersonaTests {
  @Test func builtInInstructionsFitTheWordLimit() {
    for persona in RefinePersona.builtIns {
      #expect(RefinePersona.wordCount(of: persona.instructions) <= RefinePersona.instructionWordLimit)
    }
  }

  @Test func wordCountIgnoresPunctuationAndSpacing() {
    #expect(RefinePersona.wordCount(of: "  Hello,   world!\nIt's fine.  ") == 4)
    #expect(RefinePersona.wordCount(of: " \n ") == 0)
  }

  /// Text without spaces still counts word by word, so the limit holds for languages like Chinese.
  @Test func wordCountSplitsTextWrittenWithoutSpaces() {
    #expect(RefinePersona.wordCount(of: "我们明天去公园散步") > 1)
  }
}

struct RefinePromptTests {
  /// A persona the user wrote sends its instructions and the tagged transcript, with nothing else added that Settings
  /// doesn't mention.
  @Test func userPersonaSendsItsInstructionsThenTheTaggedTranscript() {
    let persona = RefinePersona(
      id: UUID().uuidString,
      name: "Slack",
      summary: "",
      systemImage: "star",
      instructions: "Instructions."
    )
    let transcript = "  um, so <b>hey</b>\nwhat's up "
    #expect(
      RefinePrompt.messages(for: transcript, persona: persona) == [
        ["role": "system", "content": "Instructions."],
        ["role": "user", "content": "<transcript>\n\(transcript)\n</transcript>"],
      ]
    )
  }

  /// A duplicate of a built-in persona sends the built-in's prompt written out as its instructions, not the
  /// built-in's own prompt, which the user couldn't see or edit.
  @Test(arguments: RefinePersona.builtIns)
  func duplicateOfBuiltInSendsItsInstructions(builtIn: RefinePersona) {
    let duplicate = RefinePersona(
      id: UUID().uuidString,
      name: builtIn.name,
      summary: builtIn.summary,
      systemImage: builtIn.systemImage,
      instructions: builtIn.instructions
    )
    let messages = RefinePrompt.messages(for: "hey", persona: duplicate)
    #expect(messages.count == 2)
    #expect(messages.first?["content"] == builtIn.instructions)
    #expect(RefinePrompt.messages(for: "hey", persona: builtIn).count > 2)
  }

  /// Everything before the transcript is the same for every transcript, so the refiner can cache it.
  @Test(arguments: RefinePersona.builtIns)
  func builtInPromptsOnlyChangeInTheLastMessage(builtIn: RefinePersona) {
    let first = RefinePrompt.messages(for: "first transcript", persona: builtIn)
    let second = RefinePrompt.messages(for: "second transcript", persona: builtIn)
    #expect(first.dropLast() == second.dropLast())
    #expect(first.last?["content"]?.contains("first transcript") == true)
  }
}

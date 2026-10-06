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

  @Test func appsWithoutAPinUseTheChosenPersona() {
    let store = makeStore()
    store.selectedID = RefinePersona.casual.id
    store.pin(RefinePersona.formal.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    #expect(store.persona(forApp: "com.tinyspeck.slackmacgap") == .formal)
    #expect(store.persona(forApp: "com.apple.mail") == .casual)
    #expect(store.persona(forApp: nil) == .casual)
  }

  @Test func anAppHasOnePersona() {
    let store = makeStore()
    store.pin(RefinePersona.formal.id, toApp: "com.hnc.Discord", named: "Discord")
    store.pin(RefinePersona.casual.id, toApp: "com.hnc.Discord", named: "Discord")
    #expect(store.appPersonas.map(\.personaID) == [RefinePersona.casual.id])
  }

  @Test func unknownPersonasCantBePinned() {
    let store = makeStore()
    store.pin("deleted", toApp: "com.hnc.Discord", named: "Discord")
    #expect(store.appPersonas.isEmpty)
  }

  @Test func deletingAPersonaDeletesItsPins() {
    let store = makeStore()
    let slack = custom("Slack")
    store.save(slack)
    store.pin(slack.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    store.pin(RefinePersona.casual.id, toApp: "com.hnc.Discord", named: "Discord")

    store.delete(slack)

    #expect(store.appPersonas.map(\.bundleIdentifier) == ["com.hnc.Discord"])
    #expect(makeStore().appPersonas.map(\.bundleIdentifier) == ["com.hnc.Discord"])
  }

  @Test func duplicatingAPersonaLeavesItsPinsOnTheOriginal() {
    let store = makeStore()
    store.pin(RefinePersona.casual.id, toApp: "com.hnc.Discord", named: "Discord")
    let copy = store.duplicate(.casual)
    #expect(store.persona(forApp: "com.hnc.Discord") == .casual)
    #expect(!store.isPinned(copy))
  }

  @Test func pinsAreRestoredOnLaunch() {
    let store = makeStore()
    store.pin(RefinePersona.casual.id, toApp: "com.hnc.Discord", named: "Discord")
    store.pin(RefinePersona.formal.id, toApp: "com.apple.mail", named: "Mail")
    #expect(makeStore().appPersonas == store.appPersonas)
  }

  /// Pins saved by a damaged or older store load without ones to missing personas or a second pin for an app.
  @Test func storedPinsToMissingPersonasOrRepeatedAppsAreIgnored() throws {
    let pins = [
      AppPersona(bundleIdentifier: "com.hnc.Discord", appName: "Discord", personaID: RefinePersona.casual.id),
      AppPersona(bundleIdentifier: "com.hnc.Discord", appName: "Discord", personaID: RefinePersona.formal.id),
      AppPersona(bundleIdentifier: "com.apple.mail", appName: "Mail", personaID: "deleted"),
    ]
    defaults.set(try JSONEncoder().encode(pins), forKey: PersonaStore.appPersonasStorageKey)
    #expect(makeStore().appPersonas == [pins[0]])
  }

  @Test func personasInUseAreTheChosenOneThenThosePinnedToRunningApps() {
    let store = makeStore()
    let slack = custom("Slack")
    store.save(slack)
    store.pin(slack.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    store.pin(RefinePersona.casual.id, toApp: "com.hnc.Discord", named: "Discord")
    store.pin(RefinePersona.formal.id, toApp: "com.apple.mail", named: "Mail")
    store.pin(slack.id, toApp: "com.microsoft.teams2", named: "Teams")

    let inUse = store.personasInUse(runningApps: ["com.apple.mail", "com.microsoft.teams2", "com.hnc.Discord"])

    // Mail's persona is the chosen one, and Teams shares Slack's, so each is kept once.
    #expect(inUse == [.formal, .casual, slack])
    #expect(store.personasInUse(runningApps: []) == [.formal])
  }

  /// Has the cache keep the personas in use, as the refiner does, storing a start for each one it reads, and returns
  /// whether any start was dropped.
  private func keepInUse(
    _ store: PersonaStore,
    _ cache: inout PersonaPromptCache<String>,
    running: Set<String>
  ) -> Bool {
    let inUse = store.personasInUse(runningApps: running)
    let dropped = cache.keep(inUse, request: cache.request + 1)
    for persona in inUse where cache.prompt(for: persona) == nil {
      cache.store(persona.id, for: persona)
    }
    return dropped == true
  }

  /// Switching an app to another persona drops its old persona's start unless a running app still uses it, and
  /// switching back has it read again.
  @Test func repinningAnAppDropsItsOldPersonasStartUnlessAnotherRunningAppUsesIt() {
    let store = makeStore()
    var cache = PersonaPromptCache<String>()
    var running: Set = ["org.mozilla.firefox"]
    store.pin(RefinePersona.casual.id, toApp: "org.mozilla.firefox", named: "Firefox")
    _ = keepInUse(store, &cache, running: running)

    store.pin(RefinePersona.formal.id, toApp: "org.mozilla.firefox", named: "Firefox")
    #expect(keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) == nil)

    store.pin(RefinePersona.casual.id, toApp: "org.mozilla.firefox", named: "Firefox")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) != nil)

    store.pin(RefinePersona.casual.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    running.insert("com.tinyspeck.slackmacgap")
    store.pin(RefinePersona.formal.id, toApp: "org.mozilla.firefox", named: "Firefox")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) != nil)
  }

  /// Pinning a running app has its persona's start read, and unpinning it drops that start unless another running
  /// app still uses it.
  @Test func addingAndRemovingAppPersonasReadsAndDropsTheirStarts() {
    let store = makeStore()
    var cache = PersonaPromptCache<String>()
    let running: Set = ["org.mozilla.firefox", "com.tinyspeck.slackmacgap"]
    _ = keepInUse(store, &cache, running: running)

    store.pin(RefinePersona.casual.id, toApp: "com.apple.mail", named: "Mail")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) == nil)

    store.pin(RefinePersona.casual.id, toApp: "org.mozilla.firefox", named: "Firefox")
    store.pin(RefinePersona.casual.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) != nil)

    store.unpin(app: "org.mozilla.firefox")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) != nil)

    store.unpin(app: "com.tinyspeck.slackmacgap")
    #expect(keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) == nil)

    store.pin(RefinePersona.casual.id, toApp: "com.tinyspeck.slackmacgap", named: "Slack")
    #expect(!keepInUse(store, &cache, running: running))
    #expect(cache.prompt(for: .casual) != nil)
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

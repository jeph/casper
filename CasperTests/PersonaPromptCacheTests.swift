import Testing

struct PersonaPromptCacheTests {
  private let discord = RefinePersona(
    id: "discord",
    name: "Discord",
    summary: "",
    systemImage: "star",
    instructions: "Write like a gamer."
  )

  /// A dictation into an app that quits before it's refined reads its persona's start, which mustn't stay in memory.
  @Test func startsOfPersonasNoLongerKeptAreNotHeld() {
    var cache = PersonaPromptCache<String>()
    _ = cache.keep([.formal, discord], request: 1)
    cache.store("formal start", for: .formal)
    cache.store("discord start", for: discord)

    let dropped = cache.keep([.formal], request: 2)
    #expect(dropped == true)
    #expect(cache.prompt(for: discord) == nil)

    cache.store("discord start", for: discord)
    #expect(cache.prompt(for: discord) == nil)
    #expect(cache.prompt(for: .formal) == "formal start")
  }

  /// A dictation that started before its persona was edited is refined with the old instructions, whose start
  /// mustn't replace the edited persona's.
  @Test func editedPersonasDontUseOrKeepTheirOldStart() {
    var edited = discord
    edited.instructions = "Write like a pirate."
    var cache = PersonaPromptCache<String>()
    _ = cache.keep([discord], request: 1)
    cache.store("old start", for: discord)

    let dropped = cache.keep([edited], request: 2)
    #expect(dropped == true)
    #expect(cache.prompt(for: edited) == nil)

    cache.store("new start", for: edited)
    cache.store("old start", for: discord)
    #expect(cache.prompt(for: edited) == "new start")
    #expect(cache.prompt(for: discord) == nil)
  }

  @Test func keepingTheSamePersonasDropsNothing() {
    var cache = PersonaPromptCache<String>()
    _ = cache.keep([.formal, .casual], request: 1)
    cache.store("formal start", for: .formal)
    let dropped = cache.keep([.casual, .formal], request: 2)
    #expect(dropped == false)
    #expect(cache.prompt(for: .formal) == "formal start")
  }

  /// Requests made while the model loads can reach it out of order, as when Discord is unpinned right after it was
  /// pinned, and an earlier one arriving last mustn't bring back what the later one dropped.
  @Test func requestsThatArriveAfterALaterOneAreIgnored() {
    var cache = PersonaPromptCache<String>()
    let unpinned = cache.keep([.formal], request: 2)
    let pinned = cache.keep([.formal, discord], request: 1)

    #expect(unpinned == false)
    #expect(pinned == nil)
    #expect(cache.kept == [.formal])
    #expect(cache.request == 2)
    cache.store("discord start", for: discord)
    #expect(cache.prompt(for: discord) == nil)
  }
}

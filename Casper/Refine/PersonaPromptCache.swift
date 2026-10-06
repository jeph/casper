/// The cached prompt starts of the personas dictation can use right now, which are the only ones it holds.
///
/// A prompt start is the start of a persona's prompt as it was when it was read, so editing a persona's instructions
/// makes its start a different one.
struct PersonaPromptCache<Prompt> {
  private struct Key: Hashable {
    let personaID: String
    let instructions: String

    init(_ persona: RefinePersona) {
      personaID = persona.id
      instructions = persona.instructions
    }
  }

  /// The personas whose prompt starts are kept, in the order they should be read.
  private(set) var kept: [RefinePersona] = []
  /// The number of the request that chose `kept`.
  private(set) var request = Int.min
  private var prompts: [Key: Prompt] = [:]

  /// Keeps only these personas' prompt starts from now on, unless a later request already chose which to keep.
  ///
  /// Requests are numbered in the order they're made, and can arrive out of order. Returns whether any start held
  /// until now was dropped, or `nil` if a later request was already applied, which leaves the cache unchanged.
  mutating func keep(_ personas: [RefinePersona], request: Int) -> Bool? {
    guard request > self.request else { return nil }
    self.request = request
    kept = personas
    let keys = Set(personas.map(Key.init))
    let count = prompts.count
    prompts = prompts.filter { keys.contains($0.key) }
    return prompts.count != count
  }

  func prompt(for persona: RefinePersona) -> Prompt? {
    prompts[Key(persona)]
  }

  /// Holds a persona's prompt start if the persona is kept.
  ///
  /// A persona no longer kept, such as one pinned to an app that quit while its dictation was transcribed, has its
  /// start read for one transcript and then freed, so it doesn't stay in memory until the personas in use change.
  mutating func store(_ prompt: Prompt, for persona: RefinePersona) {
    let key = Key(persona)
    guard kept.contains(where: { Key($0) == key }) else { return }
    prompts[key] = prompt
  }
}

import Foundation
import OSLog
import Observation

/// The personas transcripts can be refined in and the chosen one, kept across launches.
///
/// Built-in personas come first, in Casper's order, then the user's own in the order they were added. Built-ins can't
/// be changed, so only the user's own personas are saved.
@MainActor
@Observable
final class PersonaStore {
  private(set) var personas: [RefinePersona]

  /// The chosen persona's ID, always one of `personas`.
  var selectedID: String {
    didSet { defaults.set(selectedID, forKey: RefinePersona.storageKey) }
  }

  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let defaults: UserDefaults

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "PersonaStore")

  static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "Casper/Personas.json")

  init(fileURL: URL = defaultFileURL, defaults: UserDefaults = .standard) {
    self.fileURL = fileURL
    self.defaults = defaults
    let personas = RefinePersona.builtIns + Self.load(from: fileURL).filter { !$0.isBuiltIn }
    self.personas = personas
    let storedID = defaults.string(forKey: RefinePersona.storageKey)
    selectedID = personas.first { $0.id == storedID }?.id ?? RefinePersona.formal.id
  }

  var selected: RefinePersona { personas.first { $0.id == selectedID } ?? .formal }

  /// Whether a persona other than the one with the given ID has this name, ignoring case and surrounding spaces.
  func isNameTaken(_ name: String, exceptBy id: String?) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return personas.contains { persona in
      persona.id != id && persona.name.compare(name, options: .caseInsensitive) == .orderedSame
    }
  }

  /// Adds one of the user's personas, or replaces the one with its ID.
  ///
  /// Built-in personas can't be changed.
  func save(_ persona: RefinePersona) {
    guard !persona.isBuiltIn else { return }
    var persona = persona
    persona.name = persona.name.trimmingCharacters(in: .whitespacesAndNewlines)
    persona.summary = persona.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    if let index = personas.firstIndex(where: { $0.id == persona.id }) {
      personas[index] = persona
    } else {
      personas.append(persona)
    }
    persist()
  }

  /// Adds a copy of a persona as the user's own, named so it doesn't clash with any other.
  ///
  /// A copy of a built-in persona starts from its prompt written out as instructions.
  @discardableResult
  func duplicate(_ persona: RefinePersona) -> RefinePersona {
    let id = UUID().uuidString
    let name = uniqueName(for: id, base: persona.name) { base in
      String(localized: "\(base) Copy", comment: "Name of a duplicated persona. The argument is the original's name.")
    }
    let copy = RefinePersona(
      id: id,
      name: name,
      summary: persona.summary,
      systemImage: persona.systemImage,
      instructions: persona.instructions
    )
    personas.append(copy)
    persist()
    return copy
  }

  /// Deletes one of the user's personas, choosing the formal persona if it was chosen.
  ///
  /// Built-in personas can't be deleted.
  func delete(_ persona: RefinePersona) {
    guard !persona.isBuiltIn else { return }
    personas.removeAll { $0.id == persona.id }
    if selectedID == persona.id {
      selectedID = RefinePersona.formal.id
    }
    persist()
  }

  /// A name made from a base name, followed by the first number that makes it unique if it isn't, with the base name
  /// shortened so the whole name fits the name limit.
  private func uniqueName(for id: String, base: String, format: (String) -> String) -> String {
    var number = 1
    while true {
      let suffix = number == 1 ? "" : " \(number)"
      let room = RefinePersona.nameLimit - format("").count - suffix.count
      let candidate = format(String(base.prefix(room))) + suffix
      if !isNameTaken(candidate, exceptBy: id) { return candidate }
      number += 1
    }
  }

  /// Saves the user's personas.
  private func persist() {
    let saved = personas.filter { !$0.isBuiltIn }
    do {
      let directory = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(saved).write(to: fileURL, options: .atomic)
    } catch {
      Self.logger.error("Couldn't save the personas: \(error)")
    }
  }

  private static func load(from fileURL: URL) -> [RefinePersona] {
    guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
    do {
      return try JSONDecoder().decode([RefinePersona].self, from: Data(contentsOf: fileURL))
    } catch {
      logger.error("Couldn't read the personas, so only the built-in ones are available: \(error)")
      return []
    }
  }
}

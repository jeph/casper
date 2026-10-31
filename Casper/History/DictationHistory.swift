import Foundation
import OSLog
import Observation

/// The dictations Casper has typed, saved in a database on this Mac while history is turned on.
@MainActor
@Observable
final class DictationHistory {
  static let enabledStorageKey = "historyEnabled"

  /// Whether new dictations are saved, which they are unless the user turned history off.
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
  }

  /// How many dictations are saved.
  private(set) var count = 0
  /// How many dictations have been saved since launch, so an open History page can show new ones as they arrive.
  private(set) var saves = 0

  @ObservationIgnored private let database: HistoryDatabase

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "History")

  init(database: HistoryDatabase = HistoryDatabase()) {
    self.database = database
    Task { await updateCount() }
  }

  /// Saves the text Casper typed for a dictation whose recording ended at `date` after `duration` seconds, into the
  /// app with the bundle identifier `app`, unless history is off.
  func save(_ text: String, recordedAt date: Date, duration: TimeInterval, app: String?) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isEnabled, !text.isEmpty else { return }
    Task {
      do {
        try await database.insert(text, date: date, duration: duration, app: app)
        count += 1
        saves += 1
      } catch {
        Self.logger.error("Couldn't save the dictation to the history: \(error)")
      }
    }
  }

  func page(matching query: String, before cursor: Dictation?, limit: Int) async throws -> [Dictation] {
    try await database.page(matching: query, before: cursor, limit: limit)
  }

  func dictations(matching query: String, after cursor: Dictation) async throws -> [Dictation] {
    try await database.dictations(matching: query, after: cursor)
  }

  func count(matching query: String) async throws -> Int {
    try await database.count(matching: query)
  }

  /// Stats about every saved dictation, dated in the user's calendar, with streaks up to today.
  func stats() async throws -> HistoryStats {
    try await database.stats(calendar: .current, now: .now)
  }

  func delete(_ ids: Set<Int64>) async throws {
    try await database.delete(ids)
    await updateCount()
  }

  func deleteAll() async throws {
    try await database.deleteAll()
    count = 0
  }

  private func updateCount() async {
    do {
      count = try await database.count(matching: "")
    } catch {
      Self.logger.error("Couldn't count the dictations in the history: \(error)")
    }
  }
}

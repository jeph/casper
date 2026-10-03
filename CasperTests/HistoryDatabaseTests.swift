import Foundation
import Testing

final class HistoryDatabaseTests {
  private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  private let database: HistoryDatabase

  init() {
    database = HistoryDatabase(fileURL: directory.appending(path: "History.sqlite"))
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: seconds)
  }

  /// Reads every page the way the History page scrolls through them.
  private func allPages(matching query: String = "", size: Int) async throws -> [Dictation] {
    var all: [Dictation] = []
    while true {
      let page = try await database.page(matching: query, before: all.last, limit: size)
      all += page
      if page.count < size { return all }
    }
  }

  @Test func pagesListNewestFirstByDateNotByWhenSaved() async throws {
    let older = try await database.insert("Older", date: date(100))
    let newest = try await database.insert("Newest", date: date(300))
    let middle = try await database.insert("Middle", date: date(200))
    #expect(try await allPages(size: 2) == [newest, middle, older])
  }

  /// Dictations that end at the same moment straddle a page boundary without any being skipped or repeated.
  @Test func pagingNeverSkipsDictationsWithTheSameDate() async throws {
    var saved: [Dictation] = []
    for index in 0..<7 {
      saved.append(try await database.insert("Dictation \(index)", date: date(index < 5 ? 500 : Double(index))))
    }
    let read = try await allPages(size: 2)
    #expect(read.count == saved.count)
    #expect(Set(read) == Set(saved))
  }

  @Test func searchMatchesTheStartsOfWordsIgnoringCaseAndAccents() async throws {
    let contract = try await database.insert("Review the Contract tonight", date: date(1))
    _ = try await database.insert("The process is uncontrolled", date: date(2))
    let cafe = try await database.insert("Meet at the café", date: date(3))
    #expect(try await allPages(matching: "contr", size: 10) == [contract])
    #expect(try await allPages(matching: "CAFE", size: 10) == [cafe])
    #expect(try await database.count(matching: "contr") == 1)
  }

  @Test func everyWordSearchedForHasToMatch() async throws {
    let both = try await database.insert("Move the standup to tomorrow", date: date(1))
    _ = try await database.insert("Move the meeting", date: date(2))
    #expect(try await allPages(matching: "move standup", size: 10) == [both])
  }

  /// Characters with a meaning in SQLite's query syntax are searched for as text instead of failing the search.
  @Test(arguments: ["\"", "say \"hi", "OR", "NEAR(", "a*b", "col:umn", "-", "^start"])
  func searchSyntaxIsTreatedAsText(query: String) async throws {
    _ = try await database.insert("Say \"hi\" or start a column", date: date(1))
    _ = try await database.page(matching: query, before: nil, limit: 10)
    _ = try await database.count(matching: query)
  }

  @Test func searchPagesContinueFromTheLastMatch() async throws {
    for index in 0..<5 {
      _ = try await database.insert("Contract \(index)", date: date(Double(index)))
      _ = try await database.insert("Other \(index)", date: date(Double(index) + 0.5))
    }
    let matches = try await allPages(matching: "contract", size: 2)
    #expect(matches.map(\.text) == (0..<5).reversed().map { "Contract \($0)" })
  }

  @Test func dictationsAfterACursorAreOnlyNewerMatchingOnes() async throws {
    let cursor = try await database.insert("Contract draft", date: date(10))
    _ = try await database.insert("Older contract", date: date(5))
    let newer = try await database.insert("Contract signed", date: date(20))
    _ = try await database.insert("Lunch plans", date: date(30))
    #expect(try await database.dictations(matching: "contract", after: cursor) == [newer])
  }

  @Test func deletedDictationsLeaveTheListAndTheSearch() async throws {
    let kept = try await database.insert("Keep this contract", date: date(1))
    let deleted = try await database.insert("Delete this contract", date: date(2))
    try await database.delete([deleted.id])
    #expect(try await allPages(size: 10) == [kept])
    #expect(try await allPages(matching: "delete", size: 10).isEmpty)
    #expect(try await database.count(matching: "contract") == 1)
  }

  @Test func deletesMoreDictationsThanFitInOneStatement() async throws {
    var ids: [Int64] = []
    for index in 0..<1_200 {
      ids.append(try await database.insert("Dictation \(index)", date: date(Double(index))).id)
    }
    let kept = try await database.insert("Kept", date: date(5_000))
    try await database.delete(ids)
    #expect(try await allPages(size: 100) == [kept])
  }

  /// A deleted dictation's words are gone from the file itself, including the search index, not just hidden.
  @Test func deletedDictationsAreErasedFromTheFile() async throws {
    let secret = try await database.insert("My password is quixoticzebra", date: date(1))
    _ = try await database.insert("Something else", date: date(2))
    try await database.delete([secret.id])
    let bytes = try Data(contentsOf: directory.appending(path: "History.sqlite"))
    #expect(bytes.firstRange(of: Data("quixoticzebra".utf8)) == nil)
  }

  @Test func deletingEverythingRemovesTheFileAndHistoryStartsOver() async throws {
    _ = try await database.insert("Secret", date: date(1))
    let file = directory.appending(path: "History.sqlite")
    #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    try await database.deleteAll()
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(try await database.count(matching: "") == 0)
    let next = try await database.insert("Next", date: date(2))
    #expect(try await allPages(size: 10) == [next])
  }

  @Test func historyIsKeptAcrossLaunches() async throws {
    let saved = try await database.insert("Remember me", date: date(1))
    let reopened = HistoryDatabase(fileURL: directory.appending(path: "History.sqlite"))
    #expect(try await reopened.page(matching: "remember", before: nil, limit: 10) == [saved])
  }
}

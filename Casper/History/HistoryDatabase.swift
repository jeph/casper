import Foundation
import SQLite3

/// A dictation saved in the history: the text Casper typed, when the recording ended, how long the recording was in
/// seconds, and the bundle identifier of the app it was dictated into, which is unknown when no app was frontmost.
struct Dictation: Identifiable, Hashable, Sendable {
  let id: Int64
  let date: Date
  let text: String
  let duration: TimeInterval
  let app: String?
}

/// The history's SQLite database, a file on this Mac that Casper never sends anywhere.
///
/// Dictations are read a page at a time, newest first, continuing from the last one read, so the History page only
/// holds what it has scrolled to and every page costs the same however far back it is. A full-text index finds
/// dictations by the words in them across the whole history.
actor HistoryDatabase {
  struct Error: Swift.Error, CustomStringConvertible {
    let description: String
  }

  static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "Casper/History.sqlite")
  /// The version of the tables, kept in the file's `user_version`.
  ///
  /// A history from before versions were kept is deleted when it's opened, since it can't say how long its dictations
  /// took or which apps they went into.
  private static let schemaVersion: Int64 = 1

  private let fileURL: URL
  /// Only used on the actor, and by `deinit` once nothing else can reach the actor.
  nonisolated(unsafe) private var connection: OpaquePointer?

  init(fileURL: URL = defaultFileURL) {
    self.fileURL = fileURL
  }

  deinit {
    sqlite3_close_v2(connection)
  }

  @discardableResult
  func insert(_ text: String, date: Date, duration: TimeInterval, app: String?) throws -> Dictation {
    try run(
      "INSERT INTO dictation (date, text, duration, app) VALUES (?, ?, ?, ?)",
      .double(date.timeIntervalSinceReferenceDate),
      .text(text),
      .double(duration),
      app.map(Value.text) ?? .null
    )
    return Dictation(
      id: sqlite3_last_insert_rowid(try database()),
      date: date,
      text: text,
      duration: duration,
      app: app
    )
  }

  /// The newest `limit` dictations older than `cursor`, or the newest overall without one, that match `query`.
  func page(matching query: String, before cursor: Dictation?, limit: Int) throws -> [Dictation] {
    try dictations(matching: query, beyond: cursor, newer: false, limit: limit)
  }

  /// Every dictation newer than `cursor` that matches `query`, newest first.
  func dictations(matching query: String, after cursor: Dictation) throws -> [Dictation] {
    try dictations(matching: query, beyond: cursor, newer: true, limit: nil)
  }

  func count(matching query: String) throws -> Int {
    guard let expression = HistorySearch.matchExpression(for: query) else {
      return try rows("SELECT count(*) FROM dictation") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }
    return try rows("SELECT count(*) FROM dictation_search WHERE dictation_search MATCH ?", .text(expression)) {
      Int(sqlite3_column_int64($0, 0))
    }
    .first ?? 0
  }

  /// Stats about every dictation, dated in `calendar`, with streaks up to `now`.
  func stats(calendar: Calendar, now: Date) throws -> HistoryStats {
    var stats = HistoryStats.Builder(calendar: calendar, now: now)
    _ = try rows("SELECT \(Self.columns) FROM dictation") { stats.add(Self.dictation(from: $0)) }
    return stats.build()
  }

  func delete(_ ids: some Collection<Int64>) throws {
    let ids = Array(ids)
    try run("BEGIN")
    do {
      // Batches stay well under SQLite's limit on the number of values in one statement.
      for start in stride(from: 0, to: ids.count, by: 500) {
        let batch = ids[start..<min(start + 500, ids.count)]
        let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ", ")
        try run("DELETE FROM dictation WHERE id IN (\(placeholders))", batch.map(Value.integer))
      }
      try run("COMMIT")
    } catch {
      try? run("ROLLBACK")
      throw error
    }
  }

  /// Deletes the database file itself, along with SQLite's journal files, so nothing of the history is left on disk.
  func deleteAll() throws {
    sqlite3_close_v2(connection)
    connection = nil
    try removeFiles()
  }

  // MARK: Queries

  private func dictations(
    matching query: String,
    beyond cursor: Dictation?,
    newer: Bool,
    limit: Int?
  ) throws -> [Dictation] {
    var conditions: [String] = []
    var values: [Value] = []
    var source = "dictation"
    if let expression = HistorySearch.matchExpression(for: query) {
      source = "dictation JOIN dictation_search ON dictation_search.rowid = dictation.id"
      conditions.append("dictation_search MATCH ?")
      values.append(.text(expression))
    }
    if let cursor {
      // Ordering by ID after the date keeps dictations with the same date from being skipped between pages.
      conditions.append("(dictation.date, dictation.id) \(newer ? ">" : "<") (?, ?)")
      values += [.double(cursor.date.timeIntervalSinceReferenceDate), .integer(cursor.id)]
    }
    var sql = "SELECT \(Self.columns) FROM \(source)"
    if !conditions.isEmpty {
      sql += " WHERE " + conditions.joined(separator: " AND ")
    }
    sql += " ORDER BY dictation.date DESC, dictation.id DESC"
    if let limit {
      sql += " LIMIT ?"
      values.append(.integer(Int64(limit)))
    }
    return try rows(sql, values, read: Self.dictation)
  }

  private static let columns = "dictation.id, dictation.date, dictation.text, dictation.duration, dictation.app"

  /// The dictation in a row of `columns`.
  private static func dictation(from statement: OpaquePointer) -> Dictation {
    Dictation(
      id: sqlite3_column_int64(statement, 0),
      date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
      text: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "",
      duration: sqlite3_column_double(statement, 3),
      app: sqlite3_column_text(statement, 4).map { String(cString: $0) }
    )
  }

  // MARK: SQLite

  private enum Value {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null
  }

  /// The open connection, opening the database and creating its tables the first time.
  private func database() throws -> OpaquePointer {
    if let connection { return connection }
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(fileURL.path(percentEncoded: false), &opened, flags, nil) == SQLITE_OK, let opened else {
      let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
      sqlite3_close_v2(opened)
      throw Error(description: "Couldn't open the history: \(message)")
    }
    connection = opened
    let isFromAnEarlierVersion: Bool
    do {
      isFromAnEarlierVersion = try self.isFromAnEarlierVersion()
      if !isFromAnEarlierVersion {
        try createTables()
      }
    } catch {
      sqlite3_close_v2(opened)
      connection = nil
      throw error
    }
    guard isFromAnEarlierVersion else { return opened }
    try deleteAll()
    return try database()
  }

  private func createTables() throws {
    // Deleted dictations are overwritten on disk instead of lingering in free pages of the file.
    try run("PRAGMA secure_delete = ON")
    try run(
      """
      CREATE TABLE IF NOT EXISTS dictation (
        id INTEGER PRIMARY KEY, date REAL NOT NULL, text TEXT NOT NULL, duration REAL NOT NULL, app TEXT
      )
      """
    )
    try run("CREATE INDEX IF NOT EXISTS dictation_date ON dictation (date, id)")
    // The index reads its text from the dictation table, and triggers keep it in step with that table.
    try run(
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS dictation_search USING fts5(
        text, content = 'dictation', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
      )
      """
    )
    // The index keeps a deleted dictation's words until it merges its data, unless it erases them as it deletes.
    try run("INSERT INTO dictation_search (dictation_search, rank) VALUES ('secure-delete', 1)")
    try run(
      """
      CREATE TRIGGER IF NOT EXISTS dictation_inserted AFTER INSERT ON dictation BEGIN
        INSERT INTO dictation_search (rowid, text) VALUES (new.id, new.text);
      END
      """
    )
    try run(
      """
      CREATE TRIGGER IF NOT EXISTS dictation_deleted AFTER DELETE ON dictation BEGIN
        INSERT INTO dictation_search (dictation_search, rowid, text) VALUES ('delete', old.id, old.text);
      END
      """
    )
    try run("PRAGMA user_version = \(Self.schemaVersion)")
  }

  /// Whether the open file holds a history from before its tables had a version, which a new file doesn't.
  private func isFromAnEarlierVersion() throws -> Bool {
    let version = try rows("PRAGMA user_version") { sqlite3_column_int64($0, 0) }.first ?? 0
    guard version < Self.schemaVersion else { return false }
    let tables = try rows("SELECT count(*) FROM sqlite_master WHERE name = 'dictation'") { sqlite3_column_int64($0, 0) }
    return tables.first ?? 0 > 0
  }

  private func removeFiles() throws {
    let manager = FileManager.default
    for suffix in ["", "-wal", "-shm", "-journal"] {
      let path = fileURL.path(percentEncoded: false) + suffix
      if manager.fileExists(atPath: path) {
        try manager.removeItem(atPath: path)
      }
    }
  }

  private func run(_ sql: String, _ values: Value...) throws {
    try run(sql, values)
  }

  private func run(_ sql: String, _ values: [Value]) throws {
    _ = try rows(sql, values) { _ in () }
  }

  private func rows<Row>(_ sql: String, _ values: Value..., read: (OpaquePointer) -> Row) throws -> [Row] {
    try rows(sql, values, read: read)
  }

  private func rows<Row>(_ sql: String, _ values: [Value], read: (OpaquePointer) -> Row) throws -> [Row] {
    let database = try database()
    var prepared: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
      throw error(in: database)
    }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      let position = Int32(index + 1)
      switch value {
      case .integer(let integer): sqlite3_bind_int64(statement, position, integer)
      case .double(let double): sqlite3_bind_double(statement, position, double)
      case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
      case .null: sqlite3_bind_null(statement, position)
      }
    }
    var result: [Row] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: result.append(read(statement))
      case SQLITE_DONE: return result
      default: throw error(in: database)
      }
    }
  }

  private func error(in database: OpaquePointer) -> Error {
    Error(description: String(cString: sqlite3_errmsg(database)))
  }

  /// Tells SQLite to copy bound text, since Swift frees the C string once the bind call returns.
  private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }
}

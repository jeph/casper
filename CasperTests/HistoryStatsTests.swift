import Foundation
import Testing

struct HistoryStatsTests {
  private let calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }()
  /// Noon on March 10, 2026, two days after daylight saving time started in New York.
  private var now: Date { at(day: 10, hour: 12) }

  private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
  }

  private func dictation(
    _ text: String,
    at date: Date? = nil,
    duration: TimeInterval = 10,
    app: String? = nil
  )
    -> Dictation
  {
    Dictation(id: 0, date: date ?? now, text: text, duration: duration, app: app)
  }

  private func stats(_ dictations: Dictation...) -> HistoryStats {
    var builder = HistoryStats.Builder(calendar: calendar, now: now)
    for dictation in dictations {
      builder.add(dictation)
    }
    return builder.build()
  }

  /// `count` words of five characters each, counting the space after each, as text entry research's words are.
  private func words(_ count: Int) -> String {
    String(repeating: "word ", count: count)
  }

  @Test func anEmptyHistoryHasNoStats() {
    #expect(stats() == HistoryStats())
    #expect(stats().busiestHour == nil)
    #expect(stats().averageWords == 0)
  }

  @Test func timeSavedIsTypingTheWordsLessSpeakingThem() {
    // 520 words take 10 minutes to type at 52 words a minute; saying them took 2.
    let stats = stats(dictation(words(520), duration: 120))
    #expect(stats.timeSaved == 480)
    #expect(stats.speaking == 120)
    #expect(stats.wordsPerMinute == 260)
    #expect(abs(stats.speedup - 5) < 1e-9)
  }

  /// Typing speed is measured in five-character words, so longer words take longer to type.
  @Test func typingTimeGoesByCharactersNotWords() {
    // 260 words of nine letters and a space are 2,600 characters: 520 five-character words, 10 minutes of typing.
    let stats = stats(dictation(String(repeating: "abcdefghi ", count: 260), duration: 120))
    #expect(stats.words == 260)
    #expect(stats.timeSaved == 480)
  }

  @Test func speakingSlowerThanTypingSavesNothing() {
    let stats = stats(dictation("one two", duration: 60))
    #expect(stats.timeSaved == 0)
    #expect(stats.speedup < 1)
  }

  @Test(arguments: [
    ("", 0), ("  \n\t ", 0), ("— ... !", 0), ("  Hello, world — it's 2026!  ", 4), ("one\ntwo\tthree", 3),
  ])
  func countsOnlyRunsWithALetterOrDigitAsWords(text: String, words: Int) {
    #expect(HistoryStats.countWords(in: text) == words)
  }

  @Test func longestAndAverageDictations() {
    let stats = stats(dictation(words(1)), dictation(words(4)), dictation(words(2)))
    #expect(stats.longestDictationWords == 4)
    #expect(stats.averageWords == 2)
  }

  @Test func aStreakRunsUpToToday() {
    let stats = stats(
      dictation("a", at: at(day: 10, hour: 9)),
      dictation("b", at: at(day: 9, hour: 9)),
      dictation("c", at: at(day: 8, hour: 9)),
      dictation("d", at: at(day: 6, hour: 9))
    )
    #expect(stats.currentStreak == 3)
    #expect(stats.longestStreak == 3)
    #expect(stats.daysActive == 4)
    #expect(stats.firstDay == at(day: 6, hour: 0))
  }

  /// Until today's first dictation, a streak that reached yesterday is still going.
  @Test func aStreakEndingYesterdayHoldsUntilTodayEnds() {
    let stats = stats(dictation("a", at: at(day: 9, hour: 9)), dictation("b", at: at(day: 8, hour: 9)))
    #expect(stats.currentStreak == 2)
  }

  @Test func aMissedDayEndsTheStreak() {
    let stats = stats(
      dictation("a", at: at(day: 8, hour: 9)),
      dictation("b", at: at(day: 3, hour: 9)),
      dictation("c", at: at(day: 2, hour: 9)),
      dictation("d", at: at(day: 1, hour: 9))
    )
    #expect(stats.currentStreak == 0)
    #expect(stats.longestStreak == 3)
  }

  /// Days and hours are the calendar's, so a dictation just before local midnight counts for that day.
  ///
  /// The streak runs across March 8, a 23-hour day when daylight saving time starts.
  @Test func daysAndHoursAreInTheCalendarsTimeZone() {
    let stats = stats(
      dictation("late", at: at(day: 7, hour: 23, minute: 30)),
      dictation("later", at: at(day: 8, hour: 23, minute: 50)),
      dictation("later still", at: at(day: 9, hour: 23, minute: 50)),
      dictation("early", at: at(day: 10, hour: 7))
    )
    #expect(stats.busiestHour == 23)
    #expect(stats.dictationsByHour[23] == 3)
    #expect(stats.dictationsByHour[7] == 1)
    #expect(stats.currentStreak == 4)
  }

  @Test func topAppsAreTheMostDictatedIntoWithTiesByBundleIdentifier() {
    let stats = stats(
      dictation("a", app: "com.chat"),
      dictation("b", app: "com.chat"),
      dictation("c", app: "com.notes"),
      dictation("d", app: "com.mail"),
      dictation("e", app: "com.docs"),
      dictation("f", app: nil)
    )
    #expect(
      stats.topApps == [
        .init(bundleIdentifier: "com.chat", dictations: 2),
        .init(bundleIdentifier: "com.docs", dictations: 1),
        .init(bundleIdentifier: "com.mail", dictations: 1),
      ]
    )
  }
}

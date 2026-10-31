import Foundation

/// Stats about the dictations in the history, worked out from it alone, so deleting dictations takes them out of the
/// stats and an empty history has none.
///
/// Time saved compares typing a dictation's text at `typingWordsPerMinute` with how long its recording took. Like the
/// study that number comes from, it measures typing in standard words of `charactersPerWord` characters, spaces
/// included, rather than in the words counted elsewhere.
struct HistoryStats: Equatable, Sendable {
  /// How many dictations went into an app.
  struct AppCount: Equatable, Sendable {
    let bundleIdentifier: String
    let dictations: Int
  }

  /// The average typing speed of 168,000 volunteers in Dhakal et al., "Observations on Typing from 136 Million
  /// Keystrokes" (CHI 2018), in standard words of `charactersPerWord` characters.
  static let typingWordsPerMinute = 52.0
  /// Text entry research's standard word: five characters, spaces and punctuation included.
  static let charactersPerWord = 5.0
  static let topAppCount = 3

  var dictations = 0
  var words = 0
  /// How long the recordings took altogether, in seconds.
  var speaking: TimeInterval = 0
  /// How much longer typing the dictations would have taken than saying them did, in seconds, or zero if it wouldn't.
  var timeSaved: TimeInterval = 0
  /// How fast the user speaks, or zero without any recordings.
  var wordsPerMinute = 0
  /// How many times longer typing the dictations would take than saying them did, or zero without any recordings.
  var speedup = 0.0
  var longestDictationWords = 0
  /// The first day with a dictation, at its start in the calendar's time zone.
  var firstDay: Date?
  /// How many days have a dictation.
  var daysActive = 0
  /// The days in a row up to today with a dictation, where today counts once it has one and yesterday's run holds until
  /// then.
  var currentStreak = 0
  var longestStreak = 0
  /// How many dictations ended in each hour of the day, from midnight.
  var dictationsByHour = Array(repeating: 0, count: 24)
  /// The apps dictated into most, most first, up to `topAppCount`.
  var topApps: [AppCount] = []

  var averageWords: Int {
    dictations == 0 ? 0 : Int((Double(words) / Double(dictations)).rounded())
  }

  /// The hour of the day with the most dictations, the earliest if several tie, or `nil` without any.
  var busiestHour: Int? {
    guard dictations > 0, let most = dictationsByHour.max() else { return nil }
    return dictationsByHour.firstIndex(of: most)
  }

  /// The words in `text`: runs of characters between whitespace with at least one letter or digit in them.
  static func countWords(in text: String) -> Int {
    var count = 0
    var wordHasLetter = false
    for character in text {
      if character.isWhitespace {
        if wordHasLetter { count += 1 }
        wordHasLetter = false
      } else if character.isLetter || character.isNumber {
        wordHasLetter = true
      }
    }
    return wordHasLetter ? count + 1 : count
  }

  /// Builds the stats from the dictations added, in any order, dating them in `calendar` with streaks up to `now`.
  struct Builder {
    private let calendar: Calendar
    private let now: Date
    private var stats = HistoryStats()
    private var characters = 0
    private var days = Set<Date>()
    private var dictationsByApp: [String: Int] = [:]

    init(calendar: Calendar, now: Date) {
      self.calendar = calendar
      self.now = now
    }

    mutating func add(_ dictation: Dictation) {
      let words = HistoryStats.countWords(in: dictation.text)
      stats.dictations += 1
      stats.words += words
      stats.longestDictationWords = max(stats.longestDictationWords, words)
      stats.speaking += dictation.duration
      characters += dictation.text.count
      days.insert(calendar.startOfDay(for: dictation.date))
      stats.dictationsByHour[calendar.component(.hour, from: dictation.date)] += 1
      if let app = dictation.app {
        dictationsByApp[app, default: 0] += 1
      }
    }

    func build() -> HistoryStats {
      var stats = stats
      let typing = Double(characters) / HistoryStats.charactersPerWord / HistoryStats.typingWordsPerMinute * 60
      stats.timeSaved = max(0, typing - stats.speaking)
      if stats.speaking > 0 {
        stats.wordsPerMinute = Int((Double(stats.words) * 60 / stats.speaking).rounded())
        stats.speedup = typing / stats.speaking
      }
      let sortedDays = days.sorted()
      stats.firstDay = sortedDays.first
      stats.daysActive = sortedDays.count
      stats.currentStreak = currentStreak()
      stats.longestStreak = longestStreak(in: sortedDays)
      stats.topApps =
        dictationsByApp
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        .prefix(HistoryStats.topAppCount)
        .map { AppCount(bundleIdentifier: $0.key, dictations: $0.value) }
      return stats
    }

    private func currentStreak() -> Int {
      let today = calendar.startOfDay(for: now)
      var day = days.contains(today) ? today : dayBefore(today)
      var streak = 0
      while days.contains(day) {
        streak += 1
        day = dayBefore(day)
      }
      return streak
    }

    private func longestStreak(in sortedDays: [Date]) -> Int {
      var longest = 0
      var run = 0
      var previous: Date?
      for day in sortedDays {
        run = previous.map { dayBefore(day) == $0 } == true ? run + 1 : 1
        longest = max(longest, run)
        previous = day
      }
      return longest
    }

    /// The start of the day before `day`, which daylight saving time can make 23 or 25 hours earlier.
    private func dayBefore(_ day: Date) -> Date {
      calendar.date(byAdding: .day, value: -1, to: day).map(calendar.startOfDay) ?? day
    }
  }
}

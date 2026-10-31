import AppKit
import Charts
import OSLog
import SwiftUI

/// The Stats page, opened from General: how much the user has dictated, the time it saved over typing, and when and
/// where they dictate, all worked out from the history, so deleted dictations leave the stats too.
///
/// It's read again whenever a dictation is saved or deleted while it's open.
struct StatsView: View {
  let onBack: () -> Void

  @Environment(DictationHistory.self) private var history
  @AppStorage(DictationHistory.enabledStorageKey) private var isHistoryEnabled = true
  @State private var stats: HistoryStats?
  @State private var loadError: String?

  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "Stats")

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // The count changes when dictations are deleted, and the saves when one is saved even if a deletion evened it out.
    .task(id: [history.count, history.saves]) {
      do {
        stats = try await history.stats()
        loadError = nil
      } catch {
        Self.logger.error("Couldn't read the history's stats: \(error)")
        loadError = String(describing: error)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .frame(width: 16, height: 16)
      }
      .keyboardShortcut("[", modifiers: .command)
      .help(Text("Back to General"))
      Text("Stats")
        .font(.title3.weight(.semibold))
    }
    .padding([.horizontal, .top], 16)
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private var content: some View {
    if let loadError {
      ContentUnavailableView {
        Label("Couldn't Load Stats", systemImage: "exclamationmark.triangle")
      } description: {
        Text(loadError)
      }
    } else if let stats, stats.dictations > 0 {
      ScrollView {
        StatsList(stats: stats)
          .padding(16)
      }
    } else if stats != nil {
      ContentUnavailableView {
        Label("No Stats Yet", systemImage: "chart.bar.xaxis")
      } description: {
        Text(
          isHistoryEnabled
            ? "Stats come from your history. Dictate something and they'll appear here."
            : "Stats come from your history, which is off. Turn it on in History."
        )
      }
    } else {
      ProgressView()
    }
  }
}

private struct StatsList: View {
  let stats: HistoryStats

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TimeSavedCard(stats: stats)
      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          Tile(label: "Dictations", value: Text(stats.dictations.formatted()))
          Tile(label: "Words", value: Text(stats.words.formatted()))
          Tile(label: "Speaking Speed", value: Text("\(stats.wordsPerMinute.formatted()) wpm"))
          Tile(label: "Time Talking", value: Text(durationText(stats.speaking)))
        }
        GridRow {
          Tile(label: "Longest Dictation", value: wordCount(stats.longestDictationWords))
          Tile(label: "Average Dictation", value: wordCount(stats.averageWords))
          Tile(label: "Current Streak", value: dayCount(stats.currentStreak), showsFlame: stats.currentStreak > 0)
          Tile(label: "Longest Streak", value: dayCount(stats.longestStreak))
        }
      }
      HStack(alignment: .top, spacing: 12) {
        if let busiestHour = stats.busiestHour {
          HoursCard(dictationsByHour: stats.dictationsByHour, busiestHour: busiestHour)
        }
        if !stats.topApps.isEmpty {
          AppsCard(apps: stats.topApps, dictations: stats.dictations)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      BooksCard(words: stats.words)
      if let firstDay = stats.firstDay {
        Text(
          "Dictating since \(firstDay.formatted(date: .long, time: .omitted)). Active on \(dayCount(stats.daysActive))."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      }
    }
  }
}

/// The headline stat, with how many times faster than typing the user speaks when it's faster.
private struct TimeSavedCard: View {
  let stats: HistoryStats

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Time Saved")
          .font(.headline)
        Text(durationText(stats.timeSaved))
          .font(.system(size: 40, weight: .bold, design: .rounded))
          .monospacedDigit()
        Text(
          "Compared with typing at \(Int(HistoryStats.typingWordsPerMinute)) words a minute, the average on a computer keyboard."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if stats.speedup >= 1 {
        VStack(spacing: 2) {
          Image(systemName: "hare.fill")
            .font(.title2)
          Text("\(stats.speedup.formatted(.number.precision(.fractionLength(1))))×")
            .font(.system(.title, design: .rounded, weight: .semibold))
          Text("faster than typing")
            .font(.caption)
        }
        .foregroundStyle(.tint)
        .frame(width: 130)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tint.opacity(0.14), in: .rect(cornerRadius: 12))
  }
}

private struct Tile: View {
  let label: LocalizedStringKey
  let value: Text
  var showsFlame = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        if showsFlame {
          Image(systemName: "flame.fill")
            .foregroundStyle(.orange)
        }
        value
          .font(.system(.title3, design: .rounded, weight: .semibold))
          .monospacedDigit()
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }
}

/// A title for when the user dictates most, and a bar for each hour of the day.
private struct HoursCard: View {
  let dictationsByHour: [Int]
  let busiestHour: Int

  var body: some View {
    let most = dictationsByHour.max() ?? 0
    VStack(alignment: .leading, spacing: 2) {
      Text("When You Dictate")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(chronotype)
        .font(.title3.weight(.semibold))
      Text("You dictate most around \(Self.date(atHour: busiestHour).formatted(.dateTime.hour())).")
        .font(.callout)
        .foregroundStyle(.secondary)
      Chart(Array(dictationsByHour.enumerated()), id: \.offset) { hour, dictations in
        // Hours without dictations keep a sliver, so the chart reads as a whole day.
        BarMark(
          x: .value("Hour", Self.date(atHour: hour), unit: .hour),
          y: .value("Dictations", max(Double(dictations), Double(most) * 0.03))
        )
        .foregroundStyle(hour == busiestHour ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)))
        .clipShape(.rect(topLeadingRadius: 2, topTrailingRadius: 2))
      }
      .chartYAxis(.hidden)
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 6)) {
          AxisValueLabel(format: .dateTime.hour(), anchor: .topLeading)
        }
      }
      .frame(height: 84)
      .padding(.top, 10)
      .accessibilityHidden(true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  private var chronotype: LocalizedStringKey {
    switch busiestHour {
    case 5...11: "Early Bird"
    case 12...16: "Midday Talker"
    case 17...21: "Evening Storyteller"
    default: "Night Owl"
    }
  }

  /// The hour on a day without a daylight saving time change, which the chart and the busiest hour are shown as, so
  /// they follow the user's clock.
  private static func date(atHour hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) ?? .now
  }
}

/// The apps dictated into most, each with its share of all the dictations.
private struct AppsCard: View {
  let apps: [HistoryStats.AppCount]
  let dictations: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Where You Dictate")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      ForEach(apps, id: \.bundleIdentifier) { app in
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        HStack(spacing: 10) {
          Image(
            nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
              ?? NSWorkspace.shared.icon(for: .applicationBundle)
          )
          .resizable()
          .frame(width: 32, height: 32)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(verbatim: url.map(Self.name) ?? app.bundleIdentifier)
                .lineLimit(1)
              Spacer()
              Text("^[\(app.dictations) dictation](inflect: true)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            ProgressView(value: Double(app.dictations), total: Double(dictations))
              .controlSize(.small)
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  /// The app's name as Finder shows it, without the extension Finder may show.
  private static func name(of url: URL) -> String {
    let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
  }
}

/// A famous book the words dictated add up to: how many times over, or how much of the shortest.
private struct BooksCard: View {
  let words: Int

  var body: some View {
    let book = Self.books.last { words >= $0.words }
    let shown = book ?? Self.books[0]
    HStack(spacing: 12) {
      Image(systemName: "books.vertical.fill")
        .font(.title)
        .foregroundStyle(.tint)
        .frame(width: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text("Your Words in Books")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Group {
          if let book {
            let times = (Double(words) / Double(book.words)).formatted(.number.precision(.fractionLength(1)))
            Text("\(times)× \(Text(book.title))")
          } else {
            let percent = max(1, words * 100 / shown.words)
            Text("\(percent)% of \(Text(shown.title))")
          }
        }
        .font(.title3.weight(.semibold))
        Text("\(Text(shown.title)) has \(shown.words.formatted()) words.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(.quinary, in: .rect(cornerRadius: 10))
  }

  private struct Book {
    let title: LocalizedStringResource
    let words: Int
  }

  /// The books, shortest first, with the widely cited word counts listed by wordcounttool.com/book-word-counts.
  private static let books = [
    Book(title: "The Little Prince", words: 16_535),
    Book(title: "The Great Gatsby", words: 47_094),
    Book(title: "Harry Potter and the Philosopher's Stone", words: 76_944),
    Book(title: "The Hobbit", words: 95_356),
    Book(title: "Pride and Prejudice", words: 122_685),
    Book(title: "Moby-Dick", words: 209_117),
    Book(title: "War and Peace", words: 587_287),
    Book(title: "The Harry Potter series", words: 1_084_170),
  ]
}

/// A length of time in at most two units, such as "34 hr, 29 min" or "41 sec".
func durationText(_ seconds: TimeInterval) -> String {
  Duration.seconds(seconds.rounded())
    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
}

private func wordCount(_ words: Int) -> Text {
  Text("^[\(words) word](inflect: true)")
}

private func dayCount(_ days: Int) -> Text {
  Text("^[\(days) day](inflect: true)")
}

import SwiftUI

/// Shows what refining does, over and over: a sentence as it was spoken has its filler words struck out, and then
/// becomes the sentence Casper types, the words the two share gliding into place as the others fade away.
struct RefineDemo: View {
  private enum Stage {
    case spoken
    /// The filler words are struck out.
    case marked
    case refined
  }

  /// A word of either sentence, identified by the word of the spoken sentence it is, so a word in both keeps its
  /// identity and glides from one to the other.
  private struct Word: Identifiable {
    let id: Int
    let text: String
    /// Whether the word is spoken but not typed.
    let isFiller: Bool
  }

  @State private var stage = Stage.spoken
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let spokenText = String(
    localized: "So um I think we should uh push the meeting to like Thursday",
    comment: """
      A sentence as someone might say it, with filler words, shown in setup turning into the sentence Casper types. \
      Words it shares with that sentence glide into place, so keep them the same where the language allows.
      """
  )
  /// The spoken sentence as Casper types it, which setup's dictation demo types too.
  static let refinedText = String(
    localized: "I think we should push the meeting to Thursday.",
    comment: "The spoken sentence in setup as Casper types it, without its filler words and with punctuation."
  )
  private static let (spokenWords, refinedWords) = words(spoken: spokenText, refined: refinedText)

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        if stage == .refined {
          Text("Casper types", comment: "Label in setup above the sentence Casper types from what was said.")
        } else {
          Text("You say", comment: "Label in setup above a sentence as someone might say it.")
        }
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      ZStack {
        // Holds the card at the spoken sentence's size, the larger, so the card doesn't resize as the words change.
        sentence(Self.spokenWords).hidden()
        sentence(stage == .refined ? Self.refinedWords : Self.spokenWords)
      }
      .font(.title3)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity)
    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "You say \"\(Self.spokenText)\", and Casper types \"\(Self.refinedText)\"",
        comment: "Accessibility label of setup's animation of a spoken sentence turning into the sentence Casper types."
      )
    )
    .task { await loop() }
  }

  private func sentence(_ words: [Word]) -> some View {
    FlowLayout(spacing: 4, lineSpacing: 2) {
      ForEach(words) { word in
        let isStruck = stage == .marked && word.isFiller
        Text(verbatim: word.text)
          .strikethrough(isStruck)
          .foregroundStyle(isStruck ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
          // With Reduce Motion on, the words fade between the sentences rather than moving.
          .id(reduceMotion ? "\(stage == .refined)-\(word.id)" : "\(word.id)")
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.5)))
      }
    }
  }

  private func loop() async {
    while true {
      guard await pause(2.2) else { return }
      withAnimation(.easeInOut(duration: 0.3)) { stage = .marked }
      guard await pause(1.2) else { return }
      withAnimation(.spring(duration: 0.6, bounce: 0.15)) { stage = .refined }
      guard await pause(3.4) else { return }
      withAnimation(.easeInOut(duration: 0.4)) { stage = .spoken }
    }
  }

  /// Waits, returning whether it waited the whole time rather than being cancelled.
  private func pause(_ seconds: Double) async -> Bool {
    (try? await Task.sleep(for: .seconds(seconds))) != nil
  }

  /// Splits both sentences into words, matching each word of the refined sentence to the same word of the spoken one,
  /// ignoring case and punctuation, as long as the matched words stay in order and as many as possible match.
  private static func words(spoken: String, refined: String) -> ([Word], [Word]) {
    let spoken = spoken.split(separator: " ").map(String.init)
    let refined = refined.split(separator: " ").map(String.init)
    let spokenKeys = spoken.map(matchKey)
    let refinedKeys = refined.map(matchKey)
    // The longest common subsequence: `longest[i][j]` is how many words match from word `i` of the spoken sentence
    // and word `j` of the refined one on.
    var longest = Array(repeating: Array(repeating: 0, count: refined.count + 1), count: spoken.count + 1)
    for i in spoken.indices.reversed() {
      for j in refined.indices.reversed() {
        longest[i][j] =
          spokenKeys[i] == refinedKeys[j] && !spokenKeys[i].isEmpty
          ? longest[i + 1][j + 1] + 1 : max(longest[i + 1][j], longest[i][j + 1])
      }
    }
    var matches: [Int: Int] = [:]
    var (i, j) = (0, 0)
    while i < spoken.count, j < refined.count {
      if spokenKeys[i] == refinedKeys[j], !spokenKeys[i].isEmpty {
        matches[j] = i
        i += 1
        j += 1
      } else if longest[i + 1][j] >= longest[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    let matchedSpoken = Set(matches.values)
    let spokenWords = spoken.indices.map { i in
      Word(id: i, text: spoken[i], isFiller: !matchedSpoken.contains(i))
    }
    // Refined words that match none get IDs after the spoken sentence's.
    let refinedWords = refined.indices.map { j in
      Word(id: matches[j] ?? spoken.count + j, text: refined[j], isFiller: false)
    }
    return (spokenWords, refinedWords)
  }

  private static func matchKey(_ word: String) -> String {
    word.lowercased().filter { $0.isLetter || $0.isNumber }
  }
}

/// Lays out views in centered lines, starting a new line when the next view doesn't fit on the current one.
private struct FlowLayout: Layout {
  let spacing: CGFloat
  let lineSpacing: CGFloat

  private struct Line {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = lines(of: subviews, width: proposal.width ?? .infinity)
    let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
    return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for line in lines(of: subviews, width: bounds.width) {
      var x = bounds.minX + (bounds.width - line.width) / 2
      for index in line.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private func lines(of subviews: Subviews, width: CGFloat) -> [Line] {
    var lines: [Line] = []
    var line = Line()
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if !line.indices.isEmpty, line.width + spacing + size.width > width {
        lines.append(line)
        line = Line()
      }
      line.width += (line.indices.isEmpty ? 0 : spacing) + size.width
      line.height = max(line.height, size.height)
      line.indices.append(index)
    }
    if !line.indices.isEmpty {
      lines.append(line)
    }
    return lines
  }
}

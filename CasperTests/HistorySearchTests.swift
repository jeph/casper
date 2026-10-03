import Testing

struct HistorySearchTests {
  @Test(arguments: ["", "   ", "- !", "\n\t"])
  func nothingToSearchForShowsEveryDictation(query: String) {
    #expect(HistorySearch.matchExpression(for: query) == nil)
  }

  @Test func highlightsOnlyTheStartsOfWords() {
    let text = "The contract act was enacted"
    let matched = HistorySearch.matches(of: "act", in: text).map { String(text[$0]) }
    #expect(matched == ["act"])
  }

  @Test func highlightsIgnoringCaseAndAccents() {
    let text = "Café or CAFE, then cafeteria"
    let matched = HistorySearch.matches(of: "cafe", in: text).map { String(text[$0]) }
    #expect(matched == ["Café", "CAFE", "cafe"])
  }

  @Test func highlightsEveryWordSearchedFor() {
    let text = "Move the standup to tomorrow"
    let matched = HistorySearch.matches(of: "tom move", in: text).map { String(text[$0]) }
    #expect(Set(matched) == ["tom", "Move"])
  }
}

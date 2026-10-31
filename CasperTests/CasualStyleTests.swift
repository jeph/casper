import Testing

struct CasualStyleTests {
  struct Example: Sendable, CustomTestStringConvertible {
    let note: String
    let input: String
    let output: String

    var testDescription: String { note }
  }

  static let examples = [
    Example(
      note: "You becomes u, commas go, and so does the final period.",
      input: "Okay, I'll see you at 5:30.",
      output: "Ok I'll see u at 5:30"
    ),
    Example(
      note: "Your and you're both become ur, keeping a capital first letter.",
      input: "You're the best. Your call though.",
      output: "Ur the best. Ur call tho"
    ),
    Example(
      note: "Curly apostrophes count as apostrophes.",
      input: "You’re late, aren’t you?",
      output: "Ur late aren’t u?"
    ),
    Example(
      note: "Words that only contain a short form, or aren't in the list, stay.",
      input: "You'll love it, you've earned it. Yours, the youth group. Thanks, people.",
      output: "You'll love it you've earned it. Yours the youth group. Thanks people"
    ),
    Example(
      note: "Phrases become short forms, keeping a capital first letter.",
      input: "By the way, let me know right now. To be honest, my bad.",
      output: "Btw lmk rn. Tbh mb"
    ),
    Example(
      note: "A phrase that contains a short form's word becomes one short form.",
      input: "Talk to you later, I'm on my way.",
      output: "Ttyl I'm omw"
    ),
    Example(
      note: "Dashes separate words but break phrases; hyphens join words.",
      input: "You—please wait – by the—way, your-notes are okay-ish.",
      output: "U—pls wait – by the—way your-notes are okay-ish"
    ),
    Example(
      note: "Gonna and gotta, which the model writes, still make ngl and gtg.",
      input: "Not gonna lie, I gotta go. Not going to lie, I got to go!",
      output: "Ngl I gtg. Ngl I gtg!"
    ),
    Example(
      note: "A phrase doesn't match across a mark or a line break.",
      input: "It's for. Real talk.\nWant\nto come? Talk to you\nlater.",
      output: "It's for. Real talk.\nWant\nto come? Talk to u\nlater"
    ),
    Example(
      note: "An all-capitals word or phrase becomes an all-capitals short form.",
      input: "OH MY GOD, YOU did WHAT?",
      output: "OMG U did WHAT?"
    ),
    Example(
      note: "Quotes and brackets around a word or phrase stay.",
      input: "“You” is the word (please) and [for real].",
      output: "“U” is the word (pls) and [fr]"
    ),
    Example(
      note: "Words inside file names and addresses stay.",
      input: "Check your-notes.txt and you.com, okay?",
      output: "Check your-notes.txt and you.com ok?"
    ),
    Example(
      note: "Commas between digits stay.",
      input: "It costs $1,240, not $1,420.",
      output: "It costs $1,240 not $1,420"
    ),
    Example(
      note: "Only the period at the very end goes.",
      input: "Meet me at 3:30 with Mr. Lee about version 2.5.",
      output: "Meet me at 3:30 with Mr. Lee about version 2.5"
    ),
    Example(
      note: "A question mark at the end stays.",
      input: "Is it okay? Want to come?",
      output: "Is it ok? Wanna come?"
    ),
    Example(note: "An exclamation mark at the end stays.", input: "Never mind, I'm here!", output: "Nvm I'm here!"),
    Example(note: "An ellipsis at the end stays.", input: "I'm not sure, though...", output: "I'm not sure tho..."),
    Example(
      note: "Line breaks stay, and only the last line loses its period.",
      input: "Hi, Sam.\nPlease bring the motherfucker.\n",
      output: "Hi Sam.\nPls bring the mf"
    ),
    Example(note: "An empty dictation stays empty.", input: "", output: ""),
  ]

  @Test(arguments: examples) func writesLikeATextMessage(_ example: Example) {
    #expect(CasualStyle.apply(to: example.input) == example.output)
  }
}

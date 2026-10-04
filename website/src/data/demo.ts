export interface Word {
  text: string
  /** `cut` for a word cleanup drops, `swap` for one it writes another way. */
  kind?: "cut" | "swap"
}

export interface Example {
  app: string
  persona: "Formal" | "Casual"
  heard: Word[]
  typed: string
}

/** Splits what was said into words, where a leading `-` marks a word cleanup drops and `~` one it rewrites. */
const words = (spoken: string): Word[] =>
  spoken.split(" ").map((word) => {
    if (word.startsWith("-")) return { text: word.slice(1), kind: "cut" }
    if (word.startsWith("~")) return { text: word.slice(1), kind: "swap" }
    return { text: word }
  })

export const examples: [Example, ...Example[]] = [
  {
    app: "Mail",
    persona: "Formal",
    heard: words("-um -so can you send the deck -thursday -no -wait friday"),
    typed: "Can you send the deck Friday?",
  },
  {
    app: "Notes",
    persona: "Formal",
    heard: words("the total comes to ~twenty ~five ~dollars ~and ~fifty ~cents ~period"),
    typed: "The total comes to $25.50.",
  },
  {
    app: "Messages",
    persona: "Casual",
    heard: words("-uh hey are we still on for tacos tonight ~question ~mark"),
    typed: "hey are we still on for tacos tonight?",
  },
]

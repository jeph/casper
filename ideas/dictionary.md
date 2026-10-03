# Dictionary: words the speech model should know

Status: built, in `feat(dictionary)` (8090c7c). This records the research, the feasibility tests and the decisions behind it; the UI was prototyped first as a throwaway SwiftUI mockup outside the repository.

## Goal

Users keep a list of words, such as names, brands, jargon and slang, that the speech model should be able to write. The list is shared by every voice model. The language model used by Refine is out of scope for now.

## What each model can do with the dependencies Casper already has

No new package is needed. Both paths exist in the pinned versions: speech-swift 0.0.28 and FluidAudio 0.17.4.

### Qwen3-ASR (speech-swift): context in the prompt

- `Qwen3ASRModel.transcribe(audio:sampleRate:language:maxTokens:context:)` and `Qwen3DecodingOptions.context` put the text in the system turn: `<|im_start|>system\n{context}<|im_end|>` (`Sources/Qwen3ASR/Qwen3ASR.swift`, `generateText`). Qwen's own `qwen_asr` package builds the same prompt (`{"role": "system", "content": context}`).
- Qwen trained the model to use this. The Qwen3-ASR technical report (arXiv 2601.21337) says the fine-tuning data included context-biasing examples, so the model reads the system prompt as background knowledge. The context can be any text; a list of words works.
- No extra download or memory. The cost is a few prompt tokens per word in prefill.
- Caveat: speech-swift's `Qwen3Tokenizer.encode` splits words only at whitespace, not with Qwen's pre-tokenizer regex, so text with punctuation can tokenize differently from what the model was trained on. Words separated by newlines or spaces avoid most of that. The eval should check the token IDs against swift-transformers' tokenizer, which Casper already links.

### Parakeet (FluidAudio): correct the transcript afterward with a second model

- The Parakeet TDT decoder in 0.17.4 has no decode-time biasing. `CustomVocabularyTerm.tokenIds` exists, but the TDT decoder never reads it.
- What FluidAudio does have is CTC keyword spotting with rescoring (NeMo's CTC-WS, arXiv 2406.07096; `Documentation/ASR/CustomVocabulary.md`). A separate model, `FluidInference/parakeet-ctc-110m-coreml`, scores each dictionary word against the audio. Where a word in the Parakeet transcript sounds and is spelled close enough to a dictionary word, and the dictionary word scores better acoustically, it gets replaced.
- The extra model is a 101.8 MB `AudioEncoder.mlmodelc`, a 0.6 MB `MelSpectrogram.mlmodelc`, `vocab.json` and `tokenizer.json`. It is **English only**, licensed CC-BY-4.0, and at revision `accdafd8cf8a2ff1cabe3c11e54416b405d409aa`. It would be downloaded at runtime like the other models, so `Acknowledgements.txt` doesn't change.
- Gap in the wiring: Casper uses the plain `AsrManager`, which has no vocabulary hook in 0.17.4. Only `SlidingWindowAsrManager` and the Unified managers have `configureVocabularyBoosting`. The `VocabularyBoostingSession` helper also always loads `tokenizer.json` from FluidAudio's own folder (`~/Library/Application Support/FluidAudio/Models/…`). Casper never creates that folder: it loads Parakeet with `AsrModels.loadLocal(from:)` from `Casper/Models/`.
- Decision: Casper repeats the session's steps itself, in about 40 lines of public API, and keeps the word spotter in `Casper/Models/parakeet-ctc-110m-coreml/`:
  1. `CtcModels.loadDirect(from: casperDirectory)`
  2. `CtcTokenizer.load(from: casperDirectory)` to fill in each `CustomVocabularyTerm`'s `ctcTokenIds`
  3. `CtcKeywordSpotter(models:blankId: models.vocabulary.count)`
  4. `VocabularyRescorer.create(spotter:vocabulary:config:ctcModelDirectory: casperDirectory)`, with every `VocabularyRescorer.Config` field set explicitly. The defaults read `FLUID_*` environment variables, so leaving them implicit would let the environment change Casper's behavior.
  5. For each dictation, take `ASRResult.tokenTimings`, call `spotKeywordsWithLogProbs`, then `ctcTokenEvaluateCandidates` (see "Keeping punctuation" below) with the `cbw` and `minSimilarity` from `ContextBiasingConstants.rescorerConfig(forVocabSize:)`.

## Feasibility test

Three clips made with `say -v Samantha` at 16 kHz and a 10-word list: Jeph, Qwen3, MLX, Siobhan, Unifly, Tailscale, Zed, Himalaya, Anirudh, Casper. Qwen3-ASR ran as the official 0.6B weights in fp32 through `qwen-asr` on the CPU, not the 5-bit MLX build Casper ships. Parakeet Ultra ran through `fluidaudiocli` 0.17.4 with `--custom-vocab`. Synthetic speech and three clips make this a smoke test, not a measurement. Clip C is a control: it uses no dictionary word except the homophone "Jeff", and it has "milk" and "tale", which sit close to "MLX" and "Tailscale".

| Clip | Model | Without dictionary | With dictionary |
|---|---|---|---|
| A | Qwen3-ASR | Tell Jeff … runs **Quin Three** … ask **Shavon** … the **unify** config … the **tail scale** migration. | Tell Jeff … runs **Qwen 3** … ask **Siobhan** … the **Unifly** config … the **Tailscale** migration. |
| B | Qwen3-ASR | … opened sed and ran the **himalaya** command … from Anirudh. | … opened sed and ran the **Himalaya** command … from Anirudh. |
| C | Qwen3-ASR | Jeff … bought some milk … a long tale … | Unchanged. No false replacements. |
| A | Parakeet, library defaults | Tell Jeff … runs **Quen 3** … the **tail scale** migration. | Tell **Jeph** … runs **Qwen3** … the **Tailscale** migration. |
| B | Parakeet, library defaults | **I pushed the fix to the dev branch**, then I opened set … from **Onirud.** | **Jeph the Casper Casper** then I opened set … from **Anirudh** |
| C | Parakeet, library defaults | … bought some **milk**, and told … | **Jeph** said … bought some **MLX** and told … |
| A, B, C | Parakeet, short-word preset¹ | | A as with the library defaults. B: "I pushed the fix to the dev branch, then … from Anirudh". C: only Jeff → Jeph. |

¹ Both rows are FluidAudio's own settings. The library defaults are `VocabularyRescorer.Config()`: no short-word taper (`shortTermCbwTaperPivot: 1`), and the spotter rescue pass on with no similarity floor (`spotterRescueMinSimilarity: 0`, `spotterRescueMultiWordMinSimilarity: 0`). The short-word preset is the one FluidAudio's `CustomVocabulary.md` recommends for lists of short words that sound like ordinary English: `shortTermCbwTaperPivot: 5`, `spotterRescueMinSimilarity: 0.30`, `spotterRescueMultiWordMinSimilarity: 0.50`. The taper shrinks the boost for words under 5 CTC tokens, scaling it by (tokens ÷ 5)². The floors stop the rescue pass from replacing a transcript word that isn't spelled at least 30% like the dictionary word (50% for multi-word spans).

What this shows:

- **Qwen3-ASR fixed five of seven words with no false replacements.** It didn't change "Jeff" to "Jeph", since they sound the same and "Jeff" is the likelier spelling, or "sed" to "Zed". The context nudges the model; it doesn't force a spelling.
- **Parakeet's library defaults are unusable for a personal dictionary.** The acoustic "spotter rescue" pass rewrote half of an ordinary sentence and turned "milk" into "MLX". The short-word preset looked clean in these clips, but see the correction below.

**Correction, found while implementing:** every Parakeet result in this document came from noisy input. FluidAudio 0.17.5 and earlier copy audio shorter than the word spotter's 15-second window into a new `MLMultiArray` and assume the rest is zero, but Core ML doesn't zero new arrays, so leftover memory reaches the model as audio. The same clip gave different replacements depending on what ran before it, and the command-line tool's clean clip C was luck. Casper now pads the audio with silence itself, which gives exactly the output FluidAudio intends. With clean input, the short-word preset turned "milk" into "MLX", "joined" into "Aoife" and "send" into "Zed". Raising the spelling-similarity floor from FluidAudio's 0.50 to 0.55, its own value for larger dictionaries, stopped those and kept every other fix, but "Jeff" no longer becomes "Jeph" unless "Jeff" is a Sounds Like spelling. "unify" → "Unifly" and "Mix" → "MLX" still get through.
- **Homophones need a Sounds Like spelling.** With the 0.55 floor, "Jeff" stays "Jeff" even with "Jeph" in the list, on both models. Adding "Jeff" as a Sounds Like spelling of "Jeph" turns every "Jeff" into "Jeph".
- **Parakeet's rescoring drops punctuation next to a replaced word.** `ctcTokenRescore`, which the command-line tool uses, rebuilds the text from word timings, so "Onirud." became "Anirudh" and the comma after "milk" was lost. "Keeping punctuation" below avoids that.

To reproduce: build `fluidaudiocli` from the FluidAudio 0.17.4 checkout (`swift build -c release --product fluidaudiocli`), run `fluidaudiocli transcribe clip.wav --model-version ultra --custom-vocab words.txt`, and run Qwen with `uv run` on a script that calls `Qwen3ASRModel.from_pretrained("Qwen/Qwen3-ASR-0.6B").transcribe(audio=…, context=…)`.

## Keeping punctuation

Instead of taking `ctcTokenRescore`'s rebuilt text, call `ctcTokenEvaluateCandidates` on the same inputs. It runs the same matching and comparisons but leaves the transcript alone, returning each candidate with:

- `legacyOutcome`: `.applied` marks the candidates `ctcTokenRescore` would have used, after overlapping candidates are resolved.
- `baseTextUTF8Range`: where the replaced words sit in the original transcript, excluding surrounding quotes and trailing punctuation. It is `nil` when FluidAudio can't line the words up with the text exactly.

Casper replaces only the `.applied` candidates that have a range, working from the end of the transcript to the start so earlier ranges stay valid, and skips candidates whose range is `nil`. Parakeet's punctuation stays as it was, with or without Refine, and each replacement takes the capitalization of the text it replaces (see "Capitalization"). This isn't tested yet: the eval should check that it gives the same replacements as `ctcTokenRescore`, minus the lost punctuation, and how often the range is `nil`.

## Sounds Like: what it does for each model

Neither model takes a pronunciation. Qwen3-ASR's only input besides the audio is free text. FluidAudio's word spotter works in spelled subword tokens, not sounds. The "sounds like" spellings are a FluidAudio feature, `CustomVocabularyTerm.aliases`, and they are text, not audio: the rescorer compares the words Parakeet wrote with the dictionary word and its aliases by spelling, and only spelling matches go on to the acoustic comparison. That comparison scores the term's `ctcTokenIds` and also the tokens of the word's own spelling, and keeps the better score.

Test clip D, made with `say`: "I had lunch with Neeve and Seersha, then Eefa called about the Sochee project, and Shivawn joined late." The dictionary was Niamh, Saoirse, Aoife, Xochitl and Siobhan. Parakeet used the short-word preset.

| Setup | Result |
|---|---|
| Parakeet, no dictionary | Neve, Sirsha, Ifa, Sachi, Shivon |
| Parakeet, words only | Only one name fixed; "Sirsha" became **Siobhan** (wrong word) and "joined" became **Aoife** |
| Parakeet, sounds like = what Parakeet wrote (Neve, Sirsha, …) | All five fixed; "joined" still became **Aoife** |
| Parakeet, sounds like = how it's said (Neeve, Seersha, …) | Four fixed (not Aoife); "joined" became **Aoife** |
| Parakeet, word spotter tokens built from how it's said (Neeve, …), with or without sounds like | Same as without those tokens. Pronunciation tokens only take part after a spelling match, and the word's own spelling is scored anyway. Rerun with the tokens lowercased and NFKC-normalized, as FluidAudio's tokenizer does, with the same results; the token IDs came from the same `tokenizer.json` through Python's `tokenizers`, not from FluidAudio's Swift tokenizer |
| Qwen3-ASR, no dictionary | Neven, Sirisha, Efa, Sachi, Shivon |
| Qwen3-ASR, words only | Niamh, Saoirse, Aoife, Siobhan; Xochitl missed |
| Qwen3-ASR, "Niamh (pronounced Neeve)" for each word | Same as words only |
| Qwen3-ASR, "Niamh (sounds like Neve)" for each word | Worse: it wrote the sounds-like spellings (Neve, Sirsha, Ifa, Shivon) |
| Qwen3-ASR, sounds-like spellings in place of the words, then each one swapped for its word in the output | Worse: Qwen wrote its own spellings (Neve, Shivon), not the exact ones given (Neeve, Shivawn), so most weren't swapped. It also wrote "Seersha project" for "Sochee project", which the swap turned into the wrong name, Saoirse |

The last row tested putting the sounds-like spellings into Qwen's context and swapping them back afterward. On the earlier clips it also lost a fix: with "Kwen" in place of "Qwen", Qwen wrote "Quin Three" again. Exact swapping only works when the model writes exactly the spelling the user entered, and a model writes its own guess at an unfamiliar sound. Doing it fuzzily, without swapping real words, needs the acoustic check that FluidAudio's word spotter provides. That check needs word timings, which Parakeet gives and speech-swift's Qwen3-ASR doesn't without its separate forced aligner.

So:

- For Parakeet, Sounds Like is what makes names whose spelling doesn't match their sound work. The words alone produced wrong replacements. Parakeet's actual misspelling worked best; a respelling of how the word is said worked nearly as well.
- For Qwen3-ASR, the words alone in the context work best. Sounds-like spellings in the context make it write them, whether or not they're swapped back.
- Swapping exact Sounds Like spellings for the word *after* the model is still useful, as long as Qwen's context gets only the words. On clip A, Qwen with the words wrote "Jeff", and swapping "Jeff" for "Jeph" fixed the one word the context hadn't. It only touches exact Sounds Like spellings, so words the context already fixed are left alone.
- One false replacement ("joined" → "Aoife") survived every Parakeet setup here. It came from the noisy input described above; with clean input and the 0.55 similarity floor it's gone.

## Large dictionaries

The Settings page doesn't need History's paging. History pages because dictations are unbounded and live in SQLite. A dictionary is a list of short strings that fits in memory, and a SwiftUI `List` on the Mac only creates the rows on screen. In the mockup, built with `-O`, a 20,000-word dictionary:

- drew its page in 0.12–0.24 s across two runs, on top of the mockup's fixed 0.6 s wait;
- searched in 18–24 ms ("ab": 780 matches).

The models are what limit a large dictionary:

- **Qwen3-ASR** reads the whole context with every dictation, at a few tokens per word. A thousand words adds thousands of prompt tokens to each dictation, and 20,000 wouldn't fit.
- **FluidAudio** documents testing up to 230 terms. It tightens its matching above 100, because more terms means more false replacements.

Both need measuring in the eval, with dictionaries of 10, 100, 1,000 and 10,000 words. If large dictionaries are too slow or too error-prone, the fix is choosing which words go to the model for each dictation, not paging the Settings list.

## Proposed design

- **Storage.** A `DictionaryStore` modeled on `PersonaStore`: `@Observable`, saved to `Application Support/Casper/Dictionary.json`, with an on/off setting in `UserDefaults`. `DictionaryWord` holds an `id`, the `text`, and optional `soundsLike` spellings; a sounds-like entry can be several words, such as "tail scale". Words are trimmed, empty ones are rejected, and duplicates are rejected regardless of case.
- **One pipeline for every model.** Nothing outside a transcriber knows which model runs or what it supports. Each dictation goes through:
  1. **The transcriber**, which gets the dictionary entries, words and Sounds Like spellings both, with the audio: `transcribe(_ samples:sampleRate:dictionary:)`. It uses whatever its model or library supports and ignores the rest. A transcriber whose model has no way to take a word list ignores the dictionary.
  2. **The Sounds Like swap**, which Casper runs on every transcript whatever the model: each exact Sounds Like spelling is replaced with its word, whole words only, ignoring case, keeping surrounding punctuation and the model's capitalization. Every spelling is matched against the transcriber's text in one pass, never against text a replacement produced, so with Tailscale ← "tail scale" and Tailspin ← "Tailscale", "tail scale" becomes "Tailscale" and stops there. Where matches overlap, the longest wins, then the earliest. It catches whatever the model didn't. Where a model already corrected a word, the swap finds nothing to replace.
  3. **Refine**, which gets the corrected text.

  Adding a model means writing its transcriber; steps 2 and 3 don't change. See "Dictionary changes take effect without reloading" for how each transcriber keeps up with edits.
- **What each kind of model does in step 1:**
  - *Takes a word list* (Qwen3-ASR's context, a Whisper-style prompt, a decoder biasing list): pass the words only. Qwen3-ASR wrote the Sounds Like spellings when they were in its context, and other prompt-based models are likely to as well; a model that takes alias pairs natively would get both. For Qwen3-ASR this is `context:` with the words joined by newlines.
  - *Corrects Sounds Like natively* (FluidAudio's rescorer for Parakeet, or a future model or library with aliases or pronunciations): pass the words with their Sounds Like spellings as aliases.
  - *Neither*: the transcriber ignores the dictionary, and only the swap in step 2 applies.
- **Parakeet's transcriber.** Load the word spotter alongside Parakeet whenever Parakeet loads, so turning the dictionary on or adding its first word doesn't wait on a model load. Build the rescorer as described above with the short-word preset as Casper's fixed default, every value set explicitly, and a spelling-similarity floor of 0.55; exposing these settings to users can come later. Pad the audio with silence to whole 15-second windows before spotting, then drop the frames past the audio, as described in the correction above. Apply its replacements as in "Keeping punctuation". Sounds-like spellings become `CustomVocabularyTerm.aliases`. Words shorter than 3 characters are skipped (`minTermLength`).
- **Capitalization.** Wherever Casper puts a dictionary word into a transcript, from the swap or from FluidAudio's replacements, one function decides its capitalization from the text it replaces. It's prototyped and checked against the cases in "Capitalization" below.
- **Word spotter download.** The word spotter is part of Parakeet as far as the user can tell. Downloading either Parakeet model also downloads the word spotter, with Casper's own `ModelDownloader`, into `Casper/Models/parakeet-ctc-110m-coreml/`. The model counts as installed, and its download as finished, only once both are on disk. One progress bar covers both, and the size shown on the Voice Models page includes the extra 102 MB. Nothing about it appears on the Dictionary page.
  - Both Parakeet models share one copy. Deleting a Parakeet model deletes the word spotter only when no other Parakeet model is installed.
  - A Parakeet model downloaded before this change has no word spotter. Casper fetches it on launch in the background, and dictation works without the dictionary until it arrives.
  - `DownloadableModel` describes one repository per model, so `SpeechModel` needs a way to list a second repository and revision to download with it.
- **UI** (from the mockup):
  - A Dictionary tab between Refine and History, laid out like History: a card with the Enable Dictionary switch, then a card with a search field, the word list, and an Add Word button. The page never mentions which voice model is active or the word spotter.
  - Each row shows the word and any "Sounds like" spellings. Selecting words replaces Add Word, in the card's footer, with the number selected and Edit and Delete; the right-click menu has the same actions, and double-clicking edits. Delete asks first.
  - The Add Word and Edit Word sheets follow the persona editor, with Word and an optional Sounds Like field. Sounds Like asks for how Casper writes the word when it gets it wrong, such as "Neve" for Niamh, since that's what both the swap and Parakeet's rescoring match best. A word that's already in the dictionary (ignoring case) is an error.
  - The list keeps every word in memory, without paging; see "Large dictionaries".
- **Later.** Adding a word from History, by picking the misheard words in a past dictation. Not in the first version; picking words one by one also doesn't scale to long dictations.
- **Tests and eval.** Unit tests for `DictionaryStore` (rejecting duplicates and empty words, trimming, saving), following the persona store tests, and for the swap and its capitalization, using the cases below. Add `Evals/Dictionary`, following `Evals/SilenceTrim`, with real recordings that include dictionary words, near-miss ordinary words, and other languages for Parakeet. It should measure how many dictionary words come out right and how many ordinary words get replaced, for each model and setting.

## Dictionary changes take effect without reloading

An edit to the dictionary applies to the next dictation that finishes, including one being recorded during the edit, and never reloads a model. `DictationController.transcribe` reads the dictionary when it hands the recording to the transcriber, and `ModelLoader` keeps reloading only when the active model changes.

- **Qwen3-ASR has no prefix cache.** In speech-swift 0.0.28, the MLX `Qwen3ASRModel` that Casper uses builds the prompt, context included, for every call and starts each call with an empty KV cache (`Qwen3ASR.swift`, `var cache: [(MLXArray, MLXArray)]? = nil` before prefill). The Core ML path calls `decoder.resetCache()` at the start of each call. So a new `context:` takes effect on the very next call, and nothing stale can carry over. The cost is that the whole word list is prefilled with every dictation; how much that adds for large lists isn't measured yet and belongs in the eval.
- **Parakeet keeps every model loaded and rebuilds only the term list.** The word spotter (`CtcKeywordSpotter`, holding the Core ML models) doesn't depend on the dictionary. Only `VocabularyRescorer`, built from the spotter and the terms, does. Timed on this Mac with FluidAudio 0.17.4, built with `-c release`:

  | Step | Time |
  |---|---|
  | Load the word spotter, first time after download (Core ML compiles it) | 13.3 s |
  | Load the word spotter, later launches | 0.2 s |
  | Load Parakeet Ultra, first time / later | 8.4 s / 0.07–0.09 s |
  | Tokenize terms | about 0.22 ms per word: 1.2 ms for 10, 222 ms for 1,000, 2.4 s for 10,000 |
  | `VocabularyRescorer.create` from tokenized terms | 2–3 ms for 10 to 10,000 words |

  Tokenizing is the only part that grows with the list, so the transcriber caches each word's token IDs by its text. An edit re-tokenizes only the words that changed and rebuilds the rescorer, a few milliseconds in all, so the transcriber does it at the start of the next dictation when the dictionary differs from the one it last built from. The first build, tokenizing the whole list, runs when Parakeet loads. `VocabularyRescorer.create` also re-reads the word spotter's tokenizer from disk (2 ms); its initializer isn't public, so that can't be shared.
- **Future transcribers** follow the same rule: anything built from the dictionary is rebuilt in place from the new list, and the model stays loaded. A model whose library only accepts a vocabulary when it loads would need a reload per change; adding one would mean weighing that cost.

## Capitalization

A replacement follows the speech model's capitalization of the text it replaces:

1. A capital first letter, when the dictionary word is all lowercase → the word with a capital first letter, as at the start of a sentence.
2. Anything else → the word as spelled in the dictionary, so "iPhone" and "MLX" keep their own capitals, and lowercase "jeff" still becomes "Jeph".

Speech models don't write in all capitals, so there's no rule for it; "EYE PHONE" would become "iPhone".

A throwaway Swift prototype of the swap passes all of these, with Sounds Like entries Jeph ← Jeff, Tailscale ← tail scale, Tailspin ← Tailscale, Niamh ← Neve, kubectl ← cube control, iPhone ← eye phone, MLX ← M L X, and Scalewise ← scale wise:

| Speech model wrote | After the swap |
|---|---|
| Tell Jeff the build passed. | Tell Jeph the build passed. |
| tell jeff later | tell Jeph later |
| Jeff's laptop, and Jeffrey's. | Jeph's laptop, and Jeffrey's. |
| Before the tail scale migration. | Before the Tailscale migration. |
| Tail  scale is down. (two spaces) | Tailscale is down. |
| Is Tailscale down? | Is Tailspin down? |
| Tail scale, not Tailscale. | Tailscale, not Tailspin. |
| The tail scale wise. (overlap, same length) | The Tailscale wise. |
| A scale wise tail scale. | A Scalewise Tailscale. |
| Lunch with Neve? Sure. | Lunch with Niamh? Sure. |
| Run cube control apply. | Run kubectl apply. |
| Cube control is installed. | Kubectl is installed. |
| Buy an eye phone. | Buy an iPhone. |
| Eye phone sales. | iPhone sales. |
| Runs on m l x. | Runs on MLX. |
| “Jeff”, she said. | “Jeph”, she said. |

## Open questions

1. How to handle Parakeet with non-English speech. The word spotter is English only, so either skip rescoring in that case or accept the risk and let the eval measure it. Parakeet doesn't report the language it heard.
2. Later: give the same list to Refine, so the language model doesn't change "Siobhan" back to "Shavon".

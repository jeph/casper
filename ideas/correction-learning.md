# Automatically Add to Dictionary: learning words from the user's edits

Status: built, in `feat(dictionary)` (f14fa48). This records the experiments behind the design, so nobody repeats them without a new reason.

## What it does

After Casper pastes a dictation, it watches the field it pasted into through Accessibility (read-only), compares the field with what it typed each time the user stops typing for 3 seconds, and finds words the user replaced. Each paste has its own watch, lasting a minute; moving focus elsewhere or pasting another dictation doesn't end it, so a fix made after coming back still counts. A watch ends sooner when the field is emptied or closed, or when it changes while it doesn't have focus: the user can only type into the focused field, so that change is the app reusing the field for other content, such as Notes showing another note. Each candidate is checked once per paste by transcribing the same recording again with the candidate in the dictionary (a "replay"). The word is added only if the replay writes it where the transcript had the replaced words. Added words get a silent notification with Undo.

The first version compared the field only once, when the watch ended, which was 30 seconds after the paste unless focus moved within the same app; switching to another app doesn't end the watch. In use, words took 10 to 30 seconds to be added, though the replay itself takes under half a second. Checking after a 3-second pause risks checking a half-typed word; the replay rejects those with Qwen, but Parakeet's word spotter can accept them, as it accepted "Sine" in the tests below.

## OpenWhispr's approach, and why it isn't enough

OpenWhispr (`src/utils/correctionLearner.js` at 85b0115) learns any replaced word that passes text filters: about 150 common words, 3 letters minimum, a rewrite limit (more than half the words changed), and edit distance at most 0.65 of the longer word. Run on Casper-style edits, it:

- learned content edits and mistakes: "Thursday" (from "Friday"), "walk" (from "walked"), "config" (from "configs"), the typo "Sinaed", and a half-typed "Sine";
- missed real name fixes whose spelling differs too much: "Shivon" to "Siobhan" (0.71) and "Neve" to "Niamh" (0.80).

Casper keeps OpenWhispr's filters, including the 0.65 limit, as a first pass, and adds the replay as the deciding check. Unlike OpenWhispr, a run of changed words is one correction, so "tail scale" to "Tailscale" and "Quen 3" to "Qwen3" are found as written.

## Replay test

Eight clips spoken by macOS's `say`, 32 edits per model, each judged at the spot that was edited. Harness: `/tmp/dictionary-smoke` (throwaway), compiled against a snapshot of Casper's sources.

| | Qwen3-ASR 0.6B 5-bit | Parakeet Ultra + word spotter |
|---|---|---|
| Judged right | 25 of 32 | 15 of 29 (3 skipped, already right) |
| Words added | 8, 7 correct | 8, 2 correct |
| Real fixes caught | 7 of 13 | 2 of 10 |

- **Qwen** rejected every deliberate edit and both same-sounding swaps. Its one wrong addition was the typo "Sinaed": when the audio is close, Qwen copies the spelling from its prompt. Each replay took 0.2 to 0.7 s on 3 to 4 s clips.
- **Parakeet** added walk, config, Sinaed, Sine, Pam and Unifly, and missed most names (Siobhan, Niamh, Saoirse, Aoife, Xochitl, Zed). The word spotter only considers dictionary words spelled close to what Parakeet wrote (similarity 0.55, or 0.30 in its rescue pass), then gives them a bonus, so near-spellings win and differently spelled names are never compared.

### The shipped pipeline on the same clips

The same 32 edits run through the shipped `CorrectionFinder` (with the 0.65 limit and the other filters) and `ReplayCheck`, each edit as a field after the user's change:

- **Qwen**: 25 right, 7 wrong. It added Siobhan (twice), Tailscale, Aoife, Kubernetes and Unifly, all correct, and nothing wrong: the 0.65 limit filtered out "Sinaed". It missed Sinead (filtered, 0.67), Qwen3 ("Quinn three" is spelled too differently), Xochitl (replay didn't write it), and Niamh, Saoirse, Anirudh and Zed, where the harness edits one name inside a misheard stretch that covers two words.
- **Parakeet**: 15 right, 14 wrong, as in the replay test. It added walk, config, Sinaed, Sine, Pam and Unifly, all wrong, and Qwen3 and Tailscale, both right.

## Word spotter scores without the bonus

To see whether Parakeet's audio could judge corrections at all, the edited word and the replacement were scored directly against the audio frames where the word was spoken (CTC log-probability per frame, replacement minus original):

- Every real fix scored at or below +0.30 (Tailscale), most far below zero: Siobhan -2.23 and -3.66, Aoife -4.07, Niamh -4.31.
- Eight edits that shouldn't be learned scored above zero, from config (+0.10) to call (+4.93).
- FluidAudio's own raw scores (`ctcTokenEvaluateCandidates`, ignoring the bonus) agreed: the replacement scored better for walk, config, Sinaed, Sine and Pam (all wrong) and for Qwen3 and Tailscale, and worse for Anirudh and Xochitl.

No cut-off separates the two groups. The word spotter predicts word pieces from the sound and has no idea that "Siobhan" is pronounced "Shivawn"; at about 80 ms per frame, near-spellings like "walk" and "walked" cost almost nothing. Turning off the rescue pass (`spotterRescueEnabled = false`, confirmed reaching the rescorer) changed no result on these clips.

## Edit distance as an extra filter

On every word the replay accepted, a 0.65 limit blocks:

- Qwen: 1 of 7 real fixes (Shane to Sinead, 0.67) and its 1 wrong addition (Sinaed, 0.67);
- Parakeet: nothing; its wrong additions are all near-spellings (0.14 to 0.33).

It mostly costs names, and only Qwen benefits. It's kept to match OpenWhispr and as a backstop against a prompt word pulling the transcript toward an unrelated word.

## Keeping dictation first

A replay holds the speech model, and each transcriber handles one call at a time, so replays wait until Casper is idle and a recording that starts cancels the replay in progress. Qwen's transcriber uses `transcribeCheckingCancellation`, which stops between tokens; FluidAudio's decoder checks for cancellation too. Longest time from cancelling to the model being free, 31 cancellation points per length, on an otherwise idle Mac:

| Audio | Parakeet Ultra + word spotter | Qwen3-ASR 0.6B 5-bit |
|---|---|---|
| 10 s | 49 ms | 32 ms |
| 30 s | 88 ms | 204 ms |
| 51 s | 115 ms | 412 ms |

The part Qwen can't stop is feature extraction, the audio encoder and the prompt prefill. Since the cancel happens when the next recording starts, the model is free before that recording ends, so no length cap on replayed dictations is needed. With other heavy work running, the same measurement reached 1.1 s for Qwen on 51 s of audio.

When the harness ran this measurement from `main.swift` top-level code, it crashed with a null dereference whenever Qwen ran after Parakeet in the same process, and stopped crashing when print statements were added or the identical code was moved into a function. Casper's code never runs in top-level code, but if a crash appears near cancelled Qwen transcriptions, start here.

## Known limits

- Parakeet users get the same feature with its wrong additions; Undo and the Dictionary page are the way out. A better check for Parakeet would need a model that knows pronunciation.
- Names spelled too differently from the transcript ("Shivon" to "Siobhan", "Neve" to "Niamh") are never learned, because of the 0.65 limit.
- A replay is judged between the nearest unchanged words on either side, so a replay that also changed a neighbouring word rejects the correction.
- A correction doesn't record which occurrence the user edited. If the replaced words appear more than once in the dictation, the replay must write the replacement at every one; if they appear in more than one dictation of the same paste, the correction is dropped.
- Fields that don't expose their text through Accessibility, such as some terminals and Electron apps, aren't watched.
- All numbers come from synthetic speech: one `say` voice, eight clips.

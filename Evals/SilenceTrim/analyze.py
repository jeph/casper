# /// script
# requires-python = ">=3.12"
# dependencies = ["jiwer"]
# ///
"""Summarizes TrimEval results: speech cut, word errors, punctuation, and time, per longest pause and condition."""

import argparse
import difflib
import json
import re
import statistics
from collections import defaultdict
from pathlib import Path

import jiwer

PUNCTUATION = re.compile(r"[^\w\s']")


def words(text: str) -> list[str]:
    return PUNCTUATION.sub(" ", text.lower().replace("’", "'")).split()


def marks(text: str) -> list[tuple[str, str]]:
    """Each word with the punctuation class after it: '' none, ',' pause, '.' sentence end."""
    result = []
    for token in text.replace("’", "'").split():
        word = PUNCTUATION.sub("", token.lower())
        if not word:
            if result and token[-1:] in ".?!":
                result[-1] = (result[-1][0], ".")
            elif result and token[-1:] in ",;:—-" and not result[-1][1]:
                result[-1] = (result[-1][0], ",")
            continue
        tail = token.rstrip("\"')”’")
        mark = "." if tail[-1:] in ".?!" else "," if tail[-1:] in ",;:—" else ""
        result.append((word, mark))
    return result


def punctuation_counts(hypothesis: str, reference: str) -> dict[str, int]:
    """True positives, false positives, and false negatives for commas and sentence ends on aligned words."""
    hyp, ref = marks(hypothesis), marks(reference)
    matcher = difflib.SequenceMatcher(a=[w for w, _ in ref], b=[w for w, _ in hyp], autojunk=False)
    counts = defaultdict(int)
    for block in matcher.get_matching_blocks():
        for offset in range(block.size):
            expected, found = ref[block.a + offset][1], hyp[block.b + offset][1]
            for kind in ",.":
                if expected == kind and found == kind:
                    counts[f"{kind}tp"] += 1
                elif found == kind:
                    counts[f"{kind}fp"] += 1
                elif expected == kind:
                    counts[f"{kind}fn"] += 1
    return counts


def f1(counts: dict[str, int], kind: str) -> float:
    tp, fp, fn = counts[f"{kind}tp"], counts[f"{kind}fp"], counts[f"{kind}fn"]
    return 2 * tp / max(1, 2 * tp + fp + fn)


def cut_speech(kept: list[list[float]], active: list[list[float]], duration: float) -> float:
    """Seconds of active speech that fall outside the kept ranges."""
    cuts, cursor = [], 0.0
    for start, end in kept:
        if start > cursor + 1e-9:
            cuts.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < duration - 1e-9:
        cuts.append((cursor, duration))
    return sum(max(0.0, min(ce, ae) - max(cs, as_)) for cs, ce in cuts for as_, ae in active)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("results", type=Path, nargs="+")
    args = parser.parse_args()

    manifest = {e["id"]: e for e in map(json.loads, args.manifest.read_text().splitlines())}
    results = [json.loads(line) for path in args.results for line in path.read_text().splitlines()]
    by_item = defaultdict(dict)
    for result in results:
        by_item[result["id"]][result["variant"]] = result
    variants = sorted({r["variant"] for r in results}, key=lambda v: -1 if v == "original" else float(v))
    conditions = list(dict.fromkeys(e["condition"] for e in manifest.values()))

    print(f"{len(by_item)} recordings\n")
    header = (
        f"{'variant':>9} {'kept':>5} {'speech cut':>10} {'items cut':>9} {'WER':>6} {'changed':>7} "
        f"{'worse':>5} {'better':>6} {'comma F1':>8} {'end F1':>6} {'Δ time':>8} {'Δ p10':>7} {'trim p99':>8}"
    )
    for scope in ["all"] + conditions:
        print(f"== {scope}")
        print(header)
        ids = [i for i in by_item if scope == "all" or manifest[i]["condition"] == scope]
        for variant in variants:
            rows = [(manifest[i], by_item[i]["original"], by_item[i][variant]) for i in ids if variant in by_item[i]]
            references = [" ".join(words(m["reference"])) for m, _, _ in rows]
            hypotheses = [" ".join(words(r["text"])) or "<empty>" for _, _, r in rows]
            wer = jiwer.wer(references, hypotheses)
            item_errors = [
                (
                    jiwer.process_words(" ".join(words(m["reference"])), " ".join(words(o["text"])) or "<empty>"),
                    jiwer.process_words(" ".join(words(m["reference"])), " ".join(words(r["text"])) or "<empty>"),
                )
                for m, o, r in rows
            ]
            errors = lambda o: o.substitutions + o.deletions + o.insertions
            worse = sum(errors(t) > errors(o) for o, t in item_errors)
            better = sum(errors(t) < errors(o) for o, t in item_errors)
            changed = sum(words(o["text"]) != words(r["text"]) for _, o, r in rows)
            counts = defaultdict(int)
            for m, _, r in rows:
                for key, value in punctuation_counts(r["text"], m["reference"]).items():
                    counts[key] += value
            speech_cut = [cut_speech(r["kept"], m["active"], m["duration"]) for m, _, r in rows]
            kept = sum(r["outputSeconds"] for _, _, r in rows) / sum(r["inputSeconds"] for _, _, r in rows)
            deltas = [r["transcribeMilliseconds"] - o["transcribeMilliseconds"] for _, o, r in rows]
            trims = [r["trimMilliseconds"] for _, _, r in rows]
            print(
                f"{variant:>9} {kept:>5.0%} {sum(speech_cut) * 1000:>8.0f}ms {sum(c > 0 for c in speech_cut):>9} "
                f"{wer:>6.2%} {changed:>7} {worse:>5} {better:>6} {f1(counts, ','):>8.3f} {f1(counts, '.'):>6.3f} "
                f"{statistics.median(deltas):>6.0f}ms {percentile(deltas, 0.1):>5.0f}ms {percentile(trims, 0.99):>6.2f}ms"
            )
        print()

    print("== transcription time by recording length (median ms, original → trimmed)")
    buckets = [(0, 5), (5, 10), (10, 15), (15, 20), (20, 30), (30, 60)]
    print(f"{'length':>8} {'n':>4} " + " ".join(f"{v:>13}" for v in variants))
    for low, high in buckets:
        ids = [i for i in by_item if low <= manifest[i]["duration"] < high]
        if not ids:
            continue
        cells = []
        for variant in variants:
            times = [by_item[i][variant]["transcribeMilliseconds"] for i in ids if variant in by_item[i]]
            cells.append(f"{statistics.median(times):>11.0f}ms")
        print(f"{low:>3}-{high:<3}s {len(ids):>4} " + " ".join(f"{c:>13}" for c in cells))


if __name__ == "__main__":
    main()

# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy", "soundfile"]
# ///
"""Builds dictation-like recordings from LibriSpeech test-clean for evaluating SilenceTrimmer.

Each recording joins one to three consecutive utterances by one reader, adds silence before, between, and after them,
inserts thinking pauses at gaps between words, and renders the result under several background conditions. It records
where the reader's speech is loud enough to matter, so cuts into speech can be counted without any speech model.
"""

import argparse
import json
import random
from pathlib import Path

import numpy as np
import soundfile

SAMPLE_RATE = 16_000
SLICE = SAMPLE_RATE // 100

CONDITIONS = {
    # speech level (dBFS RMS of active speech), background kind, background level or SNR
    "quiet": dict(speech_db=-26, noise="pink", noise_db=-62),
    "fan": dict(speech_db=-26, noise="pink", snr=20),
    "loud_fan": dict(speech_db=-26, noise="pink", snr=10),
    "babble": dict(speech_db=-26, noise="babble", snr=15),
    "soft_voice": dict(speech_db=-46, noise="pink", noise_db=-82),
    "soft_start": dict(speech_db=-26, noise="pink", snr=20, soft_start=True),
}


def slice_levels(audio: np.ndarray) -> np.ndarray:
    count = len(audio) // SLICE
    frames = audio[: count * SLICE].reshape(count, SLICE)
    return 10 * np.log10(np.maximum((frames**2).mean(axis=1), 1e-12))


def active_mask(audio: np.ndarray) -> np.ndarray:
    """Slices where the clean utterance carries speech: well above its own background and not far below its peak."""
    levels = slice_levels(audio)
    floor = np.percentile(levels, 5)
    peak = np.percentile(levels, 99)
    return levels > max(floor + 12, peak - 45)


def word_gaps(audio: np.ndarray, mask: np.ndarray) -> list[int]:
    """Sample positions in the middle of gaps of at least 150 ms inside an utterance, where a pause can go."""
    gaps, start = [], None
    for index, active in enumerate(mask):
        if not active and start is None:
            start = index
        elif active and start is not None:
            if index - start >= 15 and start > 0:
                gaps.append((start + index) // 2 * SLICE)
            start = None
    return gaps


def pink_noise(length: int, rng: np.random.Generator) -> np.ndarray:
    spectrum = np.fft.rfft(rng.standard_normal(length))
    frequencies = np.fft.rfftfreq(length, 1 / SAMPLE_RATE)
    spectrum /= np.sqrt(np.maximum(frequencies, 20))
    noise = np.fft.irfft(spectrum, length)
    return noise / np.sqrt((noise**2).mean())


def babble_noise(length: int, pool: list[np.ndarray], rng: np.random.Generator) -> np.ndarray:
    babble = np.zeros(length)
    for _ in range(6):
        voice = pool[rng.integers(len(pool))]
        tiled = np.tile(voice, length // len(voice) + 2)
        offset = rng.integers(len(voice))
        babble += tiled[offset : offset + length] / np.sqrt((voice**2).mean())
    return babble / np.sqrt((babble**2).mean())


def rms_db(audio: np.ndarray) -> float:
    return 10 * np.log10(max((audio**2).mean(), 1e-12))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--librispeech", type=Path, required=True)
    parser.add_argument("--punctuated", type=Path, required=True, help="LibriSpeech-PC test-clean.json")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--recordings", type=int, default=240)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    choice = random.Random(args.seed)
    punctuated = {}
    for line in args.punctuated.read_text().splitlines():
        entry = json.loads(line)
        punctuated[Path(entry["audio_filepath"]).stem] = entry["text"]

    chapters: dict[str, list[Path]] = {}
    for path in sorted(args.librispeech.glob("*/*/*.flac")):
        if path.stem in punctuated:
            chapters.setdefault(path.parent.name, []).append(path)
    chapter_names = sorted(chapters)
    babble_pool = [soundfile.read(p, dtype="float64")[0] for p in choice.sample(sorted(sum(chapters.values(), [])), 40)]

    audio_dir = args.out / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    manifest = []
    for number in range(args.recordings):
        chapter = chapters[chapter_names[number % len(chapter_names)]]
        count = choice.choice([1, 1, 2, 2, 3])
        start = choice.randrange(max(1, len(chapter) - count))
        utterances = [u for u in chapter[start : start + count] if soundfile.info(u).duration < 20] or [chapter[start]]
        # One recording in five is speech from start to end, the case where nothing should be cut.
        continuous = number % 5 == 0

        pieces, active, pauses = [], [], []

        def add_silence(seconds: float) -> None:
            length = round(seconds * 100) * SLICE
            position = sum(len(p) for p in pieces)
            pieces.append(np.zeros(length))
            active.append(np.zeros(length // SLICE, dtype=bool))
            pauses.append([position / SAMPLE_RATE, (position + length) / SAMPLE_RATE])

        add_silence(0.05 if continuous else choice.uniform(0.2, 2.5))
        for index, path in enumerate(utterances):
            if index > 0:
                add_silence(choice.uniform(0.1, 0.3) if continuous else choice.uniform(0.25, 4.0))
            audio = soundfile.read(path, dtype="float64")[0]
            audio = audio[: len(audio) // SLICE * SLICE]
            mask = active_mask(audio)
            gaps = [] if continuous else choice.sample(word_gaps(audio, mask), min(2, len(word_gaps(audio, mask))))
            cursor = 0
            for gap in sorted(gaps):
                pieces.append(audio[cursor:gap])
                active.append(mask[cursor // SLICE : gap // SLICE])
                add_silence(choice.uniform(0.25, 3.0))
                cursor = gap
            pieces.append(audio[cursor:])
            active.append(mask[cursor // SLICE :])
        add_silence(0.15 if continuous else choice.uniform(0.15, 1.5))

        speech = np.concatenate(pieces)
        speech_mask = np.concatenate(active)
        speech_mask = np.pad(speech_mask, (0, len(speech) // SLICE - len(speech_mask)))[: len(speech) // SLICE]
        active_samples = np.repeat(speech_mask, SLICE)[: len(speech)]
        active_level = rms_db(speech[: len(active_samples)][active_samples])
        reference = " ".join(punctuated[u.stem] for u in utterances)

        for condition, settings in CONDITIONS.items():
            voice = speech * 10 ** ((settings["speech_db"] - active_level) / 20)
            if settings.get("soft_start"):
                first = np.argmax(active_samples)
                gain = np.ones(len(voice))
                softened = int(1.5 * SAMPLE_RATE)
                ramp = int(0.1 * SAMPLE_RATE)
                gain[first : first + softened] = 10 ** (-15 / 20)
                gain[first + softened : first + softened + ramp] = np.linspace(10 ** (-15 / 20), 1, ramp)[
                    : len(gain[first + softened : first + softened + ramp])
                ]
                voice = voice * gain
            if settings["noise"] == "pink":
                noise = pink_noise(len(voice), rng)
            else:
                noise = babble_noise(len(voice), babble_pool, rng)
            noise_db = settings.get("noise_db", settings["speech_db"] - settings.get("snr", 0))
            mixed = voice + noise * 10 ** (noise_db / 20)
            peak = np.abs(mixed).max()
            if peak > 0.99:
                mixed *= 0.99 / peak
            identifier = f"{number:03d}-{condition}"
            mixed.astype("<f4").tofile(audio_dir / f"{identifier}.f32")
            manifest.append(
                {
                    "id": identifier,
                    "recording": number,
                    "condition": condition,
                    "continuous": continuous,
                    "duration": len(mixed) / SAMPLE_RATE,
                    "reference": reference,
                    "pauses": pauses,
                    "active": runs(speech_mask),
                    "audio": str((audio_dir / f"{identifier}.f32").resolve()),
                }
            )

    with (args.out / "manifest.jsonl").open("w") as file:
        for entry in manifest:
            file.write(json.dumps(entry) + "\n")
    print(f"{len(manifest)} items, {sum(e['duration'] for e in manifest) / 3600:.2f} hours")


def runs(mask: np.ndarray) -> list[list[float]]:
    """The active slices as [start, end] second ranges."""
    ranges, start = [], None
    for index, value in enumerate(list(mask) + [False]):
        if value and start is None:
            start = index
        elif not value and start is not None:
            ranges.append([start * SLICE / SAMPLE_RATE, index * SLICE / SAMPLE_RATE])
            start = None
    return ranges


if __name__ == "__main__":
    main()

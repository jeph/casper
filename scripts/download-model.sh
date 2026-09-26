#!/usr/bin/env bash
# Downloads the speech model bundled into Casper, pinned to one Hugging Face revision, and verifies its checksums.
set -euo pipefail

repo="aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
revision="e5450a26d1fd417c45fc9c405651ddc3180a27a6"
name="Qwen3-ASR-1.7B-MLX-8bit"
files=(config.json merges.txt model.safetensors model.safetensors.index.json tokenizer_config.json vocab.json)

cd "$(dirname "$0")/../Models"
checksums="$PWD/$name.sha256"

if [[ -d "$name" ]] && (cd "$name" && shasum -a 256 --check --status "$checksums"); then
  exit 0
fi

mkdir -p "$name"
for file in "${files[@]}"; do
  echo "Downloading $repo/$file"
  curl --fail --location --continue-at - --output "$name/$file" \
    "https://huggingface.co/$repo/resolve/$revision/$file"
done
(cd "$name" && shasum -a 256 --check "$checksums")

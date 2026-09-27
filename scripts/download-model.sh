#!/usr/bin/env bash
# Downloads a model bundled into Casper from one pinned Hugging Face revision, and verifies it against the checksum
# file next to the model's folder, which also lists the files to download.
#
# Usage: scripts/download-model.sh <repo> <revision> <model folder>
set -euo pipefail

repo="$1"
revision="$2"
folder="$3"
checksums="$(cd "$(dirname "$folder")" && pwd)/$(basename "$folder").sha256"

if [[ -d "$folder" ]] && (cd "$folder" && shasum -a 256 --check --status "$checksums"); then
  exit 0
fi

mkdir -p "$folder"
while read -r _ file; do
  echo "Downloading $repo/$file"
  curl --fail --location --continue-at - --output "$folder/$file" \
    "https://huggingface.co/$repo/resolve/$revision/$file"
done <"$checksums"
(cd "$folder" && shasum -a 256 --check "$checksums")

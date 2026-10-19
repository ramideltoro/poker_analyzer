#!/bin/bash
# Reproduce the three downloaded archives and compact local reference summary.
# Raw files stay outside this Git checkout. Requires ~20 GB free space to extract.
set -euo pipefail
referenceProject="$(cd "$(dirname "$0")/.." && pwd)"
referenceDestination="${1:?Usage: bash scripts/fetch-reference-data.sh /absolute/data-directory}"
mkdir -p "$referenceDestination/raw" "$referenceDestination/extracted/phh" "$referenceDestination/extracted/uci"
referenceDestination="$(cd "$referenceDestination" && pwd)"
referenceFetch() {
  local referenceName="$1" referenceURL="$2" referenceHash="$3"
  if [[ ! -f "$referenceDestination/raw/$referenceName" ]]; then
    curl --fail --location --retry 3 --output "$referenceDestination/raw/$referenceName.partial" "$referenceURL"
    mv "$referenceDestination/raw/$referenceName.partial" "$referenceDestination/raw/$referenceName"
  fi
  local referenceActual
  referenceActual="$(shasum -a 256 "$referenceDestination/raw/$referenceName")"
  [[ "${referenceActual%% *}" == "$referenceHash" ]] || { echo "Checksum mismatch: $referenceName. Upstream ref may have changed; preserve existing data and review provenance." >&2; exit 1; }
}
referenceFetch phevaluator.tar.gz https://codeload.github.com/HenryRLee/PokerHandEvaluator/tar.gz/refs/heads/develop 5cb6dc678b7115bb3670098793786e8775c0cbec65318ae3683d9a61b0073369
referenceFetch phh-dataset.tar.gz https://codeload.github.com/uoftcprg/phh-dataset/tar.gz/refs/heads/main deb529cff7e00ecba967cbcb9fa2d83194d9860324ede3240a7b3bd7e277d5a1
referenceFetch uci-poker.zip https://archive.ics.uci.edu/static/public/158/poker+hand.zip c18333f541b344effb8f446c30f398634d1d045e7b991f3c3399e69af940c4c9
tar -xzf "$referenceDestination/raw/phh-dataset.tar.gz" -C "$referenceDestination/extracted/phh" --strip-components=1
unzip -oq "$referenceDestination/raw/uci-poker.zip" -d "$referenceDestination/extracted/uci"
referenceTool="$(bash "$referenceProject/scripts/build-reference-tool.sh")"
"$referenceTool" "$referenceDestination/extracted/phh" "$referenceDestination/extracted/uci" "$referenceDestination/reference-data.json"
# The app always has a checked-in summary; replacing it is an explicit development step.
echo "Imported: $referenceDestination/reference-data.json"
echo "Compare it with Sources/PokerCore/Resources/reference-data.json before rebuilding."

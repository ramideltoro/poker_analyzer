#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
referenceBuild="${TMPDIR:-/tmp}/livecardreader-reference-tool"
mkdir -p "$referenceBuild"
for referenceSource in Sources/CPokerEvaluator/*.c; do
  /Library/Developer/CommandLineTools/usr/bin/clang -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -O3 -I Sources/CPokerEvaluator -c "$referenceSource" -o "$referenceBuild/$(basename "$referenceSource" .c).o"
done
/Library/Developer/CommandLineTools/usr/bin/clang++ -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -O3 -std=c++17 -I Sources/CPokerEvaluator/include Tools/ReferenceDataTool/main.cpp "$referenceBuild"/*.o -o "$referenceBuild/poker-reference-tool"
echo "$referenceBuild/poker-reference-tool"

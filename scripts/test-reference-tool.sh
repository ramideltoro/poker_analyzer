#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
referenceTestTool="$(bash scripts/build-reference-tool.sh)"
referenceTestOutput="$(mktemp -d)"
trap 'rm -rf "$referenceTestOutput"' EXIT
"$referenceTestTool" Tools/ReferenceDataTool/Fixtures/phh Tools/ReferenceDataTool/Fixtures/uci "$referenceTestOutput/result.json"
ruby -rjson - "$referenceTestOutput/result.json" <<'RUBY'
a=JSON.parse(File.read(ARGV[0]))
abort 'Importer fixture failed' unless a['hands']==2 && a['duplicateHandHQIDs']==1 && a['conflictingDuplicateActions']==0 && a['excludedVariants']==1 && a['classes']['AKs']['known']==1 && a['classes']['QJs']['categories'][8]==1 && a['uciRows']==1 && a['uciMismatches']==0
puts 'Importer duplicate / multiline / category fixtures passed'
RUBY
mkdir -p "$referenceTestOutput/conflicting/handhq"
cat > "$referenceTestOutput/conflicting/handhq/conflict.phhs" <<'PHH'
[1]
variant = 'NT'
actions = ['d dh p1 AhKh']
hand = 1
venue = 'Test'
[2]
variant = 'NT'
actions = ['d dh p1 QsJs']
hand = 1
venue = 'Test'
PHH
"$referenceTestTool" "$referenceTestOutput/conflicting" Tools/ReferenceDataTool/Fixtures/uci "$referenceTestOutput/conflict.json"
ruby -rjson -e 'a=JSON.parse(File.read(ARGV[0]));abort "Missing quarantine report" unless a["conflictingDuplicateActions"]==1 && a["quarantinedRecords"]==2 && a["hands"]==0' "$referenceTestOutput/conflict.json"

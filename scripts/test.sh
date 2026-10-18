#!/bin/bash
set -euo pipefail
coachProject="$(cd "$(dirname "$0")/.." && pwd)"
cd "$coachProject"
bash scripts/swift-tool.sh build --build-tests
coachBin="$(bash scripts/swift-tool.sh build --show-bin-path)"
coachTests="$coachBin/MacPokerCoachPackageTests.xctest"
[[ -d "$coachTests" ]] || { echo 'Test bundle is missing.' >&2; exit 1; }
# Direct invocation avoids a SwiftPM/Xcode discovery mismatch on this host.
exec /Applications/Xcode.app/Contents/Developer/usr/bin/xctest "$coachTests"

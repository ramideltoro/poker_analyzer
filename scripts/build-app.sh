#!/bin/bash
set -euo pipefail
coachProject="$(cd "$(dirname "$0")/.." && pwd)"
cd "$coachProject"
bash scripts/swift-tool.sh build -c release
coachBin="$(bash scripts/swift-tool.sh build -c release --show-bin-path)"
coachStage="$(mktemp -d "$coachProject/.build/app-stage.XXXXXX")"
coachBundle="$coachStage/Live Card Reader.app"
mkdir -p "$coachBundle/Contents/MacOS" "$coachBundle/Contents/Resources" "$coachProject/dist"
cp "$coachBin/MacPokerCoach" "$coachBundle/Contents/MacOS/MacPokerCoach"
cp "$coachProject/Sources/PokerCore/Resources/reference-data.json" "$coachBundle/Contents/Resources/"
cp -R "$coachProject/ThirdParty" "$coachBundle/Contents/Resources/ThirdParty"
cp "$coachProject/Info.plist" "$coachBundle/Contents/Info.plist"
codesign --force --sign - --identifier local.livecardreader "$coachBundle"
codesign --verify --strict "$coachBundle"
if [[ -d "$coachProject/dist/Live Card Reader.app" ]]; then
  coachPrevious="$(mktemp -d "$coachProject/.build/previous-app.XXXXXX")"
  mv "$coachProject/dist/Live Card Reader.app" "$coachPrevious/"
fi
mv "$coachBundle" "$coachProject/dist/Live Card Reader.app"
rmdir "$coachStage"
echo "Built: $coachProject/dist/Live Card Reader.app"

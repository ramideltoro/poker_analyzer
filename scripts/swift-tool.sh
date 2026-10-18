#!/bin/bash
set -euo pipefail
coachProject="$(cd "$(dirname "$0")/.." && pwd)"
cd "$coachProject"
coachToolchain="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
if [[ ! -x "$coachToolchain/usr/bin/swift" ]]; then
  echo 'Install Xcode from Apple to build this app.' >&2
  exit 1
fi
coachSDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
if [[ ! -d "$coachSDK" ]]; then
  coachSDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi
coachDeveloper="/Library/Developer/CommandLineTools"
if [[ ! -d "$coachDeveloper" ]]; then coachDeveloper="/Applications/Xcode.app/Contents/Developer"; fi
coachCommand="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
coachTestFrameworks="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
coachTestLibraries="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib"
exec env DEVELOPER_DIR="$coachDeveloper" "$coachToolchain/usr/bin/swift" "$coachCommand" \
  --build-system native --toolchain "$coachToolchain" --sdk "$coachSDK" \
  -Xswiftc -F -Xswiftc "$coachTestFrameworks" -Xswiftc -I -Xswiftc "$coachTestLibraries" \
  -Xlinker -F -Xlinker "$coachTestFrameworks" -Xlinker -rpath -Xlinker "$coachTestFrameworks" \
  -Xlinker -L -Xlinker "$coachTestLibraries" -Xlinker -rpath -Xlinker "$coachTestLibraries" "$@"

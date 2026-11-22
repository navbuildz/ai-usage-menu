#!/bin/bash
set -eu
cd "$(dirname "$0")"
args=(-project AIUsageMenu.xcodeproj -scheme AIUsageMenu -derivedDataPath build CODE_SIGNING_ALLOWED=NO)
case "${1:-build}" in
  build) exec xcodebuild "${args[@]}" -configuration Release -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build ;;
  test) exec xcodebuild "${args[@]}" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" test ;;
  *) echo "Usage: $0 [build|test]" >&2; exit 2 ;;
esac

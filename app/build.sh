#!/bin/bash
set -eu
cd "$(dirname "$0")"
args=(-project AIUsageMenu.xcodeproj -scheme AIUsageMenu -derivedDataPath build CODE_SIGNING_ALLOWED=NO)
case "${1:-build}" in
  build) exec xcodebuild "${args[@]}" -configuration Release -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build ;;
  test) exec xcodebuild "${args[@]}" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" test ;;
  sign)
    # Signs the Release build with BaseThread LLC's Developer ID and the hardened runtime, inner parts
    # first. Local use only: notarization and release are separate steps that need Nav's go.
    app="build/Build/Products/Release/AI Usage Menu.app"
    identity="${SIGN_IDENTITY:-Developer ID Application: BaseThread LLC (U5HKKL4525)}"
    sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    for item in "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/Autoupdate" "$sparkle/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
      [ -e "$item" ] && codesign --force --options runtime --timestamp --sign "$identity" "$item"
    done
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
    ;;
  *) echo "Usage: $0 [build|test|sign]" >&2; exit 2 ;;
esac

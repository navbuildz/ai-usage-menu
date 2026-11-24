#!/bin/bash
# Refreshes Resources/Localizable.xcstrings from the strings the compiler found in SwiftUI views.
# Run after ./build.sh build whenever you add or change user-facing text.
set -eu
cd "$(dirname "$0")"
args=()
for file in build/Build/Intermediates.noindex/AIUsageMenu.build/Release/AIUsageMenu.build/Objects-normal/arm64/*.stringsdata; do
  args+=(--stringsdata "$file")
done
xcrun xcstringstool sync Resources/Localizable.xcstrings "${args[@]}"
echo "Localizable.xcstrings: $(python3 -I -c "import json;print(len(json.load(open('Resources/Localizable.xcstrings'))['strings']))") strings"

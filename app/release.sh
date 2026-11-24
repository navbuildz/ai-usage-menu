#!/bin/bash
# Builds, signs, notarizes and packages a release, writes the Sparkle update feed, and (with
# --publish) creates the GitHub release that every installed copy picks up within a day.
#
#   ./release.sh 1.1.0 notes.md                 build and package into build/release/1.1.0
#   ./release.sh 1.1.0 notes.md --publish       also create the GitHub release (needs GITHUB_REPO)
#   ./release.sh 1.1.0 notes.md --local-feed http://127.0.0.1:8765/   test feed, no notarization
#
# notes.md is a plain list, one "- " line per change, in user-facing words. Those lines become the
# bullets in the update window, the appcast and the in-app "What's new".
set -euo pipefail
cd "$(dirname "$0")"

version="${1:?usage: release.sh <version> <notes.md> [--publish | --local-feed <url>]}"
notes="${2:?usage: release.sh <version> <notes.md> [--publish | --local-feed <url>]}"
mode="${3:-}"
feed_prefix="${4:-}"
repo="${GITHUB_REPO:-}"
team="U5HKKL4525"
app="build/Build/Products/Release/AI Usage Menu.app"
out="build/release/$version"
bin="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
grep -q '^- ' "$notes" || { echo "$notes needs at least one '- ' line" >&2; exit 1; }
if grep -q $'\xe2\x80\x94' "$notes"; then echo "No em dashes in release notes" >&2; exit 1; fi
if [ "$mode" = "--publish" ] && [ -z "$repo" ]; then echo "Set GITHUB_REPO=owner/name to publish" >&2; exit 1; fi
free_gb=$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')
[ "$free_gb" -ge 3 ] || { echo "Only ${free_gb} GB free; need at least 3" >&2; exit 1; }

# 1. Version, build number and bundled release notes.
build_number=$(( $(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | head -1 | awk '{print $2}') + 1 ))
sed -i '' -E "s/(MARKETING_VERSION: ).*/\1$version/; s/(CURRENT_PROJECT_VERSION: ).*/\1$build_number/" project.yml
python3 -I - "$version" "$notes" <<'PY'
import json, sys
version, notes = sys.argv[1], sys.argv[2]
bullets = [line[2:].strip() for line in open(notes, encoding="utf-8") if line.startswith("- ")]
path = "Resources/ReleaseNotes.json"
data = json.load(open(path, encoding="utf-8"))
data[version] = bullets
json.dump(dict(sorted(data.items(), key=lambda kv: [int(x) for x in kv[0].split(".")], reverse=True)), open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY
xcodegen generate >/dev/null

# 2. Test, build both architectures, sign as BaseThread LLC.
./build.sh test >/dev/null
./build.sh build >/dev/null
./build.sh sign >/dev/null
[ "$(defaults read "$PWD/$app/Contents/Info" CFBundleShortVersionString)" = "$version" ] || { echo "Built app is not $version" >&2; exit 1; }

# 3. Notarize and staple (skipped for a local test feed).
mkdir -p "$out"
zip="$out/AIUsageMenu-$version.zip"
if [ "$mode" != "--local-feed" ]; then
  source ~/.zshrc >/dev/null 2>&1 || true
  : "${APPLE_ID:?APPLE_ID not set (notarization)}" "${APPLE_PASSWORD:?APPLE_PASSWORD not set (notarization)}"
  ditto -c -k --keepParent "$app" "$out/notarize.zip"
  xcrun notarytool submit "$out/notarize.zip" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$team" --wait
  xcrun stapler staple "$app"
  rm "$out/notarize.zip"
  spctl --assess --type execute "$app" || { echo "Gatekeeper rejects the build" >&2; exit 1; }
fi
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# 4. Release notes page and the signed appcast (key from the Keychain, account ai.aiusagemenu.app).
python3 -I - "$notes" "$out/AIUsageMenu-$version.html" <<'PY'
import html, sys
bullets = [line[2:].strip() for line in open(sys.argv[1], encoding="utf-8") if line.startswith("- ")]
open(sys.argv[2], "w", encoding="utf-8").write("<ul>\n" + "".join(f"  <li>{html.escape(b)}</li>\n" for b in bullets) + "</ul>\n")
PY
if [ "$mode" = "--local-feed" ]; then
  prefix="${feed_prefix:?--local-feed needs a URL}"
else
  prefix="https://github.com/$repo/releases/download/v$version/"
fi
"$bin/generate_appcast" --account ai.aiusagemenu.app --embed-release-notes --download-url-prefix "$prefix" "$out" >/dev/null
grep -q "sparkle:edSignature" "$out/appcast.xml" || { echo "Appcast is not signed" >&2; exit 1; }
echo "Packaged $version (build $build_number) in $out"

# 5. Publish: a GitHub release holding the app and the feed. aiusagemenu.com/appcast.xml forwards to
#    https://github.com/$repo/releases/latest/download/appcast.xml, so every copy finds it.
if [ "$mode" = "--publish" ]; then
  gh release create "v$version" "$zip" "$out/appcast.xml" --repo "$repo" --title "AI Usage Menu $version" --notes-file "$notes"
  echo "Published v$version to https://github.com/$repo/releases/tag/v$version"
fi

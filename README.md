# AI Usage Menu

AI Usage Menu is a free macOS menu bar app for tracking Claude Code and Codex plan limits. Phase 1 provides the native menu bar gauge and a Quit command. Usage readings and reset times arrive with the data layer and window in Phases 2 and 3.

## Build from source

Use Xcode with Swift 6 on a Mac. The deployment target is macOS 13. From the repository root, run:

```sh
./app/build.sh
./app/build.sh test
open "app/build/Build/Products/Release/AI Usage Menu.app"
```

The release script builds for Intel and Apple silicon. Tests run on the host architecture. The shared Xcode project builds directly. If changing targets or build settings, edit `app/project.yml` and run `cd app && xcodegen generate` to update the project. The development team is empty and the build script disables Xcode signing. Apple’s linker embeds an ad hoc signature on Apple silicon. Distribution signing and notarization belong to the release process.

## Privacy

The scaffold displays a bundled template image. It reads no provider data, runs no child processes and makes no network requests.

The planned Claude provider will invoke the signed-in Claude Code CLI, which may contact Anthropic. The planned Codex provider will read rate-limit events from local session logs. The app will never read credentials, cookies, browser profiles or Keychain items. Local paths in usage breakdowns belong on screen only.

Claude Code can create a project entry even for a read with session persistence disabled. Every invocation will use the same empty working directory at `~/Library/Application Support/AI Usage Menu/claude-workdir/` to keep that side effect to one project location. The planned updater will require opt-in for automatic checks.

## Adding a provider

Phase 2 introduces the Provider protocol. A new provider will supply its identity, display name, original glyph, availability check and asynchronous snapshot reader, with fixtures for each supported response and failure state. Use data already available from a signed-in local tool. Preserve unknown values and report the time of each reading.

## Phase 1 verification, November 22, 2026

The Release build contains arm64 and x86_64 slices. Three hosted XCTest cases passed on Apple silicon for accessory-app metadata, the compiled template image and light/dark canvas colors. Intel runtime testing and menu bar appearance checks across displays remain open. All 112 extracted brand files matched the supplied archive byte for byte.

Claude Code 2.1.330 emitted a SessionStart hook event during a baseline /usage read. With the fixed empty workdir, adding `--setting-sources project,local` eliminated observed hook events and preserved plan limits. The broader `--safe-mode` also worked. The test observed lifecycle events through verbose stream JSON with `--include-hook-events`. A separate read using the provider's regular JSON format and the narrower setting returned plan limits, zero turns and zero reported cost. Use the narrower setting in Phase 2. The probe kept usage text in memory.

[From the makers of TypeFire](https://typefire.app)

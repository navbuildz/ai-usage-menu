# AI Usage Menu

AI Usage Menu is a free macOS menu bar app for tracking Claude Code and Codex plan limits. Choose which provider and usage window to track in the menu bar. Click the gauge to check reset times and scroll through Claude Code’s contribution breakdown. The Dock opens the same view in a draggable window without a title bar. Close it with × or Cmd+W and tracking continues.

## Build from source

Use Xcode with Swift 6 on a Mac. The deployment target is macOS 13. From the repository root, run:

```sh
./app/build.sh
./app/build.sh test
open "app/build/Build/Products/Release/AI Usage Menu.app"
```

To include the signed-in local providers in the hosted test run, use:

```sh
TEST_RUNNER_AI_USAGE_MENU_LIVE=1 ./app/build.sh test
```

The release script builds for Intel and Apple silicon. Tests run on the host architecture. The shared Xcode project builds directly. If changing targets or build settings, edit `app/project.yml` and run `cd app && xcodegen generate` to update the project. The development team is empty and the build script disables Xcode signing. Apple’s linker embeds an ad hoc signature on Apple silicon. Distribution signing and notarization belong to the release process.

## Privacy

The Claude provider invokes the signed-in Claude Code CLI, which may contact Anthropic. The Codex provider reads the newest rollout under `$CODEX_HOME/sessions` (default `~/.codex/sessions`) from the end of the file. The app keeps snapshots in memory. It reads no credentials, cookies, browser profiles or Keychain items and does not log usage text.

Claude Code can create a project entry even for a read with session persistence disabled. Every usage read uses the same empty working directory at `~/Library/Application Support/AI Usage Menu/claude-workdir/` to keep that side effect to one project location. The planned updater will require opt-in for automatic checks.

## Adding a provider

Implement the `Provider` protocol and include the type in the `UsageStore` provider list. Supply its identity, display name, original glyph, availability check and asynchronous snapshot reader, with fixtures for each supported response and failure state. Use data already available from a signed-in local tool. Preserve unknown values and report the time of each reading.

## Display settings

Open Settings with the gear or Cmd+comma. Choose Menu bar and Dock, Menu bar only or Dock only. The choice takes effect immediately. The combined menu bar gauge lights one mint bar, two amber bars or three danger bars. One item per provider uses the kit’s individual provider glyphs. The optional number follows the same reading.

Menu bar and Dock preferences are independent. Each offers Auto or an explicit provider when multiple tools are available. Both default to the 5-hour number. In the Dock, the upper arc shows the 5-hour window and the lower arc shows overall weekly usage. The center selector changes only the number. Auto keeps both arcs on the provider with the highest current overall weekly or 5-hour reading. The menu bar’s Auto compares just its selected window. Claude’s model-specific limits remain visible in its usage cards.

The menu bar and Dock previews show the current display choices. Dock appearance has its own System, Light and Dark setting. The live ring centers the selected number without a percent sign. The first usage window after launch opens in the center of the active display. Closing and reopening restores its position until quit.

Select System, Light or Dark in the header or Settings. System follows macOS and is the default. Scheduled refresh defaults to five minutes. Settings also offers 2, 10, 15 and 30 minutes. Manual, wake and Codex file-change refreshes work independently.

## Phase 3 verification, November 22, 2026

The hosted tests exercise all three placement settings live, the regular and accessory activation policies, status item counts, the Dock window and access to Settings. The selection tests cover an individual provider, a single enabled provider, both providers on Auto, and session and weekly filtering. The display settings persist across launches.

The [Dock snapshots](handoff/screenshots/dock) cover 14 cases at 32, 128 and 1024 pixels, including custom thresholds and stale readings. The [window captures](handoff/screenshots/window) use the built views and fixture data in both appearances. The renderer also runs at 64 and 512 pixels. To deliberately regenerate reference captures, run `TEST_RUNNER_RECORD_DOCK=1 TEST_RUNNER_RECORD_PANEL=1 ./app/build.sh test`.

Desktop checks on this Mac included the real provider tabs and a titled usage window with the Dock on the right, left and bottom, including bottom placement with auto-hide and magnification enabled. The original Dock configuration was restored. Individual Dock hover frames, Cmd-Tab artwork, the absence of a one-frame launch flash and notched-display overflow still need visual verification. Login-item startup requires Phase 4. The Release build targets Apple silicon and Intel. Tests ran on Apple silicon.

## Phase 2 verification, November 22, 2026

All 14 hosted tests passed with live reads enabled. Claude Code returned three windows and Codex returned two. An earlier live Codex check returned no windows. Both follow-up runs succeeded. The reader uses only the newest rollout and clears unavailable readings.

The 50 MiB tail fixture took 0.34 ms in the final run on this Mac. The FSEvents test picked up an appended rate-limit record in about one second. Fixture tests cover year rollover, daylight-saving gaps and repeated hours, partial Claude output, stale Codex windows, malformed records, command timeouts and refresh coalescing. The source scan passed. Runtime network and write measurements belong to hardening.

The store uses Combine observation for macOS 13 compatibility. The Release build contains both Intel and Apple silicon slices. Dock rendering, settings, screenshots and manual Dock behavior checks belong to subsequent phases.

## Phase 1 verification, November 22, 2026

The Release build contains arm64 and x86_64 slices. Three hosted XCTest cases passed on Apple silicon for accessory-app metadata, the compiled template image and light/dark canvas colors. Intel runtime testing and menu bar appearance checks across displays remain open. All 112 extracted brand files matched the supplied archive byte for byte.

Claude Code 2.1.330 emitted a SessionStart hook event during a baseline /usage read. With the fixed empty workdir, adding `--setting-sources project,local` eliminated observed hook events and preserved plan limits. The broader `--safe-mode` also worked. The test observed lifecycle events through verbose stream JSON with `--include-hook-events`. A separate read using the provider's regular JSON format and the narrower setting returned plan limits, zero turns and zero reported cost. The app uses the narrower setting. The probe kept usage text in memory.

[From the makers of TypeFire](https://typefire.app)

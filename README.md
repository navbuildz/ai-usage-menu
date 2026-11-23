# AI Usage Menu: a free, open-source Claude and Codex usage tracker for the Mac menu bar and Dock. No cookie, no API key.

AI Usage Menu is a free macOS menu bar app for tracking Claude Code and Codex plan limits. Choose which provider and usage window to track in the menu bar. Click the gauge to check reset times and scroll through Claude Code’s contribution breakdown. The Dock opens the same view in a draggable window without a title bar. Close it with × or Cmd+W and tracking continues.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="handoff/screenshots/window/hero-dark.png">
  <img src="handoff/screenshots/window/hero-light.png" width="390" alt="AI Usage Menu showing Claude Code session and weekly limits, reset times, and contributing activity">
</picture>

Visit [aiusagemenu.com](https://aiusagemenu.com) for the tracker, usage guide and downloads. The app reads local usage output, shows contributing activity and displays session and weekly limits in the Dock. The MIT license permits inspecting and building the Swift source. The public DMG and Homebrew cask are pending release.

## Key facts

- **Product** A Mac menu bar and Dock app for tracking Claude Code and Codex usage.
- **Platforms** macOS 13 or later on Intel and Apple silicon.
- **Plans** Claude Pro, Max and Team, and ChatGPT plans for Codex. API-key accounts have no plan limits to show.
- **Data sources** Claude Code’s /usage output and Codex’s local session logs.
- **Network calls** None for usage readings. The app contacts its update service only when you enable update checks. Claude Code itself may contact Anthropic.
- **Price** Free.
- **License** MIT.
- **Maker** TypeFire.

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

### Disk limits for this Mac

Use the single derived-data directory at `app/build`. Before a build, test or measurement that could write over 500 MB, run `df -h /System/Volumes/Data` and stop if less than 15 GB is free. Use text-only profiling with `ps`, `lsof`, `nettop` and metadata snapshots. Instruments recordings can allocate gigabytes in system temporary storage. Keep phase reports small, remove obsolete build copies and list generated items over 100 MB in each phase report.

## Privacy

The Claude provider invokes the signed-in Claude Code CLI, which may contact Anthropic. The Codex provider reads the newest rollout under `$CODEX_HOME/sessions` (default `~/.codex/sessions`) from the end of the file. The app keeps snapshots in memory. It reads no credentials, cookies, browser profiles or Keychain items and does not log usage text.

Claude Code can create a project entry even for a read with session persistence disabled. Every usage read uses the same empty working directory at `~/Library/Application Support/AI Usage Menu/claude-workdir/` to keep that side effect to one project location. Sparkle starts when you enable automatic checks or select Check for Updates. Automatic checks default to off.

## Adding a provider

Implement the `Provider` protocol and include the type in the `UsageStore` provider list. Supply its identity, display name, original glyph, availability check and asynchronous snapshot reader, with fixtures for each supported response and failure state. Use data already available from a signed-in local tool. Preserve unknown values and report the time of each reading.

## Display settings

Open Settings with the gear or Cmd+comma. Use the independent menu bar and Dock switches in General or in each display pane. Both start on. If both are hidden, open the app from Finder to return to Settings. The choice takes effect immediately. The combined menu bar gauge lights one mint bar, two amber bars or three danger bars. One item per provider uses the kit’s individual provider glyphs. The optional number follows the same reading.

Menu bar and Dock preferences are independent. Each offers Auto or an explicit provider when multiple tools are available. Both default to the 5-hour number. In the Dock, the upper arc shows the 5-hour window and the lower arc shows overall weekly usage. The center selector changes only the number. Auto keeps both arcs on the provider with the highest current overall weekly or 5-hour reading. The menu bar’s Auto compares just its selected window. Claude’s model-specific limits remain visible in its usage cards.

The menu bar and Dock previews show the current display choices. Dock appearance has its own System, Light and Dark setting. The live ring centers the selected number without a percent sign. The first usage window after launch opens in the center of the active display. Closing and reopening restores its position until quit.

Select System, Light or Dark in the header or Settings. System follows macOS and is the default. Scheduled refresh defaults to five minutes. Settings also offers 2, 10, 15 and 30 minutes. Manual, wake and Codex file-change refreshes work independently.

## Phase 6 brand verification and captures, November 23, 2026

The [capture set](handoff/screenshots/window) contains a dark and light hero from the app-hosted main window. The four feature pairs for the site are `breakdown`, `settings-menu`, `settings-dock`, and `onboarding`. The images use real app views with repeatable fixture readings. The [six social cards](handoff/social) cover each planned guide and comparison in 1200 × 630 pixels using Inter, the kit lockup and the brandHero gradient.

The Xcode icon set matches the kit. Xcode's default standalone icon lacked the 1024 px rendition. Building all standalone renditions restored it, and the compiled 1024 px pixels match the kit exactly. The [system icon samples](handoff/screenshots/icon) show the rebuilt bundle through NSWorkspace at 16, 32, 128 and 1024 px, plus the three usage tiers against both menu bar appearances. Spotlight's bundle-ID search returned the Release app. The Finder and Spotlight interfaces were not visually inspected. Settings shows the application icon in the sidebar and the kit mark in About. The menu template, brand mark, provider glyphs and copied kit UI SVGs were checked against their source artwork.

All 25 hosted tests passed with real provider integration enabled. The unsigned universal Release build succeeded. No new item over 100 MB was created. Retained build directories over 100 MB (decimal, nested) are `app/build` (594 MB), `ModuleCache.noindex` (331 MB), `Build` (110 MB) and `SourcePackages` (103 MB). The Debug app copy and temporary icon and font working files were removed. Free space was 17 GiB after cleanup.

## Phase 5 hardening, November 23, 2026

All 24 hosted tests passed, including live Claude Code and Codex reads. The unsigned universal Release build succeeded. The usage window recenters when its previous display disappears. Finder reopens Settings in menu-bar-only mode, including when status items crowd the notch. Usage cards support a single column at accessibility text sizes and announce stale resets. Selected tabs have stronger contrast. The refresh control uses the system progress indicator during reads.

Text-only measurements used the existing running Release process (PID 58406), which predates the final UI rebuild. Through three scheduled refreshes, 83 regular lsof samples and a follow-up found no internet sockets for the app, and nettop reported no connection rows. Across ten minutes, 21 ps samples rounded to 0.0% CPU with resident memory from 29.88 to 31.36 MiB. See [network samples](handoff/phase5-network.txt) and [performance samples](handoff/phase5-performance.txt).

The [metadata diff](handoff/phase5-writes.txt) covers the readable portions of all five requested roots. It found 132 changed entries on this active Mac, with none under the app's support directory or at its preferences plist. Each scan encountered 697 access or traversal errors. The diff cannot attribute changes to a process or capture transient writes. Source review identified the instance lock, Claude working directory and app preferences as intentional app writes. The runtime no-write claim remains unproven. The diff contains local paths and is intended for internal handoff.

Tests exercised the wake notification, synthetic multiple-display geometry and Settings recovery with 12 temporary menu bar items on a Mac with a 33-point top safe inset. Physical sleep/wake, a live second-display disconnect and spoken VoiceOver output remain manual checks.

Disk inventory uses decimal MB and includes nested paths. The single retained `app/build` directory is 592 MB, including `ModuleCache.noindex` (331 MB), `Build` (108 MB) and `SourcePackages` (103 MB). The test-host Debug app copy was removed. TF ENG previously removed the 8.5 GB and 1.5 GB temporary kernel traces and both Instruments output bundles. The repeat measurements produced three text files totaling about 31 KB. No individual build file exceeds 100 MB.

## Phase 4 verification, November 22, 2026

First launch walks through privacy, detected providers and optional services. Open **Settings > Startup & alerts** to change launch at login, local notifications, or automatic update checks. Threshold alerts default to 75% and 90% when enabled. Reset alerts are optional. In General, browse for the Claude executable or test its usage read.

All 21 hosted tests passed on Apple silicon with live provider reads enabled. The alert-cycle test covers repeat reads, separate providers, expiry and a fresh cycle. The Release executable contains arm64 and x86_64 slices and embeds Sparkle 2.10.1. The onboarding and Settings captures are in `handoff/screenshots/window/`.

With automatic updates off, 62 lsof samples at ten-second intervals over 610 seconds found zero internet sockets for the running Phase 4 Release app. A nettop snapshot also showed no app connections. The Claude CLI ran as a separate child during scheduled refreshes.

The update feed and source repository URL are placeholders. A production update requires the hosted appcast and release key. A real logout/login and OS notification delivery are pending manual checks.

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

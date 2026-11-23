# Security

## Reporting a security issue

Report suspected vulnerabilities privately through GitHub's "Report a vulnerability" form on this repository. Please don't open a public issue for them. Include the app version, your macOS version, what an attacker could do, and the code path involved. Leave out session logs, credentials and account files.

## What the app can touch

AI Usage Menu is a small app, and you can check everything below in the source.

- **It runs one program:** your own `claude` binary, with `-p /usage`, from its own folder in `~/Library/Application Support/AI Usage Menu/claude-workdir`. Claude Code then contacts Anthropic the same way it does when you type `/usage`. The app passes `DISABLE_AUTOUPDATER=1` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` so Claude Code skips its update check and telemetry during the read.
- **It reads two things:** the end of the newest Codex session log in `~/.codex/sessions`, and the `auth_mode` field of `~/.codex/auth.json`. No other field of that file is decoded.
- **It writes nothing outside its own preferences** and that working folder.
- **It makes no network requests,** except Sparkle update checks, which are off until you turn them on. `ProviderTests.testNoNetworkCodeOutsideUpdater` fails the build if networking code appears anywhere outside `Sources/Updater`.

## Why the app is not sandboxed

A sandboxed app can't start your `claude` binary or read `~/.codex`, and those are the two places the readings come from. The app uses the hardened runtime with no extra entitlements. Keep it that way: a change that adds an entitlement needs a security review in its pull request.

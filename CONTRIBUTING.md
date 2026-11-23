# Contributing to AI Usage Menu

Thanks for helping. This app's promise is that anyone can read the code that touches their data, so readable code matters as much as working code.

## Build and test

```sh
./app/build.sh          # universal Release build, unsigned
./app/build.sh test     # the full test suite
```

You need Xcode with Swift 6 and macOS 13 or later. Run the tests before you open a pull request.

## Ground rules

1. Local data only. No network calls outside `Sources/Updater` (a test enforces this), no cookies, no API keys, no telemetry.
2. One statement per line and descriptive names. Add a short doc comment to anything that reads user data or starts a process.
3. Every behavior change comes with a test that does the action and checks the result.
4. Fixtures are real output with personal details removed: replace your home folder with `~` and remove emails, project names and account ids.
5. American English in all user-facing text.

## When a provider changes its output

Claude Code and Codex change their output from time to time. If the app says a provider "changed its usage output", use **Copy details** in the app (home paths and emails are removed) and open an issue with the "Provider output changed" template. A fix usually means adding the new output as a fixture, updating the parser and adding a test.

## Adding a provider

1. Create `app/Sources/<Name>Provider.swift` that conforms to `Provider` (`Sources/Provider.swift`). Start the file with a comment listing exactly what it reads, what it runs, what it writes (it should be nothing) and what it sends (it should be nothing).
2. Keep parsing in a separate pure function or enum, like `ClaudeParser` and `CodexParser`, so it can be tested without the provider.
3. Map the provider's states to `ProviderState`. Use `.nonSubscription` only when the provider positively says the account has no plan limits, and use `.unknownFormat` for anything you don't recognize.
4. Add fixtures under `app/Tests/Fixtures/` for a normal reading, signed out, no plan, an error, and a reading whose window has already reset.
5. Register the provider in `UsageStore.init` and add its glyph to `Assets.xcassets`.

## Pull requests

Describe what changed, why, and how you verified it. Include before and after screenshots for any visual change, in both light and dark.

# Contributing

Thanks for being here. This repository is where the FeedbackThread Swift SDK is
developed — issues and pull requests are read, and merged pull requests land
here directly.

> **Changed August 2026.** This repository used to be a read-only mirror,
> published by force-pushing from a private monorepo, which quietly meant a
> pull request could never be merged. That is no longer the case. The SDK lives
> here now.

## Requirements

- Swift 6.0
- iOS 16+ / macOS 13+
- Xcode with an iOS simulator runtime installed

No dependencies, and none will be accepted — the package is deliberately a small
async/await client over `URLSession` plus SwiftUI views.

## Running the tests

```sh
swift test
```

**One thing that will catch you out.** `swift test` runs on macOS, and every view
in this package is behind `#if os(iOS)`. A macOS test pass compiles none of the
UI. A broken preview fixture once shipped this way. So also run:

```sh
SDKPATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
swift build -Xswiftc -sdk -Xswiftc "$SDKPATH" \
  -Xswiftc -target -Xswiftc arm64-apple-ios16.0-simulator
```

CI runs both on every pull request, always from a clean checkout, so you will
find out either way — but locally this is the one that catches UI breakage.

## Adding a language

Translations are the easiest contribution here and very welcome.

Everything user-facing lives in one file:
`Sources/FeedbackThread/Resources/Localizable.xcstrings`. Add your locale to the
catalog and open a pull request — no Swift changes are needed, and none should
be. Each entry carries a translator comment explaining where the string appears.

The tests will hold you to it: `LocalizationCatalogTests` fails on any key left
untranslated, on a translation whose format specifiers drift from the English,
and on a malformed plural. `LocalizedResolutionTests` pins a locale and asserts
strings actually resolve from the package bundle, so a translation that is
present but unreachable fails loudly rather than silently falling back to
English.

## One invariant worth knowing

**Server status values are not display strings, even where they read
identically.** `feedbackThreadRequestStage` matches the wire values the API
sends — `"Submitted"`, `"In review"`, `"In progress"`, `"Ready to release"`. The
labels a user sees are separate and translated. Several collide textually, so
these must never be changed by find-and-replace. Changing a wire string breaks
status mapping silently and at runtime only.

The same goes for enum raw values, `CodingKey`s, URL paths, headers, and the
persisted voter-identity key.

`FeedbackThreadError.invalidConfiguration` stays English on purpose — it
addresses the developer integrating the SDK, not their users.

## Pull requests

- Branch from `main`, keep the change focused.
- Explain the reasoning in the description, not just the what. If you made a
  judgement call, say which way and why.
- New behaviour comes with a test.
- Public API changes need a note in `CHANGELOG.md` under `## Unreleased`.

Releases and version tags are cut by the maintainer; you do not need to bump a
version in your pull request.

## Reporting a bug

Open an issue with the SDK version, iOS version, and the smallest reproduction
you can manage. If it involves a request board, whether the card was public or
still in triage is usually the detail that matters.

## Licence

MIT. By contributing you agree your work ships under it.

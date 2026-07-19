# Changelog

All notable changes to the FeedbackThread Swift SDK are documented here.

## 0.2.0

### Breaking

- **FeedbackThread-first rename.** The `Loopline`-prefixed types (`LooplineClient`, `LooplineConfiguration`, `LooplineFeedbackSubmission`, `LooplineFeatureRequest`, `LooplineCustomerTier`, `LooplineFeedbackKind`, `LooplineRequestTarget`, `LooplineFeatureRequestList`, `LooplineFeedbackForm`, and friends) are no longer the primary API. `FeedbackThread`-prefixed types are now the real declarations; the `Loopline`-prefixed names are deprecated typealiases kept for source compatibility. They will be removed in **0.3.0** — see the Migration section below.
- **`FeedbackThreadConfiguration.init` now throws.** The base URL's scheme is validated at configuration time: only `http` and `https` are accepted. An invalid scheme throws `FeedbackThreadError.invalidConfiguration("The FeedbackThread base URL must use HTTP or HTTPS.")` instead of failing later at request time. This mirrors the Android SDK's base URL validation.

### Added

- `FeedbackThreadFeedbackKind` gained a `.review` case (serialized as `"Reviews"`), matching Android's `REVIEW` case and the server-side feedback kind.
- `FeedbackThreadConfiguration` gained a `requestTimeout: TimeInterval` field (default `30`), applied to every outgoing `URLRequest.timeoutInterval`. This mirrors Android's `connectTimeoutMillis` / `readTimeoutMillis` configuration.

### Changed

- The anonymous voter ID persisted by `FeedbackThreadFeatureRequestList` now lives under the `com.feedbackthread.sdk.voter-id` `UserDefaults` key. On first read under the new key, the view migrates forward from the legacy `com.loopline.sdk.voter-id` key if present, so existing installs keep their voting identity.
- Internal-only symbols (the private HTTP transport and its payload/envelope types) were also renamed from `Loopline*` to `FeedbackThread*`. These were never public API.

### Compatibility

- The separate `Loopline` product/target (Swift Package Manager "compatibility" library) still exists and still resolves. It now works by `@_exported import`-ing the `FeedbackThread` module, which itself declares the deprecated `Loopline*` typealiases — so `import Loopline` continues to expose both the new and the deprecated names without a second layer of duplicate aliasing.
- Existing `Package.resolved` pins against the `Loopline` product are unaffected: the product and target names were intentionally left as `Loopline`.

## 0.1.0

- Initial private-alpha Swift SDK: async client, SwiftUI feature-request list and feedback form, customer tier support, shipped-in-version badges.

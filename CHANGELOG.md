# Changelog

## 0.2.1

Initial public release.

- `FeedbackThreadClient` — async/await client for submissions, the moderated request feed, and voting, with idempotent retries, configurable timeouts, and base-URL validation.
- `FeedbackThreadFeatureRequestList` — SwiftUI feature-request board with voting, status filters, detail views, and **Shipped in x.y.z** badges on released requests.
- `FeedbackThreadFeedbackForm` — SwiftUI bug-report and feature-request form.
- `customerTier` — optional paying/free/custom signal on submissions and votes for revenue-aware prioritization.
- Anonymous voter identity stored on-device; no personal data collected.

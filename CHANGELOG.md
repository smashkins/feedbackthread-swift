# Changelog

## 0.3.0

Close the loop for end users, and harden the drop-in surfaces.

- **`FeedbackThreadMyRequestsList`** — new drop-in view showing the current user their own requests: pending ones under "Waiting for review", everything in progress, and shipped items with version badges. Auto-acknowledges shipped items and reports an unread count so the host app can badge its own menu.
- `myRequests()`, `myUpdates()`, `acknowledgeUpdates(ids:)` on `FeedbackThreadClient`.
- `customerTierProvider` on the feedback form and request board — the paying/free signal now works with the drop-in UI, read at submit/vote time.
- Retried submissions reuse their idempotency key until they succeed or the content changes, so an uncertain network failure can never create a duplicate.
- Unknown future statuses render instead of hiding requests from the board.
- Vote failures now surface an inline error in the board and detail views.
- Plain-HTTP base URLs are rejected unless the host is loopback.
- Boards arrive most-voted-first (server-side ordering change).

## 0.2.1

Initial public release.

- `FeedbackThreadClient` — async/await client for submissions, the moderated request feed, and voting, with idempotent retries, configurable timeouts, and base-URL validation.
- `FeedbackThreadFeatureRequestList` — SwiftUI feature-request board with voting, status filters, detail views, and **Shipped in x.y.z** badges on released requests.
- `FeedbackThreadFeedbackForm` — SwiftUI bug-report and feature-request form.
- `customerTier` — optional paying/free/custom signal on submissions and votes for revenue-aware prioritization.
- Anonymous voter identity stored on-device; no personal data collected.

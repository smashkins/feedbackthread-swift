# FeedbackThread Swift SDK

![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%C2%B7%20macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Native in-app feedback for iOS: a drop-in feature-request board with voting, a feedback form, and automatic **"Shipped in x.y.z"** badges — all wired to your [FeedbackThread](https://feedbackthread.com) dashboard, roadmap, and AI-agent workflow.

- 🗳️ **Feature-request board** — moderated public requests with voting, status filters, and full-text detail views
- ✍️ **Feedback form** — bug reports and feature requests straight into your triage inbox
- 🚀 **Close the loop** — requests attached to a published release automatically show a *Shipped in x.y.z* badge to the people who asked
- 💎 **Paying-customer signal** — optionally tag submissions and votes with your paywall state so you can prioritize by revenue
- 🔒 **Privacy-first** — no email or name is required; you control whether to pass an external user identifier; anonymous voter IDs stay on-device
- 🪶 **Zero dependencies** — a small async/await client over `URLSession`, SwiftUI views, nothing else

## Requirements

- iOS 16+ (SwiftUI views) · macOS 13+ (client only)
- Xcode 16 / Swift 6

## Installation

In Xcode: **File → Add Package Dependencies…** and enter

```text
https://github.com/aivars/feedbackthread-swift.git
```

Choose **Up to Next Major Version** from `0.3.0` and add the `FeedbackThread` product.

## Quick start

Grab your project key from the dashboard (**SDK setup**). It's a public, low-privilege identifier — safe to ship in your binary. It can submit feedback, read the moderated request feed, and vote; it cannot touch your private dashboard data.

```swift
import FeedbackThread

let feedbackThread = FeedbackThreadClient(
    configuration: try FeedbackThreadConfiguration(
        baseURL: URL(string: "https://api.feedbackthread.com")!,
        projectKey: "<your-project-key>",
        source: "ios"
    )
)
```

### Show the feature-request board

```swift
.sheet(isPresented: $showRequests) {
    FeedbackThreadFeatureRequestList(
        client: feedbackThread,
        appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown",
        externalUserID: signedInUserID   // optional; anonymous ID used otherwise
    )
}
```

Users see approved requests, filter by status (In review · Planned · In progress · Completed), vote with a single tap, and get a **Shipped in x.y.z** badge on anything you've released.

### Show the feedback form

```swift
.sheet(isPresented: $showFeedback) {
    FeedbackThreadFeedbackForm(
        client: feedbackThread,
        appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    )
}
```

Every submission carries an idempotency key, so a retried request never creates a duplicate.

### Tell FeedbackThread who pays

Pass the same signal you trust for your own paywall — it powers per-request "N paying customers want this" prioritization in the dashboard:

```swift
try await feedbackThread.submit(
    FeedbackThreadFeedbackSubmission(
        kind: .request,
        title: "iCloud sync",
        text: "Sync my data between iPhone and iPad.",
        customerTier: entitlements.isPro ? .paying : .free
    )
)
```

`customerTier` is `.free`, `.paying`, or `.custom("family")` — and omitted entirely when you don't pass it.

### Use the client directly

The SwiftUI views are optional. `FeedbackThreadClient` exposes `submit(_:)`, `requests(externalUserID:)`, and `setVote(for:voted:externalUserID:customerTier:)` if you're building your own UI. Requests time out after a configurable `requestTimeout` (default 30 s).

## How it fits together

The SDK is the in-app half of FeedbackThread: feedback lands in a keyboard-driven triage inbox, becomes cards on your roadmap, ships in tracked releases — and your AI agent can work the whole backlog over [MCP](https://feedbackthread.com). Learn more at [feedbackthread.com](https://feedbackthread.com).

## License

MIT — see [LICENSE](LICENSE).

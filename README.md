# FeedbackThread Swift SDK

This package provides the first app-side test integration for iOS 16+ and macOS 13+. It includes a small async client on both platforms plus a native feedback form and feature-request list on iOS. There is intentionally no Watch app UI.

## Add the package

GitHub plus Swift Package Manager is the standard low-friction distribution path for an iOS SDK. In Xcode, choose **File → Add Package Dependencies…** and enter:

```text
https://github.com/aivars/loopline.git
```

Select the `FeedbackThread` library product. During the closed beta, use the current beta branch or an exact beta tag supplied with the tester invitation. Once `0.1.0` exists, use **Up to Next Major Version** starting at `0.1.0`. Do not use an unbounded `main` dependency in a released app.

For local development, choose **File → Add Package Dependencies… → Add Local…**, select this repository root, and select the `FeedbackThread` product. The deprecated `Loopline` product remains temporarily available for source compatibility.

The repository is not tagged or published by this document change; creating the first beta tag is a separate release action.

### Migrating from the `Loopline`-prefixed API (0.1.x → 0.2.0)

As of 0.2.0, `FeedbackThread`-prefixed types (`FeedbackThreadClient`, `FeedbackThreadConfiguration`, `FeedbackThreadFeedbackSubmission`, `FeedbackThreadFeatureRequest`, and so on) are the real API. The previous `Loopline`-prefixed names (`LooplineClient`, `LooplineConfiguration`, …) still compile — they are now `@available(*, deprecated, renamed:)` typealiases pointing at the `FeedbackThread` types — but Xcode will flag every use with a deprecation warning, and **they are removed in 0.3.0**. Existing integrators (Apnea, FocusLock) should rename to the `FeedbackThread`-prefixed types before then; a simple find-and-replace of `Loopline` → `FeedbackThread` handles nearly every call site. The `Loopline` compatibility product/target itself keeps its name, so an existing `Package.resolved` pin against it does not need to be re-pinned.

## Configure the client

```swift
import FeedbackThread

let feedbackThread = FeedbackThreadClient(
    configuration: try FeedbackThreadConfiguration(
        baseURL: URL(string: "https://api.feedbackthread.com")!,
        projectKey: "your-project-key",
        source: "ios"
    )
)
```

Copy the project key from **SDK setup** in the signed-in dashboard. Treat it as a public project identifier: any value shipped in an app can be extracted. It can submit feedback, read the moderated public request feed, and vote. It cannot read the private workspace, call MCP, access store credentials, or perform developer mutations.

Create one shared client near your app root and inject it into the settings or support flow that presents FeedbackThread UI. Do not create a new client for every render.

`FeedbackThreadConfiguration.init` throws: it validates that `baseURL` uses the `http` or `https` scheme, matching the Android SDK's base URL validation. It also accepts an optional `requestTimeout: TimeInterval` (default `30`), applied to every outgoing request, mirroring Android's connect/read timeouts.

## Present the feature-request list

```swift
FeedbackThreadFeatureRequestList(
    client: feedbackThread,
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
    externalUserID: signedInUserID,
    onDismiss: { isShowingRequests = false }
)
```

The list is moderated: Submitted and Rejected requests stay in the developer dashboard. App users can filter approved requests by In review, Planned, In progress, and Completed. New requests appear only after approval.

The list automatically requests the iOS audience. It includes iOS requests and Apple Watch-specific requests; only Watch-specific rows receive an **Apple Watch** label. If the app has no account ID, the view stores a random anonymous voter ID locally.

Requests whose status is Completed and whose release has been published show a **Shipped in `<version>`** badge next to the status pill, using the `shippedInVersion` value from the request feed.

### Statuses

The dashboard and API renamed two request statuses: `Open` is now `Submitted`, and `Under review` is now `In review`. The SDK's models and public request feed already use the new labels; the feature-request list still tolerates the old `Under review` label when filtering, in case cached data has not refreshed yet.

### Customer tier

`FeedbackThreadFeedbackSubmission` and `FeedbackThreadClient.setVote(for:voted:externalUserID:customerTier:)` both accept an optional `customerTier`:

```swift
FeedbackThreadFeedbackSubmission(
    kind: .request,
    title: "Add dark mode",
    text: "Would love a dark theme.",
    customerTier: .paying
)
```

`FeedbackThreadCustomerTier` is `.free`, `.paying`, or `.custom("<label>")` for plans that don't fit that binary. The convention: pass the same signal you trust for your own paywall. FeedbackThread uses it to help prioritize feedback and votes from paying customers. The field is omitted from the request body entirely when left `nil`, so existing integrations are unaffected.

## Present the feedback form

```swift
import FeedbackThread
import SwiftUI

struct SettingsView: View {
    @State private var isShowingFeedback = false

    var body: some View {
        Button("Send feedback") {
            isShowingFeedback = true
        }
        .sheet(isPresented: $isShowingFeedback) {
            FeedbackThreadFeedbackForm(
                client: feedbackThread,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        }
    }
}
```

The SDK sends a unique `Idempotency-Key` with every submission so a retried request does not create duplicate feedback.

The SDK form accepts feature requests and bug reports. It does not ask users to write store reviews: FeedbackThread will import written reviews from App Store Connect and Google Play so the developer can reply, close them, or promote useful feedback into the product workflow.

Tapping a public request opens its complete description and keeps voting available from the detail screen. Public comments are not part of the current SDK/API contract; the WishKit CSV export also did not contain historical comments, so FeedbackThread does not invent or display them.

## Verify the integration

1. Run the app and open the feature-request list. Only developer-moderated iOS and Apple Watch requests should appear.
2. Submit a test feature request or bug report.
3. Sign in at `https://app.feedbackthread.com` and confirm that the item appears in the correct project inbox.
4. Retry the same queued submission and confirm that the idempotency key prevents a duplicate.

If the project is on the free plan after five collected items, collection still succeeds but the new content stays locked in the dashboard, API, exports, and MCP until the project is upgraded.

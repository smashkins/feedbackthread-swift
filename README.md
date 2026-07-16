# Loopline Swift SDK

This package provides the first app-side test integration for iOS 16+ and macOS 13+. It includes a small async client on both platforms plus a native feedback form and feature-request list on iOS. There is intentionally no Watch app UI.

## Add the package

For local private-alpha testing, add `/Users/aivarsmeijers/Developer/Loopline` as a local package in Xcode and select the `Loopline` product. The package manifest lives at the repository root, so the GitHub URL can be used after this branch is merged or tagged.

## Configure the client

```swift
import Loopline

let loopline = LooplineClient(
    configuration: LooplineConfiguration(
        baseURL: URL(string: "https://loopline-staging.aivars-meijers.workers.dev")!,
        projectKey: "your-project-key",
        source: "ios"
    )
)
```

Treat the project key as an app credential, not an administrator credential. It can submit feedback, read the moderated public request feed, and vote. It cannot read the private workspace or perform developer mutations.

## Present the feature-request list

```swift
LooplineFeatureRequestList(
    client: loopline,
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
    externalUserID: signedInUserID,
    onDismiss: { isShowingRequests = false }
)
```

The list is moderated: Open and Rejected requests stay in the developer dashboard. App users can filter approved requests by In review, Planned, In progress, and Completed. Submitted requests appear only after approval.

The list automatically requests the iOS audience. It includes iOS requests and Apple Watch-specific requests; only Watch-specific rows receive an **Apple Watch** label. If the app has no account ID, the view stores a random anonymous voter ID locally.

## Present the feedback form

```swift
import Loopline
import SwiftUI

struct SettingsView: View {
    @State private var isShowingFeedback = false

    var body: some View {
        Button("Send feedback") {
            isShowingFeedback = true
        }
        .sheet(isPresented: $isShowingFeedback) {
            LooplineFeedbackForm(
                client: loopline,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        }
    }
}
```

The SDK sends a unique `Idempotency-Key` with every submission so a retried request does not create duplicate feedback.

The SDK form accepts feature requests and bug reports. It does not ask users to write store reviews: Loopline will import written reviews from App Store Connect and Google Play so the developer can reply, close them, or promote useful feedback into the product workflow.

Tapping a public request opens its complete description and keeps voting available from the detail screen. Public comments are not part of the current SDK/API contract; the WishKit CSV export also did not contain historical comments, so Loopline does not invent or display them.

import Foundation

/// The host app's marketing version and build number, read from the main
/// bundle — the value the drop-in feedback form attaches to submissions by
/// default so integrators never have to plumb it through themselves.
public enum FeedbackThreadAppVersion {
    /// e.g. `"2.4.1 (317)"`, or `"unknown"` outside a normal app bundle.
    public static var current: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case (let v?, let b?): return "\(v) (\(b))"
        case (let v?, nil): return v
        default: return "unknown"
        }
    }
}

/// Resolves the stable identity used to tie a submission, vote, or "My
/// requests" lookup to a single person: a developer-supplied external user
/// ID when present, otherwise the SDK's own on-device anonymous ID —
/// generating and persisting one on first use so every SDK surface (the
/// request board, the standalone feedback form, and My Requests) converges
/// on the same identity without requiring the host app to manage one
/// itself.
///
/// This lives outside the `#if os(iOS)`-gated view files so the resolution
/// logic is testable on any platform, and so it is a single source of truth
/// - the views themselves only read/write the persisted value for SwiftUI
/// reactivity (`@AppStorage`), never re-implement the fallback logic.
public enum FeedbackThreadIdentity {
    /// The UserDefaults key used to persist the generated anonymous ID.
    /// This is the exact key `FeedbackThreadFeatureRequestList` and
    /// `FeedbackThreadMyRequestsList` read via `@AppStorage`, so all three
    /// surfaces stay in sync.
    static let voterIDDefaultsKey = "com.feedbackthread.sdk.voter-id"

    /// Resolves the identity to submit/vote/query with: `externalUserID`
    /// trimmed, if non-empty; otherwise the persisted anonymous voter ID,
    /// generating and persisting a new UUID on first use.
    ///
    /// Public so host apps can use the same identity outside the drop-in
    /// views — e.g. calling `myUpdates(externalUserID:)` at launch to badge
    /// a menu item before the user ever opens My Requests.
    public static func resolve(
        externalUserID: String? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        let provided = externalUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !provided.isEmpty { return provided }

        if let stored = defaults.string(forKey: voterIDDefaultsKey), !stored.isEmpty {
            return stored
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: voterIDDefaultsKey)
        return generated
    }
}

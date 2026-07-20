import Foundation

/// Tracks the idempotency key used by a resubmittable form (feedback, bug, or
/// review) so a retry after a failed submission reuses the same key instead
/// of minting a new one — which would let the server see it as a distinct
/// submission and create a duplicate.
///
/// A new key is only generated for the first attempt, after a successful
/// submission, or after the user materially edits the content being
/// submitted.
struct FeedbackThreadResubmissionKey: Sendable, Equatable {
    private var key: String?

    /// Returns the key to use for the next submission attempt, generating and
    /// caching one if none is currently pending.
    mutating func beginAttempt(generator: () -> String = { UUID().uuidString }) -> String {
        if let key { return key }
        let generated = generator()
        key = generated
        return generated
    }

    /// Call once a submission succeeds so the next attempt starts a fresh key.
    mutating func submissionSucceeded() {
        key = nil
    }

    /// Call when the user materially edits the content being submitted so a
    /// later retry doesn't reuse a key that was minted for different content.
    mutating func contentChanged() {
        key = nil
    }
}

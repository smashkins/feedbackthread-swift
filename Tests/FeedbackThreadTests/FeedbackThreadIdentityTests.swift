import Foundation
import Testing
@testable import FeedbackThread

@Suite("FeedbackThreadIdentity")
struct FeedbackThreadIdentityTests {
    /// A fresh, isolated UserDefaults suite per test so tests can't leak
    /// persisted state into each other or into the real `.standard` store.
    private func freshDefaults() -> UserDefaults {
        let suiteName = "FeedbackThreadIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Returns the provided external ID, trimmed, without touching storage")
    func returnsProvidedID() {
        let defaults = freshDefaults()
        let resolved = FeedbackThreadIdentity.resolve(externalUserID: "  user-42  ", defaults: defaults)
        #expect(resolved == "user-42")
        #expect(defaults.string(forKey: FeedbackThreadIdentity.voterIDDefaultsKey) == nil)
    }

    @Test("Generates and persists a UUID once when no external ID is provided")
    func generatesAndPersistsOnce() {
        let defaults = freshDefaults()

        let first = FeedbackThreadIdentity.resolve(externalUserID: nil, defaults: defaults)
        #expect(!first.isEmpty)
        #expect(defaults.string(forKey: FeedbackThreadIdentity.voterIDDefaultsKey) == first)

        // A second resolution - whether the external ID is nil or blank -
        // reuses the persisted value instead of generating a new one.
        let second = FeedbackThreadIdentity.resolve(externalUserID: nil, defaults: defaults)
        let third = FeedbackThreadIdentity.resolve(externalUserID: "   ", defaults: defaults)
        #expect(second == first)
        #expect(third == first)
    }
}

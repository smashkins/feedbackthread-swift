import Testing
@testable import FeedbackThread

@Suite("FeedbackThreadResubmissionKey")
struct FeedbackThreadResubmissionKeyTests {
    @Test("Reuses the same key across retries of a failed attempt")
    func reusesKeyOnRetryAfterFailure() {
        var generatedCount = 0
        var key = FeedbackThreadResubmissionKey()

        let firstAttempt = key.beginAttempt {
            generatedCount += 1
            return "key-\(generatedCount)"
        }
        // Simulate a network failure: no success/edit call happens before retrying.
        let retryAttempt = key.beginAttempt {
            generatedCount += 1
            return "key-\(generatedCount)"
        }

        #expect(firstAttempt == retryAttempt)
        #expect(generatedCount == 1)
    }

    @Test("Generates a new key after a successful submission")
    func generatesNewKeyAfterSuccess() {
        var generatedCount = 0
        var key = FeedbackThreadResubmissionKey()
        let generator: () -> String = {
            generatedCount += 1
            return "key-\(generatedCount)"
        }

        let firstAttempt = key.beginAttempt(generator: generator)
        key.submissionSucceeded()
        let nextAttempt = key.beginAttempt(generator: generator)

        #expect(firstAttempt != nextAttempt)
        #expect(generatedCount == 2)
    }

    @Test("Generates a new key after the user edits the content")
    func generatesNewKeyAfterContentChanged() {
        var generatedCount = 0
        var key = FeedbackThreadResubmissionKey()
        let generator: () -> String = {
            generatedCount += 1
            return "key-\(generatedCount)"
        }

        let firstAttempt = key.beginAttempt(generator: generator)
        key.contentChanged()
        let nextAttempt = key.beginAttempt(generator: generator)

        #expect(firstAttempt != nextAttempt)
        #expect(generatedCount == 2)
    }

    @Test("Generates a new key when the feedback kind (Request/Bug/Review) changes")
    func generatesNewKeyWhenFeedbackKindChanges() {
        // FeedbackThreadFeedbackForm wires its type Picker's onChange to
        // contentChanged() - documented here so a switch from, say, Request
        // to Bug after a failed submit can't reuse a key minted for a
        // materially different payload.
        var generatedCount = 0
        var key = FeedbackThreadResubmissionKey()
        let generator: () -> String = {
            generatedCount += 1
            return "key-\(generatedCount)"
        }

        let firstAttempt = key.beginAttempt(generator: generator)
        // Simulates the user switching the Picker selection after a failed attempt.
        key.contentChanged()
        let nextAttempt = key.beginAttempt(generator: generator)

        #expect(firstAttempt != nextAttempt)
        #expect(generatedCount == 2)
    }
}

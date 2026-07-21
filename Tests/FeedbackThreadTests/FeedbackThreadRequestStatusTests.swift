import Testing
@testable import FeedbackThread

@Suite("FeedbackThreadRequestStatus")
struct FeedbackThreadRequestStatusTests {
    @Test(
        "Maps known status strings to their public board stage",
        arguments: [
            ("Submitted", FeedbackThreadRequestStage.pendingReview),
            ("Under review", .inReview),
            ("In review", .inReview),
            ("Planned", .planned),
            ("In progress", .inProgress),
            ("Ready to release", .inProgress),
            ("Released", .completed),
            ("Rejected", .rejected),
        ]
    )
    func mapsKnownStatuses(status: String, stage: FeedbackThreadRequestStage) {
        #expect(status.feedbackThreadRequestStage == stage)
    }

    @Test("Labels a Rejected status plainly")
    func labelsRejected() {
        #expect("Rejected".feedbackThreadRequestLabel == "Rejected")
    }

    @Test("Labels a Submitted status honestly, without implying moderation happened")
    func labelsPendingReview() {
        #expect("Submitted".feedbackThreadRequestLabel == "Waiting for review")
    }

    @Test("Preserves a fabricated, unrecognized status rather than dropping it")
    func preservesUnknownStatus() {
        let status = "archived"
        #expect(status.feedbackThreadRequestStage == .unknown("archived"))
        #expect(status.feedbackThreadRequestLabel == "Archived")
    }

    @Test("Sensibly capitalizes an unrecognized status with separators")
    func capitalizesUnknownStatusWithSeparators() {
        #expect("on_hold".feedbackThreadRequestLabel == "On Hold")
        #expect("NEEDS-TRIAGE".feedbackThreadRequestLabel == "Needs Triage")
    }

    @Test(
        "Buckets every possible stage into exactly one My Requests section",
        arguments: [
            (FeedbackThreadRequestStage.pendingReview, FeedbackThreadMyRequestsSection.waitingForReview),
            (.inReview, .inProgress),
            (.planned, .inProgress),
            (.inProgress, .inProgress),
            (.completed, .shipped),
            (.rejected, .closed),
            (.unknown("archived"), .inProgress),
        ]
    )
    func bucketsEveryStage(stage: FeedbackThreadRequestStage, section: FeedbackThreadMyRequestsSection) {
        #expect(stage.feedbackThreadMyRequestsSection == section)
    }
}

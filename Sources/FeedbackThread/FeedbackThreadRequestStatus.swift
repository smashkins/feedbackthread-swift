import Foundation

/// The canonical stages of the public feature-request board.
///
/// Statuses the SDK doesn't recognize are preserved as ``unknown(_:)`` rather
/// than dropped, so a status added on the server later doesn't silently hide
/// cards from a board built against an older SDK.
enum FeedbackThreadRequestStage: Equatable, Sendable {
    case inReview
    case planned
    case inProgress
    case completed
    case unknown(String)
}

extension String {
    /// Maps a raw feature-request status string to its public board stage.
    var feedbackThreadRequestStage: FeedbackThreadRequestStage {
        switch self {
        case "Under review", "In review": .inReview
        case "Planned": .planned
        case "In progress", "Ready to release": .inProgress
        case "Released": .completed
        default: .unknown(self)
        }
    }

    /// A user-facing label for the status: the known stage's display name, or
    /// the raw status sensibly capitalized when the stage isn't recognized.
    var feedbackThreadRequestLabel: String {
        switch feedbackThreadRequestStage {
        case .inReview: "In review"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .unknown: sensiblyCapitalized
        }
    }

    /// Capitalizes each word of a raw status string, e.g. "on_hold" -> "On Hold".
    var sensiblyCapitalized: String {
        let words = replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
        guard !words.isEmpty else { return self }
        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

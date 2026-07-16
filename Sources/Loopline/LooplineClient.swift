import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LooplineFeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug = "Bugs"
    case request = "Requests"
    case review = "Reviews"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .bug: "Bug"
        case .request: "Request"
        case .review: "Review"
        }
    }
}

public struct LooplineFeedbackSubmission: Encodable, Equatable, Sendable {
    public var kind: LooplineFeedbackKind
    public var title: String
    public var text: String
    public var appVersion: String?
    public var externalUserID: String?

    public init(
        kind: LooplineFeedbackKind,
        title: String,
        text: String,
        appVersion: String? = nil,
        externalUserID: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.appVersion = appVersion
        self.externalUserID = externalUserID
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case text
        case appVersion
        case externalUserID = "externalUserId"
    }
}

public struct LooplineFeedback: Decodable, Equatable, Sendable {
    public let id: String
    public let kind: LooplineFeedbackKind
    public let source: String
    public let title: String
    public let excerpt: String
    public let version: String
    public let status: String
    public let count: Int
    public let note: String
    public let responseDraft: String
    public let responseState: String
    public let createdAt: String
    public let updatedAt: String
}

public struct LooplineConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var projectKey: String
    public var source: String

    public init(baseURL: URL, projectKey: String, source: String) {
        self.baseURL = baseURL
        self.projectKey = projectKey
        self.source = source
    }
}

public enum LooplineError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidResponse
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidResponse: "Loopline returned an unreadable response."
        case .server(_, let message): message
        }
    }
}

public struct LooplineClient: Sendable {
    public typealias SubmissionHandler = @Sendable (
        _ submission: LooplineFeedbackSubmission,
        _ idempotencyKey: String
    ) async throws -> LooplineFeedback

    private let submissionHandler: SubmissionHandler

    public init(
        configuration: LooplineConfiguration,
        session: URLSession = .shared
    ) {
        let transport = LooplineHTTPTransport(configuration: configuration, session: session)
        submissionHandler = { submission, idempotencyKey in
            try await transport.submit(submission, idempotencyKey: idempotencyKey)
        }
    }

    public init(submit: @escaping SubmissionHandler) {
        submissionHandler = submit
    }

    @discardableResult
    public func submit(
        _ submission: LooplineFeedbackSubmission,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> LooplineFeedback {
        try await submissionHandler(submission, idempotencyKey)
    }
}

private final class LooplineHTTPTransport: @unchecked Sendable {
    private let configuration: LooplineConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: LooplineConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func submit(
        _ submission: LooplineFeedbackSubmission,
        idempotencyKey: String
    ) async throws -> LooplineFeedback {
        let projectKey = configuration.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = configuration.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else {
            throw LooplineError.invalidConfiguration("A Loopline project key is required.")
        }
        guard !source.isEmpty else {
            throw LooplineError.invalidConfiguration("A Loopline source is required.")
        }

        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("projects")
            .appendingPathComponent(projectKey)
            .appendingPathComponent("feedback")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(LooplineIngestionPayload(submission: submission, source: source))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LooplineError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? decoder.decode(LooplineErrorEnvelope.self, from: data)
            throw LooplineError.server(
                statusCode: httpResponse.statusCode,
                message: error?.error.message ?? "Loopline returned HTTP \(httpResponse.statusCode)."
            )
        }

        guard let envelope = try? decoder.decode(LooplineFeedbackEnvelope.self, from: data) else {
            throw LooplineError.invalidResponse
        }
        return envelope.feedback
    }
}

private struct LooplineIngestionPayload: Encodable {
    let kind: LooplineFeedbackKind
    let source: String
    let title: String
    let text: String
    let appVersion: String?
    let externalUserID: String?

    init(submission: LooplineFeedbackSubmission, source: String) {
        kind = submission.kind
        self.source = source
        title = submission.title
        text = submission.text
        appVersion = submission.appVersion
        externalUserID = submission.externalUserID
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case source
        case title
        case text
        case appVersion
        case externalUserID = "externalUserId"
    }
}

private struct LooplineFeedbackEnvelope: Decodable {
    let feedback: LooplineFeedback
}

private struct LooplineErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

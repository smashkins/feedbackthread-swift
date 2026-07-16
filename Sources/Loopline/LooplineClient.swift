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

public enum LooplineRequestTarget: String, Codable, Sendable {
    case ios
    case android
    case watchOS = "watchos"

    public var title: String? {
        switch self {
        case .watchOS: "Apple Watch"
        case .ios, .android: nil
        }
    }
}

public struct LooplineFeatureRequest: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let votes: Int
    public let target: LooplineRequestTarget
    public let status: String
    public let voted: Bool
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
    public typealias RequestListHandler = @Sendable (_ externalUserID: String?) async throws -> [LooplineFeatureRequest]
    public typealias VoteHandler = @Sendable (
        _ requestID: String,
        _ voted: Bool,
        _ externalUserID: String
    ) async throws -> LooplineVoteResult

    private let submissionHandler: SubmissionHandler
    private let requestListHandler: RequestListHandler
    private let voteHandler: VoteHandler

    public init(
        configuration: LooplineConfiguration,
        session: URLSession = .shared
    ) {
        let transport = LooplineHTTPTransport(configuration: configuration, session: session)
        submissionHandler = { submission, idempotencyKey in
            try await transport.submit(submission, idempotencyKey: idempotencyKey)
        }
        requestListHandler = { externalUserID in
            try await transport.requests(externalUserID: externalUserID)
        }
        voteHandler = { requestID, voted, externalUserID in
            try await transport.setVote(for: requestID, voted: voted, externalUserID: externalUserID)
        }
    }

    public init(submit: @escaping SubmissionHandler) {
        submissionHandler = submit
        requestListHandler = { _ in [] }
        voteHandler = { _, _, _ in
            throw LooplineError.invalidConfiguration("This Loopline client does not support voting.")
        }
    }

    public init(
        submit: @escaping SubmissionHandler,
        requests: @escaping RequestListHandler,
        setVote: @escaping VoteHandler
    ) {
        submissionHandler = submit
        requestListHandler = requests
        voteHandler = setVote
    }

    @discardableResult
    public func submit(
        _ submission: LooplineFeedbackSubmission,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> LooplineFeedback {
        try await submissionHandler(submission, idempotencyKey)
    }

    public func requests(externalUserID: String? = nil) async throws -> [LooplineFeatureRequest] {
        try await requestListHandler(externalUserID)
    }

    @discardableResult
    public func setVote(
        for requestID: String,
        voted: Bool,
        externalUserID: String
    ) async throws -> LooplineVoteResult {
        try await voteHandler(requestID, voted, externalUserID)
    }
}

public struct LooplineVoteResult: Decodable, Equatable, Sendable {
    public let feedbackId: String
    public let votes: Int
    public let voted: Bool
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

    func requests(externalUserID: String?) async throws -> [LooplineFeatureRequest] {
        var components = URLComponents(
            url: try projectEndpoint().appendingPathComponent("requests"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "platform", value: "ios")]
        guard let endpoint = components?.url else {
            throw LooplineError.invalidConfiguration("The Loopline base URL is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let externalUserID = normalizedUserID(externalUserID) {
            request.setValue(externalUserID, forHTTPHeaderField: "X-Loopline-User")
        }

        let data = try await responseData(for: request)
        guard let envelope = try? decoder.decode(LooplineRequestsEnvelope.self, from: data) else {
            throw LooplineError.invalidResponse
        }
        return envelope.requests
    }

    func setVote(
        for requestID: String,
        voted: Bool,
        externalUserID: String
    ) async throws -> LooplineVoteResult {
        guard let userID = normalizedUserID(externalUserID) else {
            throw LooplineError.invalidConfiguration("A stable user ID is required for voting.")
        }
        var components = URLComponents(
            url: try projectEndpoint()
                .appendingPathComponent("requests")
                .appendingPathComponent(requestID)
                .appendingPathComponent("vote"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "platform", value: "ios")]
        guard let endpoint = components?.url else {
            throw LooplineError.invalidConfiguration("The Loopline base URL is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = voted ? "POST" : "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userID, forHTTPHeaderField: "X-Loopline-User")

        let data = try await responseData(for: request)
        guard let result = try? decoder.decode(LooplineVoteResult.self, from: data) else {
            throw LooplineError.invalidResponse
        }
        return result
    }

    private func projectEndpoint() throws -> URL {
        let projectKey = configuration.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else {
            throw LooplineError.invalidConfiguration("A Loopline project key is required.")
        }
        return configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("projects")
            .appendingPathComponent(projectKey)
    }

    private func normalizedUserID(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private func responseData(for request: URLRequest) async throws -> Data {
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
        return data
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

private struct LooplineRequestsEnvelope: Decodable {
    let requests: [LooplineFeatureRequest]
}

private struct LooplineErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

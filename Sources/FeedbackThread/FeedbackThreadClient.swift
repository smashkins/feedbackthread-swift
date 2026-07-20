import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FeedbackThreadFeedbackKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case request = "Requests"
    case bug = "Bugs"
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

/// A customer's plan tier, used to prioritize feedback and votes.
///
/// Pass the same signal you trust for your own paywall — whatever your app already
/// uses to distinguish free users from paying customers.
public enum FeedbackThreadCustomerTier: Sendable, Equatable {
    case free
    case paying
    case custom(String)

    public var rawValue: String {
        switch self {
        case .free: "free"
        case .paying: "paying"
        case .custom(let value): value
        }
    }
}

extension FeedbackThreadCustomerTier: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct FeedbackThreadFeedbackSubmission: Encodable, Equatable, Sendable {
    public var kind: FeedbackThreadFeedbackKind
    public var title: String
    public var text: String
    public var appVersion: String?
    public var externalUserID: String?
    public var customerTier: FeedbackThreadCustomerTier?

    public init(
        kind: FeedbackThreadFeedbackKind,
        title: String,
        text: String,
        appVersion: String? = nil,
        externalUserID: String? = nil,
        customerTier: FeedbackThreadCustomerTier? = nil
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.appVersion = appVersion
        self.externalUserID = externalUserID
        self.customerTier = customerTier
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case text
        case appVersion
        case externalUserID = "externalUserId"
        case customerTier
    }
}

public struct FeedbackThreadFeedback: Decodable, Equatable, Sendable {
    public let id: String
    public let kind: FeedbackThreadFeedbackKind
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

public enum FeedbackThreadRequestTarget: String, Codable, Sendable {
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

public struct FeedbackThreadFeatureRequest: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let votes: Int
    public let target: FeedbackThreadRequestTarget
    public let status: String
    public let voted: Bool
    public let updatedAt: String
    public let shippedInVersion: String?
}

public struct FeedbackThreadConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var projectKey: String
    public var source: String
    public var requestTimeout: TimeInterval

    /// Hosts that are trusted to be reached over plain HTTP (local development only).
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    public init(
        baseURL: URL,
        projectKey: String,
        source: String,
        requestTimeout: TimeInterval = 30
    ) throws {
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw FeedbackThreadError.invalidConfiguration("The FeedbackThread base URL must use HTTP or HTTPS.")
        }
        if scheme == "http" {
            let host = baseURL.host?.lowercased() ?? ""
            guard Self.loopbackHosts.contains(host) else {
                throw FeedbackThreadError.invalidConfiguration(
                    "The FeedbackThread base URL must use HTTPS unless it points at localhost."
                )
            }
        }
        self.baseURL = baseURL
        self.projectKey = projectKey
        self.source = source
        self.requestTimeout = requestTimeout
    }
}

public enum FeedbackThreadError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidResponse
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidResponse: "FeedbackThread returned an unreadable response."
        case .server(_, let message): message
        }
    }
}

public struct FeedbackThreadClient: Sendable {
    public typealias SubmissionHandler = @Sendable (
        _ submission: FeedbackThreadFeedbackSubmission,
        _ idempotencyKey: String
    ) async throws -> FeedbackThreadFeedback
    public typealias RequestListHandler = @Sendable (_ externalUserID: String?) async throws -> [FeedbackThreadFeatureRequest]
    public typealias VoteHandler = @Sendable (
        _ requestID: String,
        _ voted: Bool,
        _ externalUserID: String,
        _ customerTier: FeedbackThreadCustomerTier?
    ) async throws -> FeedbackThreadVoteResult

    private let submissionHandler: SubmissionHandler
    private let requestListHandler: RequestListHandler
    private let voteHandler: VoteHandler

    public init(
        configuration: FeedbackThreadConfiguration,
        session: URLSession = .shared
    ) {
        let transport = FeedbackThreadHTTPTransport(configuration: configuration, session: session)
        submissionHandler = { submission, idempotencyKey in
            try await transport.submit(submission, idempotencyKey: idempotencyKey)
        }
        requestListHandler = { externalUserID in
            try await transport.requests(externalUserID: externalUserID)
        }
        voteHandler = { requestID, voted, externalUserID, customerTier in
            try await transport.setVote(
                for: requestID,
                voted: voted,
                externalUserID: externalUserID,
                customerTier: customerTier
            )
        }
    }

    public init(submit: @escaping SubmissionHandler) {
        submissionHandler = submit
        requestListHandler = { _ in [] }
        voteHandler = { _, _, _, _ in
            throw FeedbackThreadError.invalidConfiguration("This FeedbackThread client does not support voting.")
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
        _ submission: FeedbackThreadFeedbackSubmission,
        idempotencyKey: String = UUID().uuidString
    ) async throws -> FeedbackThreadFeedback {
        try await submissionHandler(submission, idempotencyKey)
    }

    public func requests(externalUserID: String? = nil) async throws -> [FeedbackThreadFeatureRequest] {
        try await requestListHandler(externalUserID)
    }

    @discardableResult
    public func setVote(
        for requestID: String,
        voted: Bool,
        externalUserID: String,
        customerTier: FeedbackThreadCustomerTier? = nil
    ) async throws -> FeedbackThreadVoteResult {
        try await voteHandler(requestID, voted, externalUserID, customerTier)
    }
}

public struct FeedbackThreadVoteResult: Decodable, Equatable, Sendable {
    public let feedbackId: String
    public let votes: Int
    public let voted: Bool
}

private final class FeedbackThreadHTTPTransport: @unchecked Sendable {
    private let configuration: FeedbackThreadConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: FeedbackThreadConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func submit(
        _ submission: FeedbackThreadFeedbackSubmission,
        idempotencyKey: String
    ) async throws -> FeedbackThreadFeedback {
        let projectKey = configuration.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = configuration.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else {
            throw FeedbackThreadError.invalidConfiguration("A FeedbackThread project key is required.")
        }
        guard !source.isEmpty else {
            throw FeedbackThreadError.invalidConfiguration("A FeedbackThread source is required.")
        }

        let endpoint = configuration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("projects")
            .appendingPathComponent(projectKey)
            .appendingPathComponent("feedback")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(FeedbackThreadIngestionPayload(submission: submission, source: source))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackThreadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? decoder.decode(FeedbackThreadErrorEnvelope.self, from: data)
            throw FeedbackThreadError.server(
                statusCode: httpResponse.statusCode,
                message: error?.error.message ?? "FeedbackThread returned HTTP \(httpResponse.statusCode)."
            )
        }

        guard let envelope = try? decoder.decode(FeedbackThreadFeedbackEnvelope.self, from: data) else {
            throw FeedbackThreadError.invalidResponse
        }
        return envelope.feedback
    }

    func requests(externalUserID: String?) async throws -> [FeedbackThreadFeatureRequest] {
        var components = URLComponents(
            url: try projectEndpoint().appendingPathComponent("requests"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "platform", value: "ios")]
        guard let endpoint = components?.url else {
            throw FeedbackThreadError.invalidConfiguration("The FeedbackThread base URL is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let externalUserID = normalizedUserID(externalUserID) {
            request.setValue(externalUserID, forHTTPHeaderField: "X-FeedbackThread-User")
        }

        let data = try await responseData(for: request)
        guard let envelope = try? decoder.decode(FeedbackThreadRequestsEnvelope.self, from: data) else {
            throw FeedbackThreadError.invalidResponse
        }
        return envelope.requests
    }

    func setVote(
        for requestID: String,
        voted: Bool,
        externalUserID: String,
        customerTier: FeedbackThreadCustomerTier? = nil
    ) async throws -> FeedbackThreadVoteResult {
        guard let userID = normalizedUserID(externalUserID) else {
            throw FeedbackThreadError.invalidConfiguration("A stable user ID is required for voting.")
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
            throw FeedbackThreadError.invalidConfiguration("The FeedbackThread base URL is invalid.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = voted ? "POST" : "DELETE"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userID, forHTTPHeaderField: "X-FeedbackThread-User")
        if let customerTier {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(FeedbackThreadVotePayload(customerTier: customerTier))
        }

        let data = try await responseData(for: request)
        guard let result = try? decoder.decode(FeedbackThreadVoteResult.self, from: data) else {
            throw FeedbackThreadError.invalidResponse
        }
        return result
    }

    private func projectEndpoint() throws -> URL {
        let projectKey = configuration.projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectKey.isEmpty else {
            throw FeedbackThreadError.invalidConfiguration("A FeedbackThread project key is required.")
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
            throw FeedbackThreadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? decoder.decode(FeedbackThreadErrorEnvelope.self, from: data)
            throw FeedbackThreadError.server(
                statusCode: httpResponse.statusCode,
                message: error?.error.message ?? "FeedbackThread returned HTTP \(httpResponse.statusCode)."
            )
        }
        return data
    }
}

private struct FeedbackThreadIngestionPayload: Encodable {
    let kind: FeedbackThreadFeedbackKind
    let source: String
    let title: String
    let text: String
    let appVersion: String?
    let externalUserID: String?
    let customerTier: FeedbackThreadCustomerTier?

    init(submission: FeedbackThreadFeedbackSubmission, source: String) {
        kind = submission.kind
        self.source = source
        title = submission.title
        text = submission.text
        appVersion = submission.appVersion
        externalUserID = submission.externalUserID
        customerTier = submission.customerTier
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case source
        case title
        case text
        case appVersion
        case externalUserID = "externalUserId"
        case customerTier
    }
}

private struct FeedbackThreadVotePayload: Encodable {
    let customerTier: FeedbackThreadCustomerTier
}

private struct FeedbackThreadFeedbackEnvelope: Decodable {
    let feedback: FeedbackThreadFeedback
}

private struct FeedbackThreadRequestsEnvelope: Decodable {
    let requests: [FeedbackThreadFeatureRequest]
}

private struct FeedbackThreadErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

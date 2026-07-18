import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import FeedbackThread

@Suite("FeedbackThreadClient", .serialized)
struct LooplineClientTests {
    @Test("Offers only feature requests and bug reports for SDK submission")
    func exposesAppFeedbackKinds() {
        #expect(FeedbackThreadFeedbackKind.allCases == [.request, .bug])
    }

    @Test("Submits the documented payload and idempotency key")
    func submitsFeedback() async throws {
        let recorder = RequestRecorder { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://example.com/v1/projects/project-key/feedback")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "stable-request-id")

            let body = try requestBody(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["kind"] == "Requests")
            #expect(json["source"] == "ios")
            #expect(json["title"] == "Schedule by weekday")
            #expect(json["text"] == "Please add weekday schedules.")
            #expect(json["appVersion"] == "1.2 (34)")
            #expect(json["externalUserId"] == "user-123")

            return try response(
                statusCode: 201,
                json: [
                    "feedback": sampleFeedback(),
                ]
            )
        }

        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        let feedback = try await client.submit(
            LooplineFeedbackSubmission(
                kind: .request,
                title: "Schedule by weekday",
                text: "Please add weekday schedules.",
                appVersion: "1.2 (34)",
                externalUserID: "user-123"
            ),
            idempotencyKey: "stable-request-id"
        )

        #expect(feedback.id == "FDBK-test")
        #expect(feedback.kind == .request)
        #expect(feedback.status == "Submitted")
    }

    @Test("Surfaces the server error message")
    func surfacesServerError() async throws {
        let recorder = RequestRecorder { _ in
            try response(
                statusCode: 404,
                json: [
                    "error": [
                        "code": "not_found",
                        "message": "Project was not found.",
                    ],
                ]
            )
        }

        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "wrong-key",
                source: "ios"
            ),
            session: recorder.session
        )

        do {
            _ = try await client.submit(
                LooplineFeedbackSubmission(kind: .bug, title: "Crash", text: "It crashed.")
            )
            Issue.record("Expected a server error")
        } catch let error as LooplineError {
            #expect(error == .server(statusCode: 404, message: "Project was not found."))
        }
    }

    @Test("Loads the iOS request feed and includes the voter identity")
    func loadsRequests() async throws {
        let recorder = RequestRecorder { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://example.com/v1/projects/project-key/requests?platform=ios")
            #expect(request.value(forHTTPHeaderField: "X-FeedbackThread-User") == "user-123")
            return try response(
                statusCode: 200,
                json: ["requests": [sampleRequest()]]
            )
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        let requests = try await client.requests(externalUserID: "user-123")
        let request = try #require(requests.first)
        #expect(request.id == "FDBK-request")
        #expect(request.target == .watchOS)
        #expect(request.status == "Planned")
        #expect(request.voted)
        #expect(request.shippedInVersion == nil)
    }

    @Test("Decodes shippedInVersion when the request feed reports a published release")
    func decodesShippedInVersion() async throws {
        let recorder = RequestRecorder { _ in
            try response(
                statusCode: 200,
                json: ["requests": [sampleRequest(shippedInVersion: "2.4.0")]]
            )
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        let requests = try await client.requests(externalUserID: "user-123")
        let request = try #require(requests.first)
        #expect(request.shippedInVersion == "2.4.0")
    }

    @Test("Decodes a null shippedInVersion as nil")
    func decodesNullShippedInVersion() async throws {
        let recorder = RequestRecorder { _ in
            try response(
                statusCode: 200,
                json: ["requests": [sampleRequest(shippedInVersion: NSNull())]]
            )
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        let requests = try await client.requests(externalUserID: "user-123")
        let request = try #require(requests.first)
        #expect(request.shippedInVersion == nil)
    }

    @Test("Encodes customerTier on submission when provided, omits it otherwise")
    func submissionEncodesCustomerTier() async throws {
        let recorder = RequestRecorder { request in
            let body = try requestBody(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["customerTier"] == "paying")
            return try response(statusCode: 201, json: ["feedback": sampleFeedback()])
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        _ = try await client.submit(
            LooplineFeedbackSubmission(
                kind: .bug,
                title: "Crash",
                text: "It crashed.",
                customerTier: .paying
            )
        )

        let omittingRecorder = RequestRecorder { request in
            let body = try requestBody(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["customerTier"] == nil)
            return try response(statusCode: 201, json: ["feedback": sampleFeedback()])
        }
        let omittingClient = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: omittingRecorder.session
        )

        _ = try await omittingClient.submit(
            LooplineFeedbackSubmission(kind: .bug, title: "Crash", text: "It crashed.")
        )
    }

    @Test("Encodes a custom customerTier by its raw label")
    func submissionEncodesCustomCustomerTier() async throws {
        let recorder = RequestRecorder { request in
            let body = try requestBody(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["customerTier"] == "enterprise")
            return try response(statusCode: 201, json: ["feedback": sampleFeedback()])
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        _ = try await client.submit(
            LooplineFeedbackSubmission(
                kind: .bug,
                title: "Crash",
                text: "It crashed.",
                customerTier: .custom("enterprise")
            )
        )
    }

    @Test("Carries customerTier in the vote body when provided")
    func voteEncodesCustomerTier() async throws {
        let recorder = RequestRecorder { request in
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try requestBody(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["customerTier"] == "free")
            return try response(
                statusCode: 200,
                json: [
                    "feedbackId": "FDBK-request",
                    "votes": 13,
                    "voted": true,
                ]
            )
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: recorder.session
        )

        _ = try await client.setVote(
            for: "FDBK-request",
            voted: true,
            externalUserID: "user-123",
            customerTier: .free
        )
    }

    @Test("Votes and removes votes using the iOS platform context")
    func changesVote() async throws {
        let voteRecorder = RequestRecorder { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://example.com/v1/projects/project-key/requests/FDBK-request/vote?platform=ios")
            #expect(request.value(forHTTPHeaderField: "X-FeedbackThread-User") == "user-123")
            return try response(
                statusCode: 200,
                json: [
                    "feedbackId": "FDBK-request",
                    "votes": 13,
                    "voted": true,
                ]
            )
        }
        let voteClient = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: voteRecorder.session
        )

        let voted = try await voteClient.setVote(
            for: "FDBK-request",
            voted: true,
            externalUserID: "user-123"
        )
        #expect(voted.voted)
        #expect(voted.votes == 13)

        let removeRecorder = RequestRecorder { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.absoluteString == "https://example.com/v1/projects/project-key/requests/FDBK-request/vote?platform=ios")
            return try response(
                statusCode: 200,
                json: [
                    "feedbackId": "FDBK-request",
                    "votes": 12,
                    "voted": false,
                ]
            )
        }
        let removeClient = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "project-key",
                source: "ios"
            ),
            session: removeRecorder.session
        )
        let removed = try await removeClient.setVote(
            for: "FDBK-request",
            voted: false,
            externalUserID: "user-123"
        )
        #expect(!removed.voted)
        #expect(removed.votes == 12)
    }

    @Test("Rejects an empty project key before sending")
    func rejectsEmptyProjectKey() async throws {
        let recorder = RequestRecorder { _ in
            Issue.record("A request should not be sent for an invalid configuration")
            return try response(statusCode: 500, json: [:])
        }
        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: URL(string: "https://example.com")!,
                projectKey: "  ",
                source: "ios"
            ),
            session: recorder.session
        )

        do {
            _ = try await client.submit(
                LooplineFeedbackSubmission(kind: .bug, title: "Crash", text: "It crashed.")
            )
            Issue.record("Expected an invalid configuration error")
        } catch let error as LooplineError {
            #expect(error == .invalidConfiguration("A FeedbackThread project key is required."))
        }
    }

    @Test("Submits through the live staging service when configured")
    func liveSubmission() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let baseURLString = environment["FEEDBACKTHREAD_LIVE_BASE_URL"] ?? environment["LOOPLINE_LIVE_BASE_URL"],
            let baseURL = URL(string: baseURLString),
            let projectKey = environment["FEEDBACKTHREAD_LIVE_PROJECT_KEY"] ?? environment["LOOPLINE_LIVE_PROJECT_KEY"]
        else {
            return
        }

        let client = LooplineClient(
            configuration: LooplineConfiguration(
                baseURL: baseURL,
                projectKey: projectKey,
                source: "ios"
            )
        )
        let idempotencyKey = "swift-live-\(UUID().uuidString)"
        let feedback = try await client.submit(
            LooplineFeedbackSubmission(
                kind: .bug,
                title: "Swift SDK live integration test",
                text: "Created by the Loopline Swift package integration test.",
                appVersion: "Loopline SDK alpha"
            ),
            idempotencyKey: idempotencyKey
        )

        #expect(feedback.source == "ios")
        #expect(feedback.title == "Swift SDK live integration test")
        #expect(feedback.status == "Submitted")

        let requests = try await client.requests(externalUserID: "swift-live-reader")
        #expect(!requests.isEmpty)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    let session: URLSession

    init(handler: @escaping Handler) {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: RequestRecorder.Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: LooplineError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func sampleFeedback() -> [String: Any] {
    [
        "id": "FDBK-test",
        "kind": "Requests",
        "source": "ios",
        "title": "Schedule by weekday",
        "excerpt": "Please add weekday schedules.",
        "version": "1.2 (34)",
        "status": "Submitted",
        "count": 1,
        "note": "",
        "responseDraft": "",
        "responseState": "Not started",
        "createdAt": "2026-07-16T12:00:00.000Z",
        "updatedAt": "2026-07-16T12:00:00.000Z",
    ]
}

private func sampleRequest(shippedInVersion: Any = NSNull()) -> [String: Any] {
    [
        "id": "FDBK-request",
        "title": "Training complications",
        "description": "Show the next practice on my watch face.",
        "votes": 12,
        "target": "watchos",
        "status": "Planned",
        "voted": true,
        "updatedAt": "2026-07-16T12:00:00.000Z",
        "shippedInVersion": shippedInVersion,
    ]
}

private func response(statusCode: Int, json: [String: Any]) throws -> (HTTPURLResponse, Data) {
    let url = URL(string: "https://example.com")!
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    ))
    return (response, try JSONSerialization.data(withJSONObject: json))
}

private func requestBody(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
        let bytesRead = stream.read(&buffer, maxLength: buffer.count)
        if bytesRead == 0 { break }
        if bytesRead < 0 {
            throw stream.streamError ?? LooplineError.invalidResponse
        }
        body.append(buffer, count: bytesRead)
    }
    return body
}

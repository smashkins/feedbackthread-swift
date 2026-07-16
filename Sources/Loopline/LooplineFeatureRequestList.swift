#if os(iOS) && canImport(SwiftUI)
import SwiftUI

private enum FeatureRequestRoute: Hashable {
    case detail(String)
}

public struct LooplineFeatureRequestList: View {
    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private enum ActiveSheet: String, Identifiable {
        case submit

        var id: String { rawValue }
    }

    private enum RequestFilter: String, CaseIterable, Identifiable {
        case all
        case inReview
        case planned
        case inProgress
        case completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .inReview: "In review"
            case .planned: "Planned"
            case .inProgress: "In progress"
            case .completed: "Completed"
            }
        }

        func includes(_ status: String) -> Bool {
            switch self {
            case .all: status.publicRequestStage != nil
            case .inReview: status.publicRequestStage == .inReview
            case .planned: status.publicRequestStage == .planned
            case .inProgress: status.publicRequestStage == .inProgress
            case .completed: status.publicRequestStage == .completed
            }
        }
    }

    private let client: LooplineClient
    private let appVersion: String?
    private let externalUserID: String?
    private let onDismiss: (() -> Void)?

    @AppStorage("com.loopline.sdk.voter-id") private var storedVoterID = ""
    @State private var requests: [LooplineFeatureRequest] = []
    @State private var loadState: LoadState = .loading
    @State private var votingIDs: Set<String> = []
    @State private var activeSheet: ActiveSheet?
    @State private var selectedFilter: RequestFilter = .all

    public init(
        client: LooplineClient,
        appVersion: String? = nil,
        externalUserID: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.client = client
        self.appVersion = appVersion
        self.externalUserID = externalUserID
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feature requests")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: FeatureRequestRoute.self, destination: requestDestination)
                .toolbar {
                    ToolbarTitleMenu {
                        ForEach(RequestFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Label(
                                    "\(filter.title) (\(requestCount(for: filter)))",
                                    systemImage: selectedFilter == filter ? "checkmark" : "circle"
                                )
                            }
                        }
                    }
                    if let onDismiss {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done", action: onDismiss)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            activeSheet = .submit
                        } label: {
                            Label("Add request", systemImage: "plus")
                        }
                    }
                }
        }
        .task {
            ensureVoterID()
            await load()
        }
        .sheet(item: $activeSheet) { _ in
            LooplineFeedbackForm(
                client: client,
                appVersion: appVersion,
                externalUserID: voterID,
                onSubmitted: { _ in
                    Task { await load() }
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading where requests.isEmpty:
            ProgressView("Loading requests…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where requests.isEmpty:
            FeatureRequestMessage(
                title: "Couldn’t load requests",
                message: message,
                systemImage: "wifi.exclamationmark",
                actionTitle: "Try again",
                action: { Task { await load() } }
            )
        default:
            List(filteredRequests) { request in
                FeatureRequestRow(
                    request: request,
                    isVoting: votingIDs.contains(request.id),
                    onVote: { toggleVote(request) }
                )
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .listStyle(.plain)
            .overlay {
                if filteredRequests.isEmpty {
                    FeatureRequestMessage(
                        title: requests.isEmpty ? "No feature requests yet" : "No \(selectedFilter.title.lowercased()) requests",
                        message: requests.isEmpty ? "Be the first to share an idea." : "Choose another status to see more requests.",
                        systemImage: requests.isEmpty ? "lightbulb" : "line.3.horizontal.decrease.circle"
                    )
                }
            }
            .refreshable { await load() }
        }
    }

    private var voterID: String {
        let provided = externalUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return provided.isEmpty ? storedVoterID : provided
    }

    private var filteredRequests: [LooplineFeatureRequest] {
        requests.filter { selectedFilter.includes($0.status) }
    }

    private func requestCount(for filter: RequestFilter) -> Int {
        requests.count { filter.includes($0.status) }
    }

    @ViewBuilder
    private func requestDestination(_ route: FeatureRequestRoute) -> some View {
        switch route {
        case .detail(let requestID):
            if let request = requests.first(where: { $0.id == requestID }) {
                FeatureRequestDetail(
                    request: request,
                    isVoting: votingIDs.contains(request.id),
                    onVote: { toggleVote(request) }
                )
            } else {
                FeatureRequestMessage(
                    title: "Request unavailable",
                    message: "This request is no longer available on the public board.",
                    systemImage: "rectangle.slash"
                )
            }
        }
    }

    private func ensureVoterID() {
        if voterID.isEmpty {
            storedVoterID = UUID().uuidString
        }
    }

    @MainActor
    private func load() async {
        if requests.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.requests(externalUserID: voterID)
            guard !Task.isCancelled else { return }
            requests = loaded
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func toggleVote(_ request: LooplineFeatureRequest) {
        guard !votingIDs.contains(request.id) else { return }
        votingIDs.insert(request.id)
        Task {
            defer { votingIDs.remove(request.id) }
            do {
                let result = try await client.setVote(
                    for: request.id,
                    voted: !request.voted,
                    externalUserID: voterID
                )
                guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
                let current = requests[index]
                requests[index] = LooplineFeatureRequest(
                    id: current.id,
                    title: current.title,
                    description: current.description,
                    votes: result.votes,
                    target: current.target,
                    status: current.status,
                    voted: result.voted,
                    updatedAt: current.updatedAt
                )
            } catch {
                loadState = .failed(error.localizedDescription)
            }
        }
    }
}

private struct FeatureRequestMessage: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureRequestRow: View {
    let request: LooplineFeatureRequest
    let isVoting: Bool
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeatureRequestVoteButton(
                votes: request.votes,
                isVoted: request.voted,
                isVoting: isVoting,
                action: onVote
            )

            NavigationLink(value: FeatureRequestRoute.detail(request.id)) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(request.title)
                            .font(.headline)
                        if request.target == .watchOS {
                            Text("Apple Watch")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(request.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    FeatureRequestStatusBadge(status: request.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}

private struct FeatureRequestDetail: View {
    let request: LooplineFeatureRequest
    let isVoting: Bool
    let onVote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(request.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    FeatureRequestVoteButton(
                        votes: request.votes,
                        isVoted: request.voted,
                        isVoting: isVoting,
                        action: onVote
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRequestStatusBadge(status: request.status)
                        if request.target == .watchOS {
                            Label("Apple Watch", systemImage: "applewatch")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Text(request.description)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatureRequestStatusBadge: View {
    let status: String

    var body: some View {
        Text(status.publicRequestLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status.publicRequestStage {
        case .inReview: .cyan
        case .planned: .purple
        case .inProgress: .blue
        case .completed: .green
        case nil: .secondary
        }
    }
}

private struct FeatureRequestVoteButton: View {
    let votes: Int
    let isVoted: Bool
    let isVoting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if isVoting {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: isVoted ? "arrow.up.circle.fill" : "arrow.up.circle")
                    }
                }
                .font(.title3.weight(.semibold))
                .frame(height: 24)

                Text("\(votes)")
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            .frame(minWidth: 52)
            .frame(minHeight: 60)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isVoted ? Color.accentColor : .secondary)
        .disabled(isVoting)
        .accessibilityLabel(isVoted ? "Remove vote" : "Vote")
        .accessibilityValue("\(votes) votes")
    }

    private var backgroundColor: Color {
        isVoted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
    }
}

private enum PublicRequestStage {
    case inReview
    case planned
    case inProgress
    case completed
}

private extension String {
    var publicRequestStage: PublicRequestStage? {
        switch self {
        case "Under review": .inReview
        case "Planned": .planned
        case "In progress", "Ready to release": .inProgress
        case "Released": .completed
        default: nil
        }
    }

    var publicRequestLabel: String {
        switch publicRequestStage {
        case .inReview: "In review"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case nil: self
        }
    }
}

private struct LooplineFeatureRequestListPreviews: PreviewProvider {
    static var previews: some View {
        LooplineFeatureRequestList(
            client: LooplineClient(
                submit: { submission, _ in
                    LooplineFeedback(
                        id: "FDBK-preview",
                        kind: submission.kind,
                        source: "ios",
                        title: submission.title,
                        excerpt: submission.text,
                        version: "Preview",
                        status: "Open",
                        count: 1,
                        note: "",
                        responseDraft: "",
                        responseState: "Not started",
                        createdAt: "2026-07-16T12:00:00.000Z",
                        updatedAt: "2026-07-16T12:00:00.000Z"
                    )
                },
                requests: { _ in previewRequests },
                setVote: { id, voted, _ in
                    LooplineVoteResult(feedbackId: id, votes: voted ? 35 : 34, voted: voted)
                }
            )
        )
    }

    nonisolated private static let previewRequests = [
        LooplineFeatureRequest(
            id: "FDBK-1",
            title: "Breathing reminders",
            description: "Remind me when it is time to practice.",
            votes: 34,
            target: .ios,
            status: "In progress",
            voted: true,
            updatedAt: "2026-07-16T12:00:00.000Z"
        ),
        LooplineFeatureRequest(
            id: "FDBK-2",
            title: "Training complications",
            description: "Show the next practice on my watch face.",
            votes: 12,
            target: .watchOS,
            status: "Planned",
            voted: false,
            updatedAt: "2026-07-15T12:00:00.000Z"
        ),
        LooplineFeatureRequest(
            id: "FDBK-3",
            title: "Health integration",
            description: "Include completed breathing sessions in Health.",
            votes: 9,
            target: .ios,
            status: "Released",
            voted: false,
            updatedAt: "2026-07-14T12:00:00.000Z"
        ),
    ]
}
#endif

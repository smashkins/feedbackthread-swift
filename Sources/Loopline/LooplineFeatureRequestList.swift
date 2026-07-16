#if os(iOS) && canImport(SwiftUI)
import SwiftUI

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

    private let client: LooplineClient
    private let appVersion: String?
    private let externalUserID: String?
    private let onDismiss: (() -> Void)?

    @AppStorage("com.loopline.sdk.voter-id") private var storedVoterID = ""
    @State private var requests: [LooplineFeatureRequest] = []
    @State private var loadState: LoadState = .loading
    @State private var votingIDs: Set<String> = []
    @State private var activeSheet: ActiveSheet?

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
                .toolbar {
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
            List(requests) { request in
                FeatureRequestRow(
                    request: request,
                    isVoting: votingIDs.contains(request.id),
                    onVote: { toggleVote(request) }
                )
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .listStyle(.plain)
            .overlay {
                if requests.isEmpty {
                    FeatureRequestMessage(
                        title: "No feature requests yet",
                        message: "Be the first to share an idea.",
                        systemImage: "lightbulb"
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
            Button(action: onVote) {
                VStack(spacing: 3) {
                    if isVoting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: request.voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                    }
                    Text("\(request.votes)")
                        .font(.caption2.monospacedDigit())
                }
                .frame(width: 38)
                .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(request.voted ? Color.accentColor : .secondary)
            .accessibilityLabel(request.voted ? "Remove vote" : "Vote")

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
                Text(request.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch request.status {
        case "Released", "Closed": .green
        case "In progress", "Ready to release": .blue
        default: .secondary
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
    ]
}
#endif

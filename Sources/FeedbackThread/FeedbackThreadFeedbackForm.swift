#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// A standalone "send feedback" form: usable on its own (e.g. from a Settings
/// screen) without the request board around it. Submissions are tied to the
/// same on-device anonymous ID the board and My Requests use, unless an
/// external ID is supplied - so a submission made from here still shows up
/// in "My requests" and can receive shipped updates.
public struct FeedbackThreadFeedbackForm: View {
    private enum SubmissionPhase: Equatable {
        case editing
        case submitting
        case sent
        case failed(String)
    }

    private struct PendingSubmission: Equatable, Identifiable, Sendable {
        let id: String
        let idempotencyKey: String
        let submission: FeedbackThreadFeedbackSubmission
    }

    @Environment(\.dismiss) private var dismiss

    private let client: FeedbackThreadClient
    private let appVersion: String?
    private let externalUserID: String?
    private let customerTierProvider: (() -> FeedbackThreadCustomerTier?)?
    private let onSubmitted: @MainActor @Sendable (FeedbackThreadFeedback) -> Void

    @State private var kind: FeedbackThreadFeedbackKind = .request
    @State private var title = ""
    @State private var message = ""
    @State private var phase: SubmissionPhase = .editing
    @State private var pendingSubmission: PendingSubmission?
    @State private var resubmissionKey = FeedbackThreadResubmissionKey()

    public init(
        client: FeedbackThreadClient,
        appVersion: String? = nil,
        externalUserID: String? = nil,
        customerTierProvider: (() -> FeedbackThreadCustomerTier?)? = nil,
        onSubmitted: @escaping @MainActor @Sendable (FeedbackThreadFeedback) -> Void = { _ in }
    ) {
        self.client = client
        self.appVersion = appVersion
        self.externalUserID = externalUserID
        self.customerTierProvider = customerTierProvider
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Feedback type", selection: $kind) {
                        ForEach(FeedbackThreadFeedbackKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _ in resubmissionKey.contentChanged() }

                    TextField("Short title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: title) { _ in resubmissionKey.contentChanged() }

                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Feedback details")
                        .onChange(of: message) { _ in resubmissionKey.contentChanged() }
                } header: {
                    Text("What would you like to share?")
                }

                if case .failed(let errorMessage) = phase {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if phase == .sent {
                    Section {
                        Label(
                            kind == .request ? "Request submitted for review." : "Feedback sent. Thank you!",
                            systemImage: "checkmark.circle.fill"
                        )
                            .foregroundStyle(.green)

                        Button("Done") { dismiss() }
                    }
                } else {
                    Section {
                        Button {
                            beginSubmission()
                        } label: {
                            HStack {
                                Spacer()
                                if phase == .submitting {
                                    ProgressView()
                                } else {
                                    Text("Send feedback")
                                }
                                Spacer()
                            }
                        }
                        .disabled(!canSubmit || phase == .submitting)
                    }
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: pendingSubmission?.id) {
                guard let pendingSubmission else { return }
                await submit(pendingSubmission)
            }
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginSubmission() {
        guard canSubmit else { return }
        // Reused across retries of the same content so a network failure followed
        // by tapping Send again can't create a duplicate submission server-side.
        let idempotencyKey = resubmissionKey.beginAttempt()
        // Always resolves to a non-empty identity - the provided external ID,
        // or the same persisted anonymous ID the board and My Requests use -
        // so this submission is never orphaned from "My requests".
        let resolvedUserID = FeedbackThreadIdentity.resolve(externalUserID: externalUserID)
        pendingSubmission = PendingSubmission(
            id: UUID().uuidString,
            idempotencyKey: idempotencyKey,
            submission: FeedbackThreadFeedbackSubmission(
                kind: kind,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                text: message.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: appVersion,
                externalUserID: resolvedUserID,
                customerTier: customerTierProvider?()
            )
        )
        phase = .submitting
    }

    @MainActor
    private func submit(_ pending: PendingSubmission) async {
        do {
            let feedback = try await client.submit(pending.submission, idempotencyKey: pending.idempotencyKey)
            guard !Task.isCancelled else { return }
            phase = .sent
            resubmissionKey.submissionSucceeded()
            onSubmitted(feedback)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct FeedbackThreadFeedbackFormPreviews: PreviewProvider {
    static var previews: some View {
        FeedbackThreadFeedbackForm(
            client: FeedbackThreadClient { submission, _ in
                FeedbackThreadFeedback(
                    id: "FDBK-preview",
                    kind: submission.kind,
                    source: "ios",
                    title: submission.title,
                    excerpt: submission.text,
                    version: submission.appVersion ?? "Preview",
                    status: "Submitted",
                    count: 1,
                    note: "",
                    responseDraft: "",
                    responseState: "Not started",
                    createdAt: "2026-07-16T12:00:00.000Z",
                    updatedAt: "2026-07-16T12:00:00.000Z"
                )
            },
            appVersion: "1.0 (42)"
        )
    }
}
#endif

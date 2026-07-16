#if os(iOS) && canImport(SwiftUI)
import SwiftUI

public struct LooplineFeedbackForm: View {
    private enum SubmissionPhase: Equatable {
        case editing
        case submitting
        case sent
        case failed(String)
    }

    private struct PendingSubmission: Equatable, Identifiable, Sendable {
        let id: String
        let submission: LooplineFeedbackSubmission
    }

    @Environment(\.dismiss) private var dismiss

    private let client: LooplineClient
    private let appVersion: String?
    private let externalUserID: String?
    private let onSubmitted: @MainActor @Sendable (LooplineFeedback) -> Void

    @State private var kind: LooplineFeedbackKind = .request
    @State private var title = ""
    @State private var message = ""
    @State private var phase: SubmissionPhase = .editing
    @State private var pendingSubmission: PendingSubmission?

    public init(
        client: LooplineClient,
        appVersion: String? = nil,
        externalUserID: String? = nil,
        onSubmitted: @escaping @MainActor @Sendable (LooplineFeedback) -> Void = { _ in }
    ) {
        self.client = client
        self.appVersion = appVersion
        self.externalUserID = externalUserID
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Feedback type", selection: $kind) {
                        ForEach(LooplineFeedbackKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Short title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Feedback details")
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
        let idempotencyKey = UUID().uuidString
        pendingSubmission = PendingSubmission(
            id: idempotencyKey,
            submission: LooplineFeedbackSubmission(
                kind: kind,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                text: message.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: appVersion,
                externalUserID: externalUserID
            )
        )
        phase = .submitting
    }

    @MainActor
    private func submit(_ pending: PendingSubmission) async {
        do {
            let feedback = try await client.submit(pending.submission, idempotencyKey: pending.id)
            guard !Task.isCancelled else { return }
            phase = .sent
            onSubmitted(feedback)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct LooplineFeedbackFormPreviews: PreviewProvider {
    static var previews: some View {
        LooplineFeedbackForm(
            client: LooplineClient { submission, _ in
                LooplineFeedback(
                    id: "FDBK-preview",
                    kind: submission.kind,
                    source: "ios",
                    title: submission.title,
                    excerpt: submission.text,
                    version: submission.appVersion ?? "Preview",
                    status: "Open",
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

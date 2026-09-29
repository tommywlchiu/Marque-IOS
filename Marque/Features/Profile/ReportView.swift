import SwiftUI

struct ReportView: View {
    let title: String
    let reportedUID: String
    let contentId: String?
    /// When set, the confirmation offers "Also block @username?".
    let reportedUsername: String?

    @EnvironmentObject var blockStore: BlockStore
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var selectedReason: ReportReason?
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @State private var blockTarget: UserRef?

    init(title: String, reportedUID: String, contentId: String? = nil, reportedUsername: String? = nil) {
        self.title = title
        self.reportedUID = reportedUID
        self.contentId = contentId
        self.reportedUsername = reportedUsername
    }

    private var canOfferBlock: Bool {
        guard let reportedUsername, !reportedUsername.isEmpty else { return false }
        return reportedUID != authService.currentUser?.id
    }

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    confirmationView
                } else {
                    reasonPicker
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !submitted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedReason == nil || isSubmitting)
                    }
                }
            }
        }
    }

    private var reasonPicker: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            List(ReportReason.allCases) { reason in
                Button {
                    selectedReason = reason
                } label: {
                    HStack {
                        Text(reason.rawValue)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            VStack(spacing: 8) {
                Text("Report Submitted")
                    .font(.title3).fontWeight(.bold)
                Text("Thanks for letting us know. We review all reports and take action when our guidelines are violated.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if canOfferBlock, let username = reportedUsername {
                blockOffer(username: username)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(32)
        .modifier(BlockUserConfirmation(target: $blockTarget))
    }

    @ViewBuilder
    private func blockOffer(username: String) -> some View {
        if blockStore.isBlocked(reportedUID) {
            Label("@\(username) is blocked", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 8) {
                Text("Also block @\(username)?")
                    .font(.subheadline.weight(.semibold))
                Text("You won't see their cars, comments or profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(role: .destructive) {
                    blockTarget = UserRef(uid: reportedUID, username: username)
                } label: {
                    Label("Block @\(username)", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
        }
    }

    private func submit() async {
        guard let reason = selectedReason else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await blockStore.report(reportedUID: reportedUID, reason: reason, contentId: contentId)
            submitted = true
        } catch {
            errorMessage = "Couldn't submit your report. Please try again."
        }
        isSubmitting = false
    }
}

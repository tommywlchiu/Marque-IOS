import SwiftUI

// MARK: - Community Guidelines gate (App Store guideline 1.2)

/// One-time agreement before a user's first comment, per uid on this device.
/// View-layer only: nothing server-side depends on it.
enum CommunityGuidelines {
    static func key(for uid: String) -> String { "marque_community_agreed_\(uid)" }

    static func hasAgreed(uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: uid))
    }

    static func recordAgreement(uid: String) {
        UserDefaults.standard.set(true, forKey: key(for: uid))
    }
}

struct CommunityGuidelinesSheet: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
            .padding(.top, 28)

            VStack(spacing: 10) {
                Text("Community Guidelines")
                    .font(.title2.weight(.bold))
                Text("Marque is for people who love cars. Keep comments respectful.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    guideline("xmark.shield", "No harassment, hate, or explicit content.")
                    guideline("trash", "Violations are removed and accounts may be banned.")
                    guideline("flag", "Report anything that breaks these rules.")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                MarquePrimaryButton("Agree") {
                    dismiss()
                    onAgree()
                }
                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    private func guideline(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundColor(.accentColor)
        }
    }
}

// MARK: - Shared social identity

/// A user reached from social content (comment author, notification actor).
struct UserRef: Identifiable, Hashable {
    let uid: String
    let username: String
    var id: String { uid }
}

/// What a comment row can ask its host to do. The host owns every sheet and
/// alert, so nothing presents from inside a List row.
struct CommentCallbacks {
    let onReport: (CarComment) -> Void
    let onBlock: (UserRef) -> Void
    let onOpenProfile: (UserRef) -> Void
    let onDeleteError: (String) -> Void
}

extension CarComment {
    var authorRef: UserRef { UserRef(uid: authorUID, username: authorUsername) }
}

/// "Block @username?" confirmation, then `BlockStore.block(uid:)`. The
/// blocked user's comments disappear through the existing block filter.
struct BlockUserConfirmation: ViewModifier {
    @Binding var target: UserRef?
    var onBlocked: ((UserRef) -> Void)? = nil

    @EnvironmentObject private var blockStore: BlockStore
    @State private var pending: UserRef?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert(
                "Block @\(target?.username ?? "")?",
                isPresented: Binding(
                    get: { target != nil },
                    set: { if !$0 { target = nil } }
                ),
                presenting: target
            ) { user in
                Button("Block", role: .destructive) { block(user) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their cars, comments or profile, and they won't be able to like or comment on your cars. You can unblock them from their profile.")
            }
            .alert("Couldn't Block", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func block(_ user: UserRef) {
        Task {
            await blockStore.block(uid: user.uid)
            // block(uid:) rolls back on failure instead of throwing.
            if blockStore.isBlocked(user.uid) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onBlocked?(user)
            } else {
                errorMessage = "Couldn't block @\(user.username). Check your connection and try again."
            }
        }
    }
}

// MARK: - Row

struct CommentRow: View {
    let comment: CarComment
    /// Shows an "Owner" tag when the author owns the car.
    let carOwnerUID: String
    /// Opens the author's public profile (avatar and name are tappable).
    var onOpenProfile: ((UserRef) -> Void)? = nil

    private var hasDisplayName: Bool {
        !comment.authorDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            identityButton {
                OwnerAvatar(avatarURL: comment.authorAvatarURL, username: comment.authorUsername, size: 34)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    identityButton { nameBlock }
                    if comment.authorUID == carOwnerUID {
                        Text("Owner")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                    Spacer(minLength: 4)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "View @\(comment.authorUsername)'s profile") {
            onOpenProfile?(comment.authorRef)
        }
    }

    /// Display name (one line, truncated), then the @username, which is
    /// always shown so a display name can't pass as someone else.
    @ViewBuilder
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasDisplayName {
                Text(comment.authorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("@\(comment.authorUsername)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("@\(comment.authorUsername)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func identityButton<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if let onOpenProfile {
            // Borderless so only this area takes the tap inside a List row.
            Button { onOpenProfile(comment.authorRef) } label: { label() }
                .buttonStyle(.borderless)
        } else {
            label()
        }
    }
}

/// Swipe actions + context menu for a comment row inside a List: delete
/// (author or car owner), report and block (anyone but the author).
struct CommentRowActions: ViewModifier {
    let comment: CarComment
    let carId: String
    let carOwnerUID: String
    let callbacks: CommentCallbacks

    @EnvironmentObject private var commentStore: CommentStore
    @EnvironmentObject private var authService: AuthService

    private var canDelete: Bool { commentStore.canDelete(comment, carOwnerUID: carOwnerUID) }
    private var isOthers: Bool {
        guard let me = authService.currentUser?.id, !me.isEmpty else { return false }
        return comment.authorUID != me
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDelete {
                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                if isOthers {
                    Button { callbacks.onBlock(comment.authorRef) } label: {
                        Label("Block", systemImage: "person.crop.circle.badge.minus")
                    }
                    .tint(.gray)
                    Button { callbacks.onReport(comment) } label: {
                        Label("Report", systemImage: "flag")
                    }
                    .tint(.orange)
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = comment.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { callbacks.onOpenProfile(comment.authorRef) } label: {
                    Label("View @\(comment.authorUsername)", systemImage: "person.crop.circle")
                }
                if isOthers {
                    Button { callbacks.onReport(comment) } label: {
                        Label("Report Comment", systemImage: "flag")
                    }
                    Button(role: .destructive) { callbacks.onBlock(comment.authorRef) } label: {
                        Label("Block @\(comment.authorUsername)", systemImage: "person.crop.circle.badge.minus")
                    }
                }
                if canDelete {
                    Button(role: .destructive, action: delete) {
                        Label("Delete Comment", systemImage: "trash")
                    }
                }
            }
    }

    private func delete() {
        Task {
            do {
                try await commentStore.delete(comment, on: carId)
            } catch {
                callbacks.onDeleteError("Couldn't delete the comment. Please try again.")
            }
        }
    }
}

// MARK: - Inline section (car page)

/// "Comments (n)" section inside `CarDetailView`'s List: the latest few
/// comments, "View all" and an "Add a comment" entry point. The host owns the
/// sheets (comments sheet, report) so nothing presents from inside a List row.
struct CarCommentsSection: View {
    let carId: String
    let carOwnerUID: String
    /// Server-maintained count, used when more comments exist than are loaded.
    let serverCount: Int
    let onOpenComments: (_ focusComposer: Bool) -> Void
    let callbacks: CommentCallbacks

    @EnvironmentObject private var commentStore: CommentStore
    @EnvironmentObject private var blockStore: BlockStore

    static let inlineLimit = 3

    private var isCurrent: Bool { commentStore.carId == carId }
    private var visible: [CarComment] {
        isCurrent ? commentStore.visibleComments(hiding: blockStore.blockedUIDs) : []
    }

    private var count: Int {
        guard isCurrent, !commentStore.isLoading else { return serverCount }
        return commentStore.comments.count >= CommentStore.pageLimit
            ? max(serverCount, visible.count)
            : visible.count
    }

    var body: some View {
        Section(header: header) {
            if (commentStore.isLoading || !isCurrent) && visible.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if commentStore.lastError != nil, visible.isEmpty {
                Label("Couldn't load comments.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if visible.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No comments yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Start the conversation about this car.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(visible.suffix(Self.inlineLimit)) { comment in
                    CommentRow(comment: comment, carOwnerUID: carOwnerUID, onOpenProfile: callbacks.onOpenProfile)
                        .modifier(CommentRowActions(
                            comment: comment,
                            carId: carId,
                            carOwnerUID: carOwnerUID,
                            callbacks: callbacks
                        ))
                }
            }

            Button {
                onOpenComments(true)
            } label: {
                Label("Add a comment", systemImage: "bubble.left")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Comments (\(count))")
            Spacer()
            if visible.count > Self.inlineLimit || count > Self.inlineLimit {
                Button("View All") { onOpenComments(false) }
                    .font(.subheadline)
                    .textCase(nil)
            }
        }
    }
}

// MARK: - Full comments sheet

struct CommentsSheet: View {
    let carId: String
    let carOwnerUID: String
    let carName: String
    var focusComposerOnAppear = false

    @EnvironmentObject private var commentStore: CommentStore
    @EnvironmentObject private var blockStore: BlockStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var isPosting = false
    @State private var postError: String?
    @State private var showingGuidelines = false
    @State private var reportingComment: CarComment?
    @State private var blockTarget: UserRef?
    @State private var profileRoute: UserRef?
    @State private var deleteError: String?
    @State private var showingPushPrePrompt = false
    @FocusState private var composerFocused: Bool

    private var visible: [CarComment] {
        commentStore.carId == carId ? commentStore.visibleComments(hiding: blockStore.blockedUIDs) : []
    }

    private var draftLength: Int {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    private var canSend: Bool {
        draftLength > 0 && draftLength <= CarComment.maxLength && !isPosting
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Comments")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { composer }
                .navigationDestination(item: $profileRoute) { user in
                    PublicProfileView(ownerUID: user.uid, ownerUsername: user.username)
                }
        }
        .onAppear {
            // The car page normally started this; covers opening from elsewhere.
            if commentStore.carId != carId { commentStore.listen(to: carId) }
            if focusComposerOnAppear {
                // Focus only sticks once the sheet has finished presenting.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    composerFocused = true
                }
            }
        }
        .sheet(isPresented: $showingGuidelines) {
            CommunityGuidelinesSheet {
                if let uid = authService.currentUser?.id {
                    CommunityGuidelines.recordAgreement(uid: uid)
                }
                Task { await post() }
            }
        }
        .sheet(item: $reportingComment) { comment in
            ReportView(
                title: "Report Comment",
                reportedUID: comment.authorUID,
                contentId: ReportContent.comment(carId: carId, commentId: comment.documentID ?? comment.id),
                reportedUsername: comment.authorUsername
            )
        }
        .modifier(BlockUserConfirmation(target: $blockTarget))
        .pushPrePrompt(isPresented: $showingPushPrePrompt)
        .alert("Couldn't Delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if commentStore.isLoading && visible.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            ScrollView {
                MarqueEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No Comments Yet",
                    subtitle: "Be the first to say something about this \(carName.isEmpty ? "car" : carName)."
                )
                .padding(.top, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(visible) { comment in
                        CommentRow(comment: comment, carOwnerUID: carOwnerUID, onOpenProfile: { profileRoute = $0 })
                            .id(comment.id)
                            .modifier(CommentRowActions(
                                comment: comment,
                                carId: carId,
                                carOwnerUID: carOwnerUID,
                                callbacks: callbacks
                            ))
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: visible.last?.id) { _, _ in scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private var callbacks: CommentCallbacks {
        CommentCallbacks(
            onReport: { reportingComment = $0 },
            onBlock: { blockTarget = $0 },
            onOpenProfile: { profileRoute = $0 },
            onDeleteError: { deleteError = $0 }
        )
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = visible.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let postError {
                MarqueErrorBanner(message: postError)
                    .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray6)))
                    .onChange(of: draft) { _, _ in
                        if postError != nil { postError = nil }
                    }

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(canSend ? .accentColor : Color(.systemGray3))
                        }
                    }
                    .frame(width: 36, height: 40)
                }
                .disabled(!canSend)
                .accessibilityLabel("Post comment")
            }
            HStack {
                Text("Keep it friendly. Comments are public.")
                Spacer()
                Text("\(draftLength)/\(CarComment.maxLength)")
                    .monospacedDigit()
                    .foregroundColor(draftLength > CarComment.maxLength ? .red : .secondary)
                    .accessibilityLabel("\(draftLength) of \(CarComment.maxLength) characters")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func send() async {
        guard canSend else { return }
        guard let uid = authService.currentUser?.id else {
            postError = CommentStore.CommentError.notSignedIn.localizedDescription
            return
        }
        // Friendly local check first; CommentStore and the server re-check.
        if CommentFilter.containsBlockedTerm(draft) {
            postError = "Let's keep it friendly. Your comment includes language that isn't allowed in the Marque community."
            return
        }
        guard CommunityGuidelines.hasAgreed(uid: uid) else {
            composerFocused = false
            showingGuidelines = true
            return
        }
        await post()
    }

    private func post() async {
        guard canSend else { return }
        isPosting = true
        postError = nil
        do {
            try await commentStore.post(text: draft, on: carId)
            draft = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            PushPrePrompt.offer { showingPushPrePrompt = true }
        } catch let error as CommentStore.CommentError {
            postError = error.localizedDescription
        } catch {
            postError = CommentStore.CommentError.rejected.localizedDescription
        }
        isPosting = false
    }
}

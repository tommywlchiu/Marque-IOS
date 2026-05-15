import SwiftUI

struct CommentsView: View {
    let post: Post

    @EnvironmentObject var socialStore: SocialStore
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var commentText = ""
    @State private var isSending = false
    @FocusState private var inputFocused: Bool

    private var comments: [Comment] {
        socialStore.comments(for: post.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                postSummaryHeader
                Divider()

                if comments.isEmpty {
                    emptyState
                } else {
                    commentList
                }

                Divider()
                inputBar
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Post summary header

    private var postSummaryHeader: some View {
        HStack(spacing: 10) {
            UserAvatar(user: post.user, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.user.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(post.car.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Comment list

    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment) {
                            socialStore.toggleCommentLike(commentID: comment.id, postID: post.id)
                        }
                        .id(comment.id)
                        Divider().padding(.leading, 62)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: comments.count) { _, _ in
                if let last = comments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No comments yet")
                .font(.headline)
            Text("Be the first to leave a comment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            UserAvatar(user: authService.currentUser ?? .preview, size: 32)

            TextField("Add a comment…", text: $commentText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { sendComment() }

            if !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: sendComment) {
                    if isSending {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.accentColor)
                            .font(.body)
                    }
                }
                .disabled(isSending)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .animation(.spring(response: 0.2), value: commentText.isEmpty)
    }

    // MARK: - Actions

    private func sendComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        commentText = ""
        // Simulate brief async delay so the UI feels responsive
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            socialStore.addComment(text, to: post.id)
            isSending = false
        }
    }
}

// MARK: - Comment Row

private struct CommentRow: View {
    let comment: Comment
    let onLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatar(user: comment.author, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 4) {
                Button(action: onLike) {
                    Image(systemName: comment.isLikedByMe ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(comment.isLikedByMe ? .red : .secondary)
                }
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

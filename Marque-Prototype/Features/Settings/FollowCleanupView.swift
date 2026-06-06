import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FollowCleanupView: View {
    @Environment(\.dismiss) var dismiss

    private enum Phase: Equatable {
        case idle
        case scanning
        case preview(ghostFollowers: [String], ghostFollowing: [String])
        case cleaning
        case done(removedFollowers: Int, removedFollowing: Int)
        case failed(String)
    }

    @State private var phase: Phase = .idle
    private let db = Firestore.firestore()
    private var currentUID: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 28) {
                    phaseIcon
                    phaseText
                    phaseAction
                }
                .padding(.horizontal, 36)
                Spacer()
                Spacer()
            }
            .navigationTitle("Fix Follow Counts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
    }

    // MARK: - Phase components

    private var phaseIcon: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.12))
                .frame(width: 88, height: 88)
            Image(systemName: iconName)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(iconColor)
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    @ViewBuilder
    private var phaseText: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3).fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var phaseAction: some View {
        switch phase {
        case .idle:
            actionButton(label: "Scan Now", role: nil) {
                Task { await scan() }
            }

        case .scanning, .cleaning:
            ProgressView()
                .controlSize(.large)
                .padding(.vertical, 8)

        case .preview(let ghostFollowers, let ghostFollowing):
            let total = ghostFollowers.count + ghostFollowing.count
            if total == 0 {
                actionButton(label: "Done", role: nil) { dismiss() }
                    .tint(.secondary)
            } else {
                VStack(spacing: 12) {
                    actionButton(
                        label: "Remove \(total) \(total == 1 ? "Ghost Entry" : "Ghost Entries")",
                        role: .destructive
                    ) {
                        Task { await clean(ghostFollowers: ghostFollowers, ghostFollowing: ghostFollowing) }
                    }
                    Button("Cancel") { phase = .idle }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

        case .done:
            actionButton(label: "Done", role: nil) { dismiss() }

        case .failed:
            VStack(spacing: 12) {
                actionButton(label: "Try Again", role: nil) {
                    Task { await scan() }
                }
                Button("Cancel") { phase = .idle }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func actionButton(label: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Derived display values

    private var isWorking: Bool {
        phase == .scanning || phase == .cleaning
    }

    private var iconName: String {
        switch phase {
        case .idle, .scanning, .cleaning:    return "person.2.slash"
        case .preview(let f, let g) where f.isEmpty && g.isEmpty: return "checkmark.circle.fill"
        case .preview:                        return "exclamationmark.circle.fill"
        case .done:                           return "checkmark.circle.fill"
        case .failed:                         return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch phase {
        case .preview(let f, let g) where f.isEmpty && g.isEmpty: return .green
        case .done:   return .green
        case .failed: return .orange
        case .preview: return .red
        default:       return .accentColor
        }
    }

    private var title: String {
        switch phase {
        case .idle:     return "Fix Follow Counts"
        case .scanning: return "Scanning…"
        case .preview(let f, let g):
            let total = f.count + g.count
            return total == 0 ? "All Clean" : "\(total) Ghost \(total == 1 ? "Entry" : "Entries") Found"
        case .cleaning: return "Removing…"
        case .done(let f, let g):
            let total = f + g
            return total == 0 ? "Nothing to Remove" : "Done"
        case .failed:   return "Something Went Wrong"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return "Checks your follower and following lists for deleted accounts and removes any stale entries that are inflating your counts."
        case .scanning:
            return "Verifying each account against Firestore."
        case .preview(let ghostFollowers, let ghostFollowing):
            let total = ghostFollowers.count + ghostFollowing.count
            if total == 0 {
                return "No stale entries found. Your follow counts are accurate."
            }
            var parts: [String] = []
            if !ghostFollowers.isEmpty {
                parts.append("\(ghostFollowers.count) ghost follower\(ghostFollowers.count == 1 ? "" : "s")")
            }
            if !ghostFollowing.isEmpty {
                parts.append("\(ghostFollowing.count) ghost following \(ghostFollowing.count == 1 ? "entry" : "entries")")
            }
            return parts.joined(separator: " and ") + " from deleted accounts."
        case .cleaning:
            return "Writing changes to Firestore."
        case .done(let removedFollowers, let removedFollowing):
            let total = removedFollowers + removedFollowing
            if total == 0 { return "Your follow data was already clean." }
            var parts: [String] = []
            if removedFollowers > 0 { parts.append("\(removedFollowers) follower\(removedFollowers == 1 ? "" : "s")") }
            if removedFollowing > 0 { parts.append("\(removedFollowing) following \(removedFollowing == 1 ? "entry" : "entries")") }
            return "Removed " + parts.joined(separator: " and ") + ". Your counts are now accurate."
        case .failed(let message):
            return message
        }
    }

    // MARK: - Scan

    private func scan() async {
        guard let uid = currentUID else { phase = .failed("Not signed in."); return }
        phase = .scanning

        do {
            // Fetch both subcollections concurrently.
            async let followerFetch = db.collection("users").document(uid)
                .collection("followers").getDocuments()
            async let followingFetch = db.collection("users").document(uid)
                .collection("following").getDocuments()

            let (followerSnap, followingSnap) = try await (followerFetch, followingFetch)

            var ghostFollowers: [String] = []
            var ghostFollowing: [String] = []

            // Verify each UID against Firestore in parallel.
            await withTaskGroup(of: (kind: String, uid: String, exists: Bool).self) { group in
                for doc in followerSnap.documents {
                    let candidateUID = doc.documentID
                    group.addTask {
                        let exists = (try? await self.db.collection("users")
                            .document(candidateUID).getDocument())?.exists ?? false
                        return (kind: "follower", uid: candidateUID, exists: exists)
                    }
                }
                for doc in followingSnap.documents {
                    let candidateUID = doc.documentID
                    group.addTask {
                        let exists = (try? await self.db.collection("users")
                            .document(candidateUID).getDocument())?.exists ?? false
                        return (kind: "following", uid: candidateUID, exists: exists)
                    }
                }
                for await result in group {
                    guard !result.exists else { continue }
                    if result.kind == "follower" { ghostFollowers.append(result.uid) }
                    else { ghostFollowing.append(result.uid) }
                }
            }

            phase = .preview(ghostFollowers: ghostFollowers, ghostFollowing: ghostFollowing)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Clean

    private func clean(ghostFollowers: [String], ghostFollowing: [String]) async {
        guard let uid = currentUID else { phase = .failed("Not signed in."); return }
        phase = .cleaning

        do {
            let batch = db.batch()
            for ghostUID in ghostFollowers {
                batch.deleteDocument(
                    db.collection("users").document(uid)
                        .collection("followers").document(ghostUID)
                )
            }
            for ghostUID in ghostFollowing {
                batch.deleteDocument(
                    db.collection("users").document(uid)
                        .collection("following").document(ghostUID)
                )
            }
            try await batch.commit()
            phase = .done(removedFollowers: ghostFollowers.count, removedFollowing: ghostFollowing.count)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

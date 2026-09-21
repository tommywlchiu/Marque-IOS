import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Network

// Owns Marque Assistant conversations: the conversation list, the currently
// open conversation's messages, the streaming call to `askMarque`, and
// Firestore persistence.
//
// The Cloud Function is stateless — this store writes the user message before
// the call and the assembled assistant message after streaming completes, so
// on a mid-stream failure we still have the user's message on disk with a
// retry affordance.
@MainActor
class ChatStore: ObservableObject {

    // MARK: - Published state

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var currentMessages: [ChatMessage] = []
    @Published var isSending: Bool = false
    @Published var sendError: SendError?
    @Published var todayMessageCount: Int = 0
    @Published var isOffline: Bool = false

    /// User-facing message for a failed delete or pin action the user asked for
    /// (or the pin limit). `nil` normally; the view shows it and calls
    /// `clearConversationActionError()`. Never set by automatic cap enforcement.
    @Published var conversationActionError: String?

    /// Server-side plan (`users/{uid}.isPro`, the value `getIsPro` reads in
    /// `askMarque`). `nil` means "not yet known" — before the first snapshot,
    /// after a listener error, and after `stopListening()`. Never read StoreKit
    /// for the cap: a Family Sharing member has local StoreKit Pro but the server
    /// withholds the flag, so it enforces the free cap.
    @Published private(set) var serverIsPro: Bool?

    // MARK: - Config

    // Match FR-10.4 caps. Display copies of FREE_DAILY_CAP / PRO_DAILY_CAP in
    // functions/src/index.ts; change them together. `nonisolated` because
    // SendError.errorDescription (not main-actor) reads proDailyCap.
    nonisolated static let freeDailyCap = 10
    nonisolated static let proDailyCap = 500

    /// Today's cap for the server-side plan, or `nil` while the plan is unknown.
    var dailyCap: Int? {
        guard let serverIsPro else { return nil }
        return serverIsPro ? Self.proDailyCap : Self.freeDailyCap
    }

    // Match FR-10.19 lifecycle. Pinned convos are exempt from auto-delete.
    private let maxConversations = 50
    private let maxPinned = 10

    // Match FR-10.20 — trim to last N turns before sending to the function.
    private let maxContextTurns = 30

    // MARK: - Errors

    enum SendError: LocalizedError, Identifiable {
        case capReached(cap: Int, isPro: Bool)
        case offline
        case authRequired
        case service(String)
        case unknown(String)

        var id: String { errorDescription ?? "unknown" }

        var errorDescription: String? {
            switch self {
            case .capReached(let cap, let isPro):
                return isPro
                    ? "You've reached today's \(cap) message limit. Try again tomorrow."
                    : "You've reached today's \(cap) message limit. Upgrade to Pro for \(ChatStore.proDailyCap) messages a day."
            case .offline:
                return "Marque needs a connection. Check your network and try again."
            case .authRequired:
                return "Sign in to use Marque."
            case .service(let detail):
                return detail.isEmpty ? "Marque couldn't answer right now. Try again." : detail
            case .unknown(let detail):
                return detail.isEmpty ? "Something went wrong. Try again." : detail
            }
        }

        var isCap: Bool {
            if case .capReached = self { return true }
            return false
        }
    }

    // MARK: - Wire types

    // Matches the AskMarqueRequest interface in functions/src/index.ts.
    // scopedCarId is optional; Encodable omits nil via default nil-encoding.
    private struct RequestPayload: Encodable, Sendable {
        let message: String
        let history: [HistoryMessage]
        let clientDate: String
        let scopedCarId: String?

        struct HistoryMessage: Encodable, Sendable {
            let role: String
            let content: String
        }
    }

    // Streamed chunk shape from response.sendChunk. Extra keys like `type`
    // are ignored by Codable — only `text` is needed.
    private struct StreamChunk: Decodable, Sendable {
        let text: String
    }

    // The Cloud Function's return value (the final metadata).
    private struct StreamResult: Decodable, Sendable {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
    }

    // MARK: - Private

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var usageListener: ListenerRegistration?
    private var planListener: ListenerRegistration?
    private var planListenerFailed = false
    private var planGeneration = 0
    private var conversationsListenerFailed = false
    private var conversationsGeneration = 0
    private var messagesListenerFailedConvId: String?
    private var messagesGeneration = 0
    private var currentUID: String?
    private var usageListeningDate: String?
    private var observers: [NSObjectProtocol] = []

    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.marque.chat.network")

    private static let localDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df
    }()

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = path.status != .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)

        // The usage document is keyed by local date, so a session that crosses
        // midnight must re-attach — otherwise a stale count would show as fact.
        let names: [Notification.Name] = [.NSCalendarDayChanged, UIApplication.didBecomeActiveNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIfNeeded() }
            }
        }
    }

    deinit {
        networkMonitor.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        conversationsListener?.remove()
        messagesListener?.remove()
        usageListener?.remove()
        planListener?.remove()
    }

    // MARK: - Auth lifecycle

    func startListening(uid: String) {
        guard uid != currentUID else { return }
        stopListening()
        currentUID = uid

        attachConversationsListener(uid: uid)
        watchTodayUsage(uid: uid)
        attachPlanListener(uid: uid)
    }

    func stopListening() {
        conversationsListener?.remove()
        conversationsListener = nil
        messagesListener?.remove()
        messagesListener = nil
        usageListener?.remove()
        usageListener = nil
        usageListeningDate = nil
        planListener?.remove()
        planListener = nil
        planGeneration += 1
        planListenerFailed = false
        conversationsGeneration += 1
        conversationsListenerFailed = false
        messagesGeneration += 1
        messagesListenerFailedConvId = nil
        serverIsPro = nil
        currentUID = nil
        conversations = []
        currentConversation = nil
        currentMessages = []
        todayMessageCount = 0
        conversationActionError = nil
    }

    // MARK: - Conversation management

    // Reset to empty; a new conversation doc is created lazily on first send.
    func newConversation(scopedCarId: String? = nil) {
        messagesListener?.remove()
        messagesListener = nil
        messagesGeneration += 1
        messagesListenerFailedConvId = nil
        currentConversation = nil
        currentMessages = []
        sendError = nil
        // scopedCarId is remembered for the first send via a private ivar.
        pendingScopedCarId = scopedCarId
    }

    private var pendingScopedCarId: String?

    func openConversation(_ conversation: Conversation) {
        guard let uid = currentUID, let convId = conversation.id else { return }
        currentConversation = conversation
        currentMessages = []
        sendError = nil
        // Replaces the previous listener and clears its failure record.
        attachMessagesListener(uid: uid, convId: convId)
    }

    func clearConversationActionError() {
        conversationActionError = nil
    }

    /// User-initiated delete. Returns true only if the messages and the parent doc
    /// are both gone; on failure sets `conversationActionError`.
    @discardableResult
    func deleteConversation(_ conversation: Conversation) async -> Bool {
        conversationActionError = nil
        let deleted = await removeConversation(conversation)
        if !deleted {
            conversationActionError = "Couldn't delete that conversation. Try again."
        }
        return deleted
    }

    /// Shared by the user-initiated delete and automatic cap enforcement; reports
    /// failure by return value only, so the caller decides whether to surface it.
    private func removeConversation(_ conversation: Conversation) async -> Bool {
        guard let uid = currentUID, let convId = conversation.id else { return false }
        // Firestore doesn't cascade: delete every message (a page per batch),
        // then the parent doc LAST. A failure part-way leaves the parent in place,
        // still listed and retryable, instead of orphaning its messages.
        let convoRef = db.collection("users").document(uid)
            .collection("conversations").document(convId)
        let messagesRef = convoRef.collection("messages")
        do {
            var previousFirstId: String?
            while true {
                let snap = try await messagesRef.limit(to: 500).getDocuments()
                guard let firstId = snap.documents.first?.documentID else { break }
                // A commit that succeeded but left the same page in place would
                // spin forever; treat it as a failure.
                guard firstId != previousFirstId else {
                    print("[ChatStore] Delete conversation made no progress")
                    return false
                }
                previousFirstId = firstId
                let batch = db.batch()
                for doc in snap.documents { batch.deleteDocument(doc.reference) }
                try await batch.commit()
            }
            try await convoRef.delete()
        } catch {
            print("[ChatStore] Delete conversation failed: \(error.localizedDescription)")
            return false
        }
        if currentConversation?.id == convId {
            newConversation()
        }
        return true
    }

    func togglePin(_ conversation: Conversation) async {
        guard let uid = currentUID, let convId = conversation.id else { return }
        conversationActionError = nil
        let currentlyPinnedCount = conversations.filter { $0.isPinned }.count
        let newValue = !conversation.isPinned
        if newValue && currentlyPinnedCount >= maxPinned {
            conversationActionError = "You can pin up to \(maxPinned) conversations."
            return
        }
        let ref = db.collection("users").document(uid)
            .collection("conversations").document(convId)
        do {
            try await ref.updateData(["isPinned": newValue])
        } catch {
            print("[ChatStore] Pin update failed: \(error.localizedDescription)")
            conversationActionError = "Couldn't update the pin. Try again."
        }
    }

    // MARK: - Sending

    // Fires the streaming call to `askMarque`. Handles Firestore writes for
    // both messages, appends deltas to the visible assistant message as they
    // arrive, and translates function errors into user-facing SendError cases.
    func sendMessage(_ text: String) async {
        guard let uid = currentUID else {
            sendError = .authRequired
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isOffline {
            sendError = .offline
            return
        }
        if isSending { return }

        isSending = true
        sendError = nil
        defer { isSending = false }

        // 1. Capture history BEFORE any Firestore writes. Firestore's local
        //    snapshot listener can fire synchronously on our own writes, and
        //    we don't want the just-written user message duplicated in both
        //    `history` and `message` on the wire.
        let historyPayload = currentMessages
            .filter { $0.isStreaming != true }
            .suffix(maxContextTurns)
            .map { RequestPayload.HistoryMessage(role: $0.role, content: $0.content) }

        // 2. Get or create the conversation. Titles derive from the first
        //    user message; scopedCarId is captured from newConversation().
        let (conversation, isNew) = await ensureConversation(uid: uid, firstMessage: trimmed)
        guard let convId = conversation.id else {
            sendError = .unknown("Couldn't create conversation.")
            return
        }
        if isNew {
            currentConversation = conversation
            attachMessagesListener(uid: uid, convId: convId)
        }

        // 3. Persist the user message first so it survives a mid-stream failure.
        let userMessage = ChatMessage.user(trimmed)
        let userMsgRef = db.collection("users").document(uid)
            .collection("conversations").document(convId)
            .collection("messages").document()
        do {
            try userMsgRef.setData(from: userMessage)
        } catch {
            sendError = .unknown("Couldn't save your message.")
            return
        }

        // 4. Streaming assistant placeholder — shown while the model responds.
        var assistantMessage = ChatMessage.assistantPlaceholder()
        assistantMessage.id = UUID().uuidString
        currentMessages.append(assistantMessage)
        let assistantLocalId = assistantMessage.id

        let payload = RequestPayload(
            message: trimmed,
            history: Array(historyPayload),
            clientDate: Self.localDateFormatter.string(from: Date()),
            scopedCarId: conversation.scopedCarId
        )

        // 5. Typed streaming call. StreamResponse<Message, Result> receives
        //    both intermediate chunks (from response.sendChunk on the server)
        //    and the function's final return value.
        let callable = functions.httpsCallable(
            "askMarque",
            requestAs: RequestPayload.self,
            responseAs: StreamResponse<StreamChunk, StreamResult>.self
        )

        var accumulated = ""
        var finalMeta: StreamResult?

        do {
            let stream = try callable.stream(payload)
            for try await event in stream {
                switch event {
                case .message(let chunk):
                    accumulated += chunk.text
                    updateStreamingMessage(id: assistantLocalId, content: accumulated)
                case .result(let final):
                    finalMeta = final
                }
            }
        } catch {
            removeStreamingMessage(id: assistantLocalId)
            sendError = translateSendError(error)
            return
        }

        // FR-11.4 `assistant_message_sent`. Fired here, after the stream
        // completed without throwing — i.e. the message really was sent and
        // answered, not merely attempted. Carries only whether the conversation
        // was scoped to a car; never any part of the message body (FR-11.6).
        AnalyticsService.assistantMessageSent(wasScopedToCar: conversation.scopedCarId != nil)

        // 6. Finalize: persist the assistant message and update convo metadata.
        guard let assistantIndex = currentMessages.firstIndex(where: { $0.id == assistantLocalId }) else {
            return
        }
        var finalized = currentMessages[assistantIndex]
        finalized.isStreaming = false
        finalized.content = accumulated
        finalized.model = finalMeta?.model
        finalized.inputTokens = finalMeta?.inputTokens
        finalized.outputTokens = finalMeta?.outputTokens
        finalized.cacheReadTokens = finalMeta?.cacheReadTokens
        currentMessages[assistantIndex] = finalized

        let assistantRef = db.collection("users").document(uid)
            .collection("conversations").document(convId)
            .collection("messages").document()
        do {
            try assistantRef.setData(from: finalized)
        } catch {
            // setData(from:) without a completion only throws on an encoding
            // failure (the write itself is queued locally). The message stays in
            // memory so the user can still read and copy it.
            print("[ChatStore] Couldn't encode the assistant message for saving: \(error.localizedDescription)")
        }

        let convoRef = db.collection("users").document(uid)
            .collection("conversations").document(convId)
        do {
            try await convoRef.updateData([
                "updatedAt": FieldValue.serverTimestamp(),
                "messageCount": FieldValue.increment(Int64(2)),
            ])
        } catch {
            // Bookkeeping only — the message already sent. Not surfaced to the user.
            print("[ChatStore] Conversation metadata update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Streaming helpers

    private func updateStreamingMessage(id: String?, content: String) {
        guard let id, let idx = currentMessages.firstIndex(where: { $0.id == id }) else { return }
        currentMessages[idx].content = content
    }

    private func removeStreamingMessage(id: String?) {
        guard let id, let idx = currentMessages.firstIndex(where: { $0.id == id }) else { return }
        currentMessages.remove(at: idx)
    }

    // MARK: - Cap tracking

    /// Runs on day rollover and on foreground. A cheap no-op on an ordinary
    /// foreground within the same day; re-attaches the usage listener only when
    /// its date is stale (or an error cleared it).
    private func refreshIfNeeded() {
        guard let uid = currentUID else { return }
        if usageListeningDate != Self.localDateFormatter.string(from: Date()) {
            watchTodayUsage(uid: uid)
        }
        refreshListenersIfNeeded()
    }

    private func watchTodayUsage(uid: String) {
        usageListener?.remove()
        let date = Self.localDateFormatter.string(from: Date())
        usageListeningDate = date
        // Never show the previous day's count as fact while the new snapshot loads.
        todayMessageCount = 0
        let ref = db.collection("users").document(uid)
            .collection("usage").document("assistant_\(date)")
        usageListener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, self.currentUID == uid, self.usageListeningDate == date else { return }
            if let error {
                // Firestore ends a listener after an error, so this count would go
                // stale. Keep the last count (display only — the server enforces
                // the cap) and clear usageListeningDate so the next foreground
                // re-attaches instead of leaving the listener dead all day.
                print("[ChatStore] Usage listener error: \(error.localizedDescription)")
                self.usageListeningDate = nil
                return
            }
            let count = (snap?.data()?["count"] as? Int) ?? 0
            self.todayMessageCount = max(count, 0)
        }
    }

    /// Follows `users/{uid}.isPro` (server-written only, so the client cannot forge
    /// it — see firestore.rules). Independent of the date-scoped usage listener.
    /// A live listener, so the cap updates by itself when the server flag flips.
    private func attachPlanListener(uid: String) {
        planListener?.remove()
        planGeneration += 1
        let generation = planGeneration
        planListenerFailed = false
        planListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self, self.currentUID == uid, self.planGeneration == generation else { return }
                if let error {
                    // Firestore ends a listener after an error. Fall back to
                    // "unknown" rather than keep a plan that can no longer update;
                    // refreshPlanIfNeeded() re-attaches on the next chat appearance.
                    print("[ChatStore] Plan listener error: \(error.localizedDescription)")
                    self.serverIsPro = nil
                    self.planListenerFailed = true
                    return
                }
                guard let snap else { return }
                // A missing profile doc means free to the server (getIsPro), but a
                // *cache-only* miss just means we haven't heard from the server
                // yet — asserting "free" then would mislabel a Pro user offline.
                if !snap.exists && snap.metadata.isFromCache { return }
                self.serverIsPro = snap.data()?["isPro"] as? Bool == true
            }
    }

    /// Re-attaches the plan listener only if an error killed it. Safe to call
    /// repeatedly; a no-op when signed out or when the listener is healthy.
    func refreshPlanIfNeeded() {
        guard let uid = currentUID, planListenerFailed else { return }
        attachPlanListener(uid: uid)
    }

    /// Re-attaches any snapshot listener that an error ended: plan, conversation
    /// list, and the open conversation's messages. Safe to call repeatedly; a
    /// no-op when signed out or when every listener is healthy.
    func refreshListenersIfNeeded() {
        guard let uid = currentUID else { return }
        refreshPlanIfNeeded()
        if conversationsListenerFailed {
            attachConversationsListener(uid: uid)
        }
        if let failedConvId = messagesListenerFailedConvId {
            if currentConversation?.id == failedConvId {
                attachMessagesListener(uid: uid, convId: failedConvId)
            } else {
                messagesListenerFailedConvId = nil
            }
        }
    }

    // MARK: - Private helpers

    private func ensureConversation(uid: String, firstMessage: String) async -> (Conversation, Bool) {
        if let existing = currentConversation { return (existing, false) }

        // Auto-delete oldest un-pinned conversation if at cap (FR-10.19).
        await enforceConversationCap(uid: uid)

        let convoRef = db.collection("users").document(uid)
            .collection("conversations").document()
        let title = String(firstMessage.prefix(60))
        let now = Date()
        let convo = Conversation(
            id: convoRef.documentID,
            title: title,
            createdAt: now,
            updatedAt: now,
            isPinned: false,
            scopedCarId: pendingScopedCarId,
            messageCount: 0
        )
        pendingScopedCarId = nil
        do {
            try convoRef.setData(from: convo)
        } catch {
            // setData(from:) without a completion only throws on an encoding
            // failure (the write itself is queued locally), so a rejected write
            // is not reported here. Fall through: the in-memory convo still lets
            // the user see their message.
            print("[ChatStore] Couldn't encode the new conversation for saving: \(error.localizedDescription)")
        }
        return (convo, true)
    }

    private func enforceConversationCap(uid: String) async {
        let unpinned = conversations.filter { !$0.isPinned }
        guard unpinned.count >= maxConversations else { return }
        let sorted = unpinned.sorted { $0.updatedAt < $1.updatedAt }
        if let oldest = sorted.first {
            // Automatic, not user-requested: log a failure, never surface it.
            if !(await removeConversation(oldest)) {
                print("[ChatStore] Couldn't auto-delete oldest conversation (FR-10.19)")
            }
        }
    }

    private func attachConversationsListener(uid: String) {
        conversationsListener?.remove()
        conversationsGeneration += 1
        let generation = conversationsGeneration
        conversationsListenerFailed = false
        let convosRef = db.collection("users").document(uid).collection("conversations")
        conversationsListener = convosRef
            .order(by: "updatedAt", descending: true)
            .limit(to: maxConversations + 5)  // slack for auto-delete timing
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.currentUID == uid, self.conversationsGeneration == generation else { return }
                if let error {
                    // Firestore ends a listener after an error. Keep the last list
                    // (display only) and record the failure so
                    // refreshListenersIfNeeded() re-attaches on the next foreground.
                    print("[ChatStore] Conversations listener error: \(error.localizedDescription)")
                    self.conversationsListenerFailed = true
                    return
                }
                guard let snapshot else { return }
                let all = snapshot.documents.compactMap { try? $0.data(as: Conversation.self) }
                // Pinned first, then by updatedAt desc within each group.
                self.conversations = all.sorted { a, b in
                    if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                    return a.updatedAt > b.updatedAt
                }
            }
    }

    private func attachMessagesListener(uid: String, convId: String) {
        messagesListener?.remove()
        messagesGeneration += 1
        let generation = messagesGeneration
        messagesListenerFailedConvId = nil
        let ref = db.collection("users").document(uid)
            .collection("conversations").document(convId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
        messagesListener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, self.currentUID == uid, self.messagesGeneration == generation,
                  self.currentConversation?.id == convId else { return }
            if let error {
                // Firestore ends a listener after an error. Keep the messages on
                // screen and record which conversation lost its listener so
                // refreshListenersIfNeeded() re-attaches it — only while that
                // conversation is still the open one.
                print("[ChatStore] Messages listener error: \(error.localizedDescription)")
                self.messagesListenerFailedConvId = convId
                return
            }
            guard let snap else { return }
            let loaded = snap.documents.compactMap { try? $0.data(as: ChatMessage.self) }
            // Preserve a locally-streaming assistant message not yet persisted.
            let streaming = self.currentMessages.first(where: { $0.isStreaming == true })
            var merged = loaded
            if let streaming, !loaded.contains(where: { $0.id == streaming.id }) {
                merged.append(streaming)
            }
            self.currentMessages = merged
        }
    }

    private func translateSendError(_ error: Error) -> SendError {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return .offline
        }
        if ns.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .resourceExhausted:
                let isPro = serverIsPro == true
                return .capReached(cap: isPro ? Self.proDailyCap : Self.freeDailyCap, isPro: isPro)
            case .unauthenticated:
                return .authRequired
            case .deadlineExceeded:
                return .offline
            case .invalidArgument, .failedPrecondition, .outOfRange:
                return .service(ns.localizedDescription)
            case .notFound, .unavailable, .unimplemented:
                return .service("Marque isn't available right now. Try again in a moment.")
            default:
                return .unknown(ns.localizedDescription)
            }
        }
        return .unknown(ns.localizedDescription)
    }
}

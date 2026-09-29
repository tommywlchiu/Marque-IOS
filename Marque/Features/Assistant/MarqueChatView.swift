import SwiftUI

// The Marque Assistant chat surface. Opens as a bottom sheet at ~90% height
// (FR-10.2). Owns local input state; delegates all message state, streaming,
// and Firestore persistence to ChatStore.
struct MarqueChatView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    // If set, injected on appear via chatStore.newConversation(scopedCarId:).
    // Used when opened from Car Detail (FR-10.3).
    let scopedCarId: String?

    @State private var draft: String = ""
    @State private var showingHistory = false
    @State private var showingPaywall = false
    @State private var didSeeDisclaimer = UserDefaults.standard.bool(forKey: MarqueChatView.disclaimerKey)

    @FocusState private var inputFocused: Bool

    private static let disclaimerKey = "marque_assistant_disclaimer_seen"

    init(scopedCarId: String? = nil) {
        self.scopedCarId = scopedCarId
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if chatStore.isOffline { offlineBanner }
                messageList
                inputArea
            }
            .navigationTitle("Marque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            chatStore.newConversation(scopedCarId: nil)
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        Button {
                            showingHistory = true
                        } label: {
                            Label("Conversations", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ConversationHistoryView()
            }
            .sheet(isPresented: $showingPaywall) {
                ProUpgradeView(trigger: .assistantCap)
                    .environmentObject(subscriptionStore)
            }
            .alert(
                chatStore.sendError?.errorDescription ?? "",
                isPresented: Binding(
                    get: { chatStore.sendError != nil && chatStore.sendError?.isCap != true },
                    set: { if !$0 { chatStore.sendError = nil } }
                )
            ) {
                // draft already holds the restored text by the time this shows
                // (send() restores it synchronously right after the failed await).
                Button("Try Again") {
                    chatStore.sendError = nil
                    retry()
                }
                Button("OK", role: .cancel) { chatStore.sendError = nil }
            }
            .onAppear {
                // Re-attach any listener an error killed (server plan, conversation
                // list, this conversation's messages), so the counter, cap copy and
                // chat below never sit frozen on stale data.
                chatStore.refreshListenersIfNeeded()
                if scopedCarId != nil && chatStore.currentConversation == nil {
                    chatStore.newConversation(scopedCarId: scopedCarId)
                }
            }
            // Keyed off the cap transition rather than capReachedBar.onAppear so
            // reopening the sheet while still capped doesn't re-count.
            .onChange(of: chatStore.sendError?.isCap) { wasCap, isCap in
                if isCap == true && wasCap != true {
                    AnalyticsService.assistantCapReached()
                }
            }
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        if chatStore.currentMessages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !didSeeDisclaimer { disclaimerChip }
                        ForEach(chatStore.currentMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id ?? UUID().uuidString)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: chatStore.currentMessages.last?.content) { _, _ in
                    if let last = chatStore.currentMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatStore.currentMessages.count) { _, _ in
                    if let last = chatStore.currentMessages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("Ask Marque anything about your cars")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Service intervals, common issues, buying advice, help logging maintenance — all with your garage in mind.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !didSeeDisclaimer {
                disclaimerChip
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disclaimerChip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Marque assists but doesn't replace a mechanic.")
                    .font(.footnote).fontWeight(.medium)
                Text("For safety issues, get professional inspection.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                UserDefaults.standard.set(true, forKey: MarqueChatView.disclaimerKey)
                withAnimation { didSeeDisclaimer = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss disclaimer")
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Offline banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.footnote)
            Text("No connection").font(.footnote)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray))
    }

    // MARK: - Input area

    @ViewBuilder
    private var inputArea: some View {
        Divider()
        if chatStore.sendError?.isCap == true {
            capReachedBar
        } else {
            composerBar
        }
    }

    private var composerBar: some View {
        // The counter is a real row above the input, not an overlay: an overlay with
        // negative padding drew it on top of the last message bubble.
        VStack(spacing: 4) {
            // Follows the SERVER's plan (users/{uid}.isPro — what askMarque enforces,
            // FR-08.3), not StoreKit's: a Family Sharing member is Pro locally but
            // capped at the free limit, and a Pro bought on another device is Pro
            // here even if StoreKit says otherwise. Hidden while the plan is unknown.
            if chatStore.serverIsPro == false {
                Text("\(chatStore.todayMessageCount) / \(ChatStore.freeDailyCap) today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your car…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .disabled(chatStore.isSending || chatStore.isOffline)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? .accentColor : .gray)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var capReachedBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundColor(.orange)
                Text("Daily limit reached").font(.subheadline).fontWeight(.medium)
                Spacer()
            }
            if chatStore.serverIsPro == true {
                // A Pro account at the abuse throttle: nothing to upsell.
                Text("You've used all \(ChatStore.proDailyCap) of today's messages. Try again tomorrow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if subscriptionStore.isPro {
                // Pro on this device but the server plan isn't Pro: Family Sharing
                // (the server withholds the flag) or a sync that hasn't landed.
                // "Upgrade" would be wrong; the paywall sheet explains this state.
                Text("Your account is on the free limit of \(ChatStore.freeDailyCap) messages per day, even though this device has Pro. Try again tomorrow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showingPaywall = true
                } label: {
                    Text("About your Pro plan")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                // Free — or plan not yet known, which is treated as free (the server
                // just refused the message, so the free copy is the safe default).
                Text("Free tier is capped at \(ChatStore.freeDailyCap) messages per day. Upgrade to Pro for \(ChatStore.proDailyCap) messages a day, or try again tomorrow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showingPaywall = true
                } label: {
                    Text("Upgrade to Pro")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }

    private var canSend: Bool {
        !chatStore.isSending &&
        !chatStore.isOffline &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        inputFocused = false
        Task {
            await chatStore.sendMessage(text)
            // Restore the user's text on failure so they don't have to retype it
            // (FR-10.14 / EC-19). Not restored on the cap-reached error: that state
            // swaps the composer out for the cap bar entirely, so there's nowhere
            // to put it, and the message that failed was never sent, so it isn't
            // "one of today's messages" to begin with.
            if let error = chatStore.sendError, !error.isCap {
                draft = text
            }
        }
    }

    /// Try Again from the failure alert. When the failed message was already
    /// saved (the usual case: sendMessage writes it before calling the server),
    /// re-ask for that message instead of sending it again, which would show a
    /// duplicate bubble. If it never got saved, fall back to a normal send.
    private func retry() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = chatStore.currentMessages.last, last.role == "user",
              last.content.trimmingCharacters(in: .whitespacesAndNewlines) == text
        else {
            send()
            return
        }
        draft = ""
        Task {
            await chatStore.retryLastFailedMessage()
            if let error = chatStore.sendError, !error.isCap {
                draft = text
            }
        }
    }
}

// MARK: - Message bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 40)
                bubble
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                assistantBubble
                Spacer(minLength: 40)
            }
        }
    }

    /// The assistant answers in light Markdown (**bold**, `code`, "- " lists). Render
    /// the inline styling instead of showing the raw markers. Inline-only parsing
    /// keeps the reply's line breaks; list dashes become bullets and "#" headings
    /// become bold, because Text can't lay out block-level Markdown. Model-written
    /// links lose their tap target — a tappable link inside an AI reply is a
    /// phishing risk, and the visible text is still shown. Assistant messages only:
    /// a user's own typed asterisks must not be interpreted.
    private static func rendered(_ text: String) -> AttributedString {
        // A Text can't draw a horizontal rule, and left alone "---" shows as literal
        // dashes. The blank lines around it already separate the sections, so drop
        // the line (before the bullet rule, which "- - -" would otherwise match).
        var prepared = text.replacingOccurrences(
            of: "(?m)^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$", with: "", options: .regularExpression)
        prepared = prepared.replacingOccurrences(
            of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        prepared = prepared.replacingOccurrences(
            of: "(?m)^([ \\t]*)[-*] ", with: "$1• ", options: .regularExpression)
        prepared = prepared.replacingOccurrences(
            of: "(?m)^#{1,6}[ \\t]+(.+)$", with: "**$1**", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var attributed = try? AttributedString(markdown: prepared, options: options) else {
            return AttributedString(text)
        }
        let linkRanges = attributed.runs.compactMap { $0.link != nil ? $0.range : nil }
        for range in linkRanges { attributed[range].link = nil }
        return attributed
    }

    private var bubble: some View {
        Text(message.content)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.content.isEmpty && message.isStreaming == true {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Marque is thinking…")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(Self.rendered(message.content))
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Conversation history

private struct ConversationHistoryView: View {
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chatStore.conversations.isEmpty {
                    MarqueEmptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: "No Conversations Yet",
                        subtitle: "Your chat history will show up here."
                    )
                } else {
                    List {
                        let pinned = chatStore.conversations.filter { $0.isPinned }
                        let regular = chatStore.conversations.filter { !$0.isPinned }
                        if !pinned.isEmpty {
                            Section("Pinned") {
                                ForEach(pinned) { convo in
                                    row(convo)
                                }
                            }
                        }
                        Section {
                            ForEach(regular) { convo in
                                row(convo)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                chatStore.conversationActionError ?? "",
                isPresented: Binding(
                    get: { chatStore.conversationActionError != nil },
                    set: { if !$0 { chatStore.clearConversationActionError() } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func row(_ convo: Conversation) -> some View {
        Button {
            chatStore.openConversation(convo)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(convo.title.isEmpty ? "New chat" : convo.title)
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(convo.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundColor(.secondary)
                }
                Text("\(convo.messageCount) message\(convo.messageCount == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await chatStore.deleteConversation(convo) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await chatStore.togglePin(convo) }
            } label: {
                Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }
}

// MARK: - Floating "Ask Marque" button

// Compact pill button. Callers position via `.overlay(alignment: .bottomTrailing)`
// so it sits inside the safe area, automatically above the tab bar (FR-10.1).
// Gated on the `marque_assistant_enabled` Remote Config flag (FR-10.22) — the
// button renders nothing when the flag is off, so overlay callers don't need
// to be flag-aware.
struct AskMarqueButton: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var featureFlagsStore: FeatureFlagsStore
    @State private var showingChat = false

    var scopedCarId: String? = nil
    /// Sparkle-only circle instead of the full pill. Driven by
    /// `AskMarqueDock` for its fold/unfold animation.
    var isCollapsed: Bool = false

    var body: some View {
        if featureFlagsStore.assistantEnabled {
            button
        }
    }

    private var button: some View {
        Button {
            if scopedCarId != nil {
                chatStore.newConversation(scopedCarId: scopedCarId)
            }
            showingChat = true
        } label: {
            HStack(spacing: isCollapsed ? 0 : 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                if !isCollapsed {
                    Text("Ask Marque")
                        .font(.subheadline).fontWeight(.semibold)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, isCollapsed ? 10 : 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .sheet(isPresented: $showingChat) {
            MarqueChatView(scopedCarId: scopedCarId)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Tab-switch choreography for the floating button

/// The floating Ask Marque button for a tab root, animated as the user switches
/// tabs. Each tab has its own button instance at the same bottom-trailing spot,
/// so animating the arriving tab's instance reads as one button reacting:
/// - `.present` (Garage): rises out of the tab bar as a spinning sparkle, then
///   unfolds into the "Ask Marque" pill.
/// - `.tuckAway` (Explore): starts as the pill, folds into the sparkle, then
///   spins and sinks into the tab bar and is removed, so it can't be tapped.
/// Reduce Motion gets a plain fade.
struct AskMarqueDock: View {
    enum Mode { case present, tuckAway }
    let mode: Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCollapsed = false
    @State private var isSunk = false
    @State private var isRemoved = false
    /// Bumped on every appearance so a stale sequence from a quick tab
    /// switch back and forth can't finish after a newer one.
    @State private var generation = 0

    var body: some View {
        Group {
            if !isRemoved {
                AskMarqueButton(isCollapsed: isCollapsed)
                    .scaleEffect(isSunk ? 0.25 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(isSunk ? 140 : 0))
                    .offset(y: isSunk ? 70 : 0)
                    .opacity(isSunk ? 0 : 1)
                    .blur(radius: isSunk ? 4 : 0)
                    .allowsHitTesting(!isSunk)
            }
        }
        .onAppear(perform: run)
    }

    private func run() {
        generation += 1
        let token = generation
        switch mode {
        case .present:
            // Start folded and sunk (no animation), then rise and unfold.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { isCollapsed = true; isSunk = true; isRemoved = false }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                guard token == generation else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.72)) {
                    isSunk = false
                }
                try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.28))
                guard token == generation else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isCollapsed = false }
            }
        case .tuckAway:
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { isCollapsed = false; isSunk = false; isRemoved = false }
            Task { @MainActor in
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { isSunk = true }
                } else {
                    try? await Task.sleep(for: .seconds(0.12))
                    guard token == generation else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isCollapsed = true }
                    try? await Task.sleep(for: .seconds(0.22))
                    guard token == generation else { return }
                    withAnimation(.easeIn(duration: 0.32)) { isSunk = true }
                }
                try? await Task.sleep(for: .seconds(0.35))
                guard token == generation else { return }
                isRemoved = true
            }
        }
    }
}

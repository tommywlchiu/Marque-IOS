import Foundation
import FirebaseFirestore

// Metadata document at users/{uid}/conversations/{convId}. Actual messages
// live in the {convId}/messages/ subcollection.
struct Conversation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?

    // Derived from the first user message; used in the conversation list.
    // Falls back to "New chat" until the first message is sent.
    var title: String

    var createdAt: Date
    var updatedAt: Date

    // Pinned conversations are exempt from the FR-10.19 auto-delete cap
    // (50 conversations, up to 10 pinnable).
    var isPinned: Bool

    // Optional scoping. When the user opened the assistant from a Car Detail
    // screen, we tag the conversation with that car so the system prompt can
    // hint the model to prefer it. Nil for global conversations.
    var scopedCarId: String?

    // Denormalized so the conversation list can render "3 messages" without
    // reading the subcollection.
    var messageCount: Int
}

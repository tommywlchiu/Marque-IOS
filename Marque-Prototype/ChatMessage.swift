import Foundation
import FirebaseFirestore

// One message in a Marque Assistant conversation. Persisted at
// users/{uid}/conversations/{convId}/messages/{msgId}. The Cloud Function
// does NOT write these — the iOS client owns chat persistence and writes
// the user message before the call and the assembled assistant message
// after streaming ends. This keeps the function stateless and lets us
// avoid an extra Firestore round-trip per delta.
struct ChatMessage: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var role: String            // "user" or "assistant"
    var content: String
    var createdAt: Date

    // Assistant-only telemetry copied off the function's return value.
    // Useful for cost attribution in Firestore console and for future
    // per-message analytics without a separate collection.
    var model: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?

    // Local-only flag: true while the assistant response is streaming.
    // Not written to Firestore.
    var isStreaming: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt
        case model, inputTokens, outputTokens, cacheReadTokens
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: "user", content: text, createdAt: Date())
    }

    static func assistantPlaceholder() -> ChatMessage {
        var m = ChatMessage(role: "assistant", content: "", createdAt: Date())
        m.isStreaming = true
        return m
    }
}

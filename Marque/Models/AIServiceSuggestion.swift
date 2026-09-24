import Foundation

// AI-generated service suggestion. Parallel shape to ServiceReminder plus the
// two things the model adds on top: a `reasoning` sentence explaining WHY
// the suggestion applies to this specific car, and a `priority` label so the
// UI can badge urgency.
//
// The `id` is stable per instance (fixed once at init) so SwiftUI selection
// state and .task caches don't churn between renders — same lesson we
// learned from the rule-engine suggestions bug.
struct AIServiceSuggestion: Identifiable, Sendable {
    let id: UUID
    let serviceType: String
    let dueDate: Date?
    let dueMileage: Int?
    let reasoning: String
    let priority: Priority

    enum Priority: String, Sendable {
        case high, medium, low

        var sortOrder: Int {
            switch self {
            case .high: return 0
            case .medium: return 1
            case .low: return 2
            }
        }
    }

    // Standard init — AI-sourced suggestions get a fresh UUID.
    init(serviceType: String, dueDate: Date?, dueMileage: Int?, reasoning: String, priority: Priority) {
        self.id = UUID()
        self.serviceType = serviceType
        self.dueDate = dueDate
        self.dueMileage = dueMileage
        self.reasoning = reasoning
        self.priority = priority
    }

    // Fallback init from the rule-based engine. Reuses the source reminder's
    // UUID so selection state can survive if we later re-render from the same
    // fallback list.
    init(fallbackFrom reminder: ServiceReminder) {
        self.id = reminder.id
        self.serviceType = reminder.serviceType
        self.dueDate = reminder.dueDate
        self.dueMileage = reminder.dueMileage
        self.reasoning = ""
        self.priority = .medium
    }

    // Convert to a persistable ServiceReminder. Reasoning is preserved in the
    // reminder's `notes` field so the WHY isn't lost after the user accepts.
    func asReminder() -> ServiceReminder {
        ServiceReminder(
            serviceType: serviceType,
            notes: reasoning,
            dueDate: dueDate,
            dueMileage: dueMileage
        )
    }
}

import SwiftUI

// Shared visual language for the owner's editable car sections, extracted
// from CarDetailView so the car page and the Garage's focused screens match:
//  - `AddSectionHeader`: list-type sections (Reminders, Maintenance) — always
//    shows a "+" so the user can add more.
//  - `EditableSectionHeader`: single-record sections (Registration,
//    Insurance, Vehicle Details) — only shows a pencil when there's data to
//    edit; otherwise the empty state IS the entry point.
//  - `EmptySectionRow`: the inline empty-state button used inside a Section
//    body when there are no records yet.

struct AddSectionHeader: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill").font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(title.lowercased())")
        }
    }
}

struct EditableSectionHeader: View {
    let title: String
    let hasData: Bool
    let onEdit: () -> Void

    var body: some View {
        if hasData {
            HStack {
                Text(title)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill").font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(title.lowercased())")
            }
        } else {
            Text(title)
        }
    }
}

struct EmptySectionRow: View {
    let title: String
    var systemImage: String = "plus.circle"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundColor(.accentColor)
        }
    }
}

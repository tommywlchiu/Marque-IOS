import SwiftUI

/// FR-15.7 / GDPR Art. 20: a complete, machine-readable (JSON) copy of the
/// user's account data. Its own Settings row rather than part of
/// `DataExportView`, because that screen is about cars and shows only an
/// empty state when the garage is empty, and every user must be able to get
/// their data. The file is produced by `AccountExportService` and handed to
/// the share sheet; the app never sends it anywhere itself (FR-15.6).
struct AccountDataExportView: View {
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var exportedFile: ExportedFile?

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Everything Marque stores about your account, in one JSON file: your profile, cars, service history, mods, Assistant conversations, follows, likes, comments and notification settings.")
                    Text("Photos and sound clips are listed by name, not included. Driver license details stored only on this device are added from this device.")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }

            if let errorMessage {
                Section {
                    MarqueErrorBanner(message: errorMessage)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    export()
                } label: {
                    HStack {
                        Label("Download My Data", systemImage: "arrow.down.doc")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
                .accessibilityHint("Prepares a JSON file of your account data and opens the share sheet")
            } footer: {
                Text("This can take a moment for large accounts. Limited to 5 downloads a day.")
            }
        }
        .navigationTitle("Download My Account Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ActivityShareSheet(activityItems: [file.url])
        }
    }

    private func export() {
        errorMessage = nil
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                exportedFile = ExportedFile(url: try await AccountExportService.exportAccountData())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

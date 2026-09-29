import SwiftUI

/// Owner's "Engine Sound" section on their car page: add, preview,
/// re-record or remove the clip. Lives inside `CarDetailView`'s List.
struct EngineSoundOwnerSection: View {
    let car: Car

    @EnvironmentObject private var carStore: CarStore
    @StateObject private var player = EngineSoundPlayer()
    @State private var showingRecorder = false
    @State private var showingRemoveConfirmation = false

    private var hasClip: Bool {
        car.engineSoundFileName != nil || !(car.engineSoundURL ?? "").isEmpty
    }

    /// Local file first (instant, works offline), then the uploaded copy.
    private var playbackURL: URL? {
        if let local = carStore.localEngineSoundURL(for: car) { return local }
        if let remote = car.engineSoundURL, !remote.isEmpty { return URL(string: remote) }
        return nil
    }

    var body: some View {
        // Presenters hang off the header: it's the one view that exists in
        // both states, so a sheet isn't torn down when the rows swap.
        Section(header: Text("Engine Sound").modifier(presenters)) {
            if hasClip {
                clipRow
                Button {
                    player.stop()
                    showingRecorder = true
                } label: {
                    Label("Re-record", systemImage: "mic")
                }
                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("Remove Sound", systemImage: "trash")
                        .foregroundColor(.red)
                }
            } else {
                Button {
                    showingRecorder = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Engine Sound")
                                .foregroundColor(.accentColor)
                            Text("Record up to 5 seconds of your engine")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // Attached to exactly one view (the header): modifiers on a List Section
    // can apply to every row, which would stack duplicate presenters on one binding.
    private var presenters: EngineSoundOwnerPresenters {
        EngineSoundOwnerPresenters(
            carID: car.id,
            isPublic: car.isPublic,
            showingRecorder: $showingRecorder,
            showingRemoveConfirmation: $showingRemoveConfirmation,
            onRemove: {
                player.stop()
                if let current = carStore.cars.first(where: { $0.id == car.id }) {
                    carStore.removeEngineSound(for: current)
                }
            }
        )
    }

    private var clipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = playbackURL {
                EngineSoundCapsule(
                    isPlaying: player.isPlaying,
                    isLoading: player.isLoading,
                    progress: player.progress,
                    duration: car.engineSoundDuration ?? player.duration,
                    failed: player.failed
                ) {
                    player.toggle(url: url)
                }
            }
            statusCaption
        }
        .padding(.vertical, 4)
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var statusCaption: some View {
        if (car.engineSoundURL ?? "").isEmpty {
            Label(car.isPublic ? "Uploading… it will appear on your public car page shortly" : "Uploading…",
                  systemImage: "icloud.and.arrow.up")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if car.isPublic {
            Label("Anyone viewing this car in Explore can play it", systemImage: "globe")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Label("Only you can hear it while this car is private", systemImage: "lock")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct EngineSoundOwnerPresenters: ViewModifier {
    let carID: UUID
    let isPublic: Bool
    @Binding var showingRecorder: Bool
    @Binding var showingRemoveConfirmation: Bool
    let onRemove: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingRecorder) {
                EngineSoundRecorderSheet(carID: carID)
            }
            .confirmationDialog("Remove engine sound?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
                Button("Remove Sound", role: .destructive, action: onRemove)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isPublic ? "It will also be removed from your public car page." : "You can record a new one any time.")
            }
    }
}

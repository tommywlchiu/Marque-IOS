import SwiftUI
import PhotosUI
import Photos

/// Photos tab: every car's photos, grouped by car. Mirrors the photo-add/
/// -remove/-cover mutations Views/EditCarDetailView.swift already performs
/// against CarStore (updateCar + uploadPhotos + ImageManager) rather than
/// introducing a second way to edit a car's photos, and reuses
/// Features/Garage/PhotoGalleryView.swift for the full-screen swipe viewer.
struct PhotosTabView: View {
    @EnvironmentObject var carStore: CarStore

    @State private var viewerTarget: PhotoViewerTarget?
    @State private var reorderingCar: Car?
    @State private var pendingDelete: PendingPhotoDelete?

    private let gridColumns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if carStore.cars.isEmpty {
                    MarqueEmptyState(
                        icon: "car.fill",
                        title: "Add a Car First",
                        subtitle: "Once you add a car to your garage, its photos will show up here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(carStore.cars) { car in
                                carSection(for: car)
                                if car.id != carStore.cars.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $viewerTarget) { target in
                let car = liveCar(for: target.carID) ?? target.fallbackCar
                PhotoGalleryView(
                    photoFileNames: car.photoFileNames,
                    photoStorageURLs: car.photoStorageURLs,
                    initialIndex: target.index,
                    onSetCover: { index in
                        guard let current = liveCar(for: target.carID),
                              index < current.photoFileNames.count else { return }
                        carStore.setCoverPhoto(fileName: current.photoFileNames[index], for: current)
                    }
                )
            }
            .sheet(item: $reorderingCar) { car in
                ReorderPhotosSheet(car: car) { reordered in
                    applyReorder(reordered, to: car)
                }
            }
            .confirmationDialog(
                "Delete Photo",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { target in
                Button("Delete Photo", role: .destructive) { delete(target.fileName, from: target.carID) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This will permanently remove the photo.")
            }
        }
    }

    private func liveCar(for id: UUID) -> Car? {
        carStore.cars.first(where: { $0.id == id })
    }

    // MARK: - Per-car section

    @ViewBuilder
    private func carSection(for car: Car) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(car.displayName)
                        .font(.headline)
                    Text("\(car.photoFileNames.count) photo\(car.photoFileNames.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if car.photoFileNames.count > 1 {
                    Button {
                        reorderingCar = car
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.title3)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Reorder \(car.displayName)'s photos")
                }
                AddPhotosButton(car: car) { images in
                    await addPhotos(images, to: car)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)

            if car.photoFileNames.isEmpty {
                AddPhotosButton(car: car) { images in
                    await addPhotos(images, to: car)
                } label: {
                    addPhotosTileLabel
                }
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(Array(car.photoFileNames.enumerated()), id: \.element) { index, fileName in
                        thumbnail(fileName: fileName, index: index, car: car)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    private var addPhotosTileLabel: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)
            Text("Add Photos")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        )
    }

    @ViewBuilder
    private func thumbnail(fileName: String, index: Int, car: Car) -> some View {
        let isCover = index == 0

        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    CarPhotoImage(fileName: fileName, storageURL: car.storageURL(at: index))
                        .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if isCover {
                Text("Cover")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            viewerTarget = PhotoViewerTarget(carID: car.id, fallbackCar: car, index: index)
        }
        .contextMenu {
            if !isCover {
                Button {
                    carStore.setCoverPhoto(fileName: fileName, for: car)
                } label: {
                    Label("Set as Cover", systemImage: "star")
                }
            }
            Button(role: .destructive) {
                pendingDelete = PendingPhotoDelete(carID: car.id, fileName: fileName)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(isCover ? "Cover photo, photo \(index + 1) of \(car.photoFileNames.count)" : "Photo \(index + 1) of \(car.photoFileNames.count)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Mutations
    //
    // These three mirror EditCarDetailView's commitPhotoChanges/saveCar and
    // CarDetailView's galleryViewer/setCoverPhoto call sites exactly: they go
    // through CarStore.updateCar + CarStore.uploadPhotos + ImageManager, the
    // same public surface those screens use — nothing here talks to Firestore
    // or Storage directly.

    private func addPhotos(_ images: [UIImage], to car: Car) async {
        guard let current = liveCar(for: car.id), !images.isEmpty else { return }
        var updated = current
        var newPhotos: [(fileName: String, image: UIImage)] = []
        for image in images {
            let name = ImageManager.generateFileName()
            ImageManager.saveImage(image, fileName: name)
            updated.photoFileNames.append(name)
            updated.photoStorageURLs.append("")
            newPhotos.append((fileName: name, image: image))
        }
        carStore.updateCar(updated)
        carStore.uploadPhotos(newPhotos, removingFileNames: [], for: updated)
        for _ in newPhotos { AnalyticsService.carPhotoAdded() }
    }

    private func delete(_ fileName: String, from carID: UUID) {
        guard let current = liveCar(for: carID) else { return }
        ImageManager.deleteImage(fileName: fileName)
        var updated = current
        if let idx = updated.photoFileNames.firstIndex(of: fileName) {
            updated.photoFileNames.remove(at: idx)
            if idx < updated.photoStorageURLs.count {
                updated.photoStorageURLs.remove(at: idx)
            }
        }
        carStore.updateCar(updated)
        carStore.uploadPhotos([], removingFileNames: [fileName], for: updated)
    }

    private func applyReorder(_ orderedFileNames: [String], to original: Car) {
        guard let current = liveCar(for: original.id) else { return }
        var updated = current
        let urlByName = Dictionary(
            zip(current.photoFileNames, current.photoStorageURLs),
            uniquingKeysWith: { first, _ in first }
        )
        updated.photoFileNames = orderedFileNames
        updated.photoStorageURLs = orderedFileNames.map { urlByName[$0] ?? "" }
        // The cover may have changed; reset the crop like CarStore.setCoverPhoto does.
        updated.photoOffsetY = 0
        carStore.updateCar(updated)
    }
}

// MARK: - Identifiable sheet/dialog targets

private struct PhotoViewerTarget: Identifiable {
    let id = UUID()
    let carID: UUID
    /// Used only if the car has since been deleted out from under an open
    /// viewer; the live lookup in `liveCar(for:)` is preferred whenever possible.
    let fallbackCar: Car
    let index: Int
}

private struct PendingPhotoDelete: Identifiable {
    let id = UUID()
    let carID: UUID
    let fileName: String
}

// MARK: - Add Photos control
//
// Mirrors EditCarDetailView's PhotoPickerPresenters permission flow exactly
// (PHPhotoLibrary.authorizationStatus → request → PhotosPicker), generic over
// its label so the same permission/picker logic backs both the small
// trailing "+" button and the big empty-state tile.
private struct AddPhotosButton<Label: View>: View {
    let car: Car
    let onPicked: ([UIImage]) async -> Void
    @ViewBuilder let label: () -> Label

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingPicker = false
    @State private var showingPermissionDenied = false
    @State private var isLoading = false

    var body: some View {
        Button {
            requestPhotoPermission()
        } label: {
            if isLoading {
                ProgressView()
            } else {
                label()
            }
        }
        .disabled(isLoading)
        .accessibilityLabel("Add photos to \(car.displayName)")
        .alert("Photo Access Required", isPresented: $showingPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To add car photos, allow Marque to access your photo library in Settings > Privacy > Photos.")
        }
        .photosPicker(
            isPresented: $showingPicker,
            selection: $selectedItems,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                isLoading = true
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                selectedItems = []
                await onPicked(images)
                isLoading = false
            }
        }
    }

    private func requestPhotoPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showingPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized, .limited: showingPicker = true
                    default: showingPermissionDenied = true
                    }
                }
            }
        default:
            showingPermissionDenied = true
        }
    }
}

// MARK: - Reorder sheet

/// Drag-to-reorder via a standard `List`/`onMove` (forced into edit mode —
/// there's nothing else in this sheet to edit), rather than custom drag-and-
/// drop on the grid itself. Persists through the same `CarStore.updateCar`
/// every other photo mutation here uses; CarStore has no separate "reorder"
/// API because none is needed — the full Car document, including photo
/// order, is just written back via `updateCar`.
private struct ReorderPhotosSheet: View {
    let car: Car
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var names: [String]

    init(car: Car, onSave: @escaping ([String]) -> Void) {
        self.car = car
        self.onSave = onSave
        self._names = State(initialValue: car.photoFileNames)
    }

    private var urlByName: [String: String] {
        Dictionary(zip(car.photoFileNames, car.photoStorageURLs), uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    HStack(spacing: 12) {
                        Color.clear
                            .frame(width: 48, height: 48)
                            .overlay(
                                CarPhotoImage(fileName: name, storageURL: resolvedURL(for: name))
                                    .clipped()
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(index == 0 ? "Cover Photo" : "Photo \(index + 1)")
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { indices, newOffset in
                    names.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(names)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func resolvedURL(for name: String) -> URL? {
        guard let str = urlByName[name], !str.isEmpty else { return nil }
        return URL(string: str)
    }
}

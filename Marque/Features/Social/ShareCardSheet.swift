import SwiftUI

/// "Share my car" sheet: Post/Story picker with a live preview of
/// `CarShareCard`, then renders it to an exact-pixel JPEG via `ImageRenderer`
/// and hands it to the standard iOS share sheet. Reuses `ActivityShareSheet`
/// (Features/Settings/DataExportView.swift) rather than a second wrapper.
///
/// Privacy boundary: this view only ever holds a `PublicCar` (FR-06.3's
/// public projection), never a `Car`, so it cannot leak VIN/plate/insurance/
/// exact value/private notes even for the owner's own car — see
/// `CarDetailView`, which builds that projection before presenting this
/// sheet.
struct ShareCardSheet: View {
    let car: PublicCar
    /// Cover photo source for the OWNER'S OWN car — a local filename loaded
    /// via `ImageManager` (no network round-trip). nil when viewing someone
    /// else's public car, where the cover comes from `car`'s Storage URL
    /// instead (see `loadCoverImageIfNeeded`).
    let localCoverPhotoFileName: String?
    /// Share text reads "Check out my ..." for the owner, "Check out this
    /// ..." for a viewer.
    let isOwnCar: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var format: ShareCardFormat = .post
    @State private var coverImage: UIImage?
    @State private var isLoadingPhoto = true
    @State private var isPreparingShare = false
    @State private var pendingShare: PendingShare?
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                preview
                formatPicker
                if let shareError {
                    MarqueErrorBanner(message: shareError)
                        .padding(.horizontal)
                }
                MarquePrimaryButton("Share", isLoading: isPreparingShare) {
                    Task { await prepareAndShare() }
                }
                .padding(.horizontal)
                .disabled(isLoadingPhoto)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
            .navigationTitle("Share Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await loadCoverImageIfNeeded() }
        .sheet(item: $pendingShare) { share in
            ActivityShareSheet(activityItems: [share.url, share.text])
        }
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { geo in
            let scale = geo.size.width / format.pixelSize.width
            ZStack {
                CarShareCard(car: car, coverImage: coverImage, format: format)
                    .frame(width: format.pixelSize.width, height: format.pixelSize.height)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)

                if isLoadingPhoto {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .aspectRatio(format.pixelSize.width / format.pixelSize.height, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share card preview of \(car.displayName), \(format.displayName) format")
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(ShareCardFormat.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .accessibilityLabel("Share card format")
    }

    // MARK: - Cover photo

    /// `ImageRenderer` can't await `AsyncImage`-style loads, so the cover
    /// photo has to be a `UIImage` in hand before rendering. Own car: the
    /// local file via `ImageManager` (fast, no network). Someone else's car:
    /// download the Storage URL, through the shared `MarqueImageCache` so a
    /// photo already seen in Explore doesn't re-download. A failed/missing
    /// photo leaves `coverImage` nil — `CarShareCard` falls back to its
    /// placeholder design rather than blocking the share.
    private func loadCoverImageIfNeeded() async {
        defer { isLoadingPhoto = false }

        if let fileName = localCoverPhotoFileName, let image = ImageManager.loadImage(fileName: fileName) {
            coverImage = image
            return
        }

        guard let url = car.primaryPhotoURL ?? car.galleryURLs.first else { return }

        if let cached = MarqueImageCache.shared.get(url) {
            coverImage = cached
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let downloaded = UIImage(data: data) else { return }
        MarqueImageCache.shared.set(downloaded, for: url)
        coverImage = downloaded
    }

    // MARK: - Render + share

    private func prepareAndShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        shareError = nil
        defer { isPreparingShare = false }

        guard let image = renderCardImage(),
              let jpegData = image.jpegData(compressionQuality: 0.9) else {
            shareError = "Couldn't create the share image. Please try again."
            return
        }

        // Named after the car ("2024-audi-a5-marque.jpg"): it's what people
        // see when they save or AirDrop it.
        let slug = car.displayName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(slug.isEmpty ? "car" : slug)-marque.jpg")
        do {
            try jpegData.write(to: fileURL, options: .atomic)
        } catch {
            shareError = "Couldn't create the share image. Please try again."
            return
        }

        let text = isOwnCar
            ? "Check out my \(car.displayName) on Marque \(AppLinks.website.absoluteString)"
            : "Check out this \(car.displayName) on Marque \(AppLinks.website.absoluteString)"
        pendingShare = PendingShare(url: fileURL, text: text)
    }

    /// Renders the exact view shown in `preview`, at its true pixel size
    /// (scale 1 — the view's own frame is already set to `format.pixelSize`
    /// in points, so this maps 1:1 to pixels; see `ShareCardFormat`).
    @MainActor
    private func renderCardImage() -> UIImage? {
        let renderer = ImageRenderer(content: CarShareCard(car: car, coverImage: coverImage, format: format))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(format.pixelSize)
        return renderer.uiImage
    }
}

private struct PendingShare: Identifiable {
    let url: URL
    let text: String
    var id: URL { url }
}

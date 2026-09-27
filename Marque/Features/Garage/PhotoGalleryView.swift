import SwiftUI

// Full-screen, swipeable photo viewer. Normally backed by a car's local
// `photoFileNames`, but a public car (`CarDetailView(publicCar:)`) has no local
// files -- it only carries `photoStorageURLs` (Firebase Storage download URLs,
// stripped of everything else per FR-06.3). `pageCount` -- not photoFileNames.count
// -- drives both the empty check and index clamping so that path renders instead
// of falling through to "No photos to display".
struct PhotoGalleryView: View {
    let photoFileNames: [String]
    let photoStorageURLs: [String]
    let initialIndex: Int
    /// Own car only: makes the photo at this index the cover. nil hides the
    /// control (public cars, which the viewer can't edit).
    var onSetCover: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    /// The photo just made the cover, followed across the reorder so the
    /// viewer stays on it instead of jumping to whatever now sits at its old index.
    @State private var pendingCoverFileName: String?
    @State private var showCoverConfirmation = false

    private var pageCount: Int { max(photoFileNames.count, photoStorageURLs.count) }

    init(
        photoFileNames: [String],
        photoStorageURLs: [String] = [],
        initialIndex: Int = 0,
        onSetCover: ((Int) -> Void)? = nil
    ) {
        self.photoFileNames = photoFileNames
        self.photoStorageURLs = photoStorageURLs
        self.initialIndex = initialIndex
        self.onSetCover = onSetCover
        let count = max(photoFileNames.count, photoStorageURLs.count)
        _currentIndex = State(initialValue: count > 0 ? max(0, min(initialIndex, count - 1)) : 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if pageCount == 0 {
                emptyState
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        let fileName = index < photoFileNames.count ? photoFileNames[index] : ""
                        let urlStr = index < photoStorageURLs.count ? photoStorageURLs[index] : ""
                        let storageURL = urlStr.isEmpty ? nil : URL(string: urlStr)
                        ZoomablePhotoView(fileName: fileName, storageURL: storageURL)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                    }
                    Spacer()

                    VStack(spacing: 12) {
                        if onSetCover != nil && pageCount > 1 {
                            coverControl
                        }
                        if pageCount > 1 {
                            Text("\(currentIndex + 1) of \(pageCount)")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .statusBarHidden()
        .onChange(of: photoFileNames) { _, newNames in
            guard let name = pendingCoverFileName, let index = newNames.firstIndex(of: name) else { return }
            pendingCoverFileName = nil
            // No page-slide animation: the same photo stays on screen, it just
            // becomes number 1.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { currentIndex = index }
        }
    }

    @ViewBuilder
    private var coverControl: some View {
        if currentIndex == 0 {
            Label(showCoverConfirmation ? "Cover photo updated" : "Cover photo", systemImage: "star.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.accentColor))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            Button {
                guard currentIndex < photoFileNames.count else { return }
                pendingCoverFileName = photoFileNames[currentIndex]
                onSetCover?(currentIndex)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.2)) { showCoverConfirmation = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation { showCoverConfirmation = false }
                }
            } label: {
                Label("Set as Cover", systemImage: "star")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
            .transition(.opacity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.5))
            Text("No photos to display")
                .foregroundColor(.white.opacity(0.7))

            Button("Close") { dismiss() }
                .foregroundColor(.white)
                .padding(.top, 8)
        }
    }
}

// One page of the gallery. Loads from disk (off-main, downsampled to screen size
// via LocalPhotoLoader) and supports pinch-to-zoom and pan. A public car has no
// local fileName, so it falls straight to the storageURL branch.
private struct ZoomablePhotoView: View {
    let fileName: String
    let storageURL: URL?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture)
                        .simultaneousGesture(scale > 1 ? panGesture : nil)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if scale > 1 {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(fileName)|\(Int(geo.size.width))x\(Int(geo.size.height))") {
                // Full-size gallery page: decode at screen resolution, not thumbnail size.
                await load(pixelSize: max(geo.size.width, geo.size.height) * displayScale)
            }
        }
    }

    private func load(pixelSize: CGFloat) async {
        guard pixelSize > 0 else { return }
        if let cached = LocalPhotoLoader.cachedImage(fileName: fileName, pixelSize: pixelSize) {
            image = cached
            return
        }
        if let local = await LocalPhotoLoader.load(fileName: fileName, pixelSize: pixelSize) {
            image = local
            return
        }
        guard let storageURL else { return }
        if let cached = MarqueImageCache.shared.get(storageURL) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: storageURL),
              let downloaded = UIImage(data: data) else { return }
        MarqueImageCache.shared.set(downloaded, for: storageURL)
        image = downloaded
        if !fileName.isEmpty {
            Task.detached(priority: .utility) {
                ImageManager.saveImage(downloaded, fileName: fileName)
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, min(5, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

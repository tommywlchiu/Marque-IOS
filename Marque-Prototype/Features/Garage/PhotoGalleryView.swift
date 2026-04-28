import SwiftUI

// Full-screen, swipeable photo viewer for a car's `photoFileNames`.
// Read-only — editing (reorder, delete, set primary) lives in EditCarDetailView.
struct PhotoGalleryView: View {
    let photoFileNames: [String]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photoFileNames: [String], initialIndex: Int = 0) {
        self.photoFileNames = photoFileNames
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: max(0, min(initialIndex, photoFileNames.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photoFileNames.isEmpty {
                emptyState
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(photoFileNames.enumerated()), id: \.offset) { index, fileName in
                        ZoomablePhotoView(fileName: fileName)
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

                    if photoFileNames.count > 1 {
                        Text("\(currentIndex + 1) of \(photoFileNames.count)")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .statusBarHidden()
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

// One page of the gallery. Loads from disk and supports pinch-to-zoom and pan.
private struct ZoomablePhotoView: View {
    let fileName: String

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
        }
        .onAppear { image = ImageManager.loadImage(fileName: fileName) }
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

#Preview {
    PhotoGalleryView(photoFileNames: [], initialIndex: 0)
}

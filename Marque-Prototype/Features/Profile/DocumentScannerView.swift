import SwiftUI
import VisionKit

// SwiftUI wrapper around VNDocumentCameraViewController — the same scanner
// Notes.app uses for "Scan Documents." Provides live edge detection,
// auto-framing, auto-capture, and perspective correction out of the box.
//
// We pass the first scanned page (already perspective-corrected) to the
// onScan callback. The scanner supports multi-page captures, but for a
// driver's license we only need a single page.
//
// Note: VNDocumentCameraViewController requires a physical camera and will
// not run in the iOS Simulator. Check `VNDocumentCameraViewController.isSupported`
// before presenting to fall back gracefully on simulator/iPad without camera.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onError: onError)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: (UIImage) -> Void
        private let onCancel: () -> Void
        private let onError: (Error) -> Void

        init(
            onScan: @escaping (UIImage) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            // Take the first page only — a driver's license fits on one side.
            onScan(scan.imageOfPage(at: 0))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onError(error)
        }
    }
}

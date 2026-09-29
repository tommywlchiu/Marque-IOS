import SwiftUI
import AVFoundation

/// The one serial queue for engine-sound audio work: `AVAudioSession`
/// category/activation and the recorder's AVFoundation calls. These can make
/// synchronous XPC calls that block (indefinitely, when the Simulator waits
/// on macOS mic access), so they must never run on the main thread. Serial,
/// so a player's deactivation can't land between a recorder's activation
/// and its start.
enum EngineAudioQueue {
    static let queue = DispatchQueue(label: "com.tommychiu.marque.engine-audio", qos: .userInitiated)

    static func activatePlayback() {
        queue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                print("[EngineAudio] Playback session error: \(error.localizedDescription)")
            }
        }
    }

    static func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// View-local playback for an engine sound clip: a local file (the owner's
/// own clip) or a Storage download URL (streamed). One clip at a time.
/// Activates a `.playback` audio session while playing and deactivates it
/// (letting other audio resume) when playback ends or stops; both on
/// `EngineAudioQueue`, off the main thread.
@MainActor
final class EngineSoundPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    /// 0...1 through the clip while playing.
    @Published private(set) var progress: Double = 0
    /// Known once the item is ready (streamed clips don't carry a duration).
    @Published private(set) var duration: Double?
    @Published private(set) var failed = false

    private var player: AVPlayer?
    private var currentURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    func toggle(url: URL) {
        if isPlaying, currentURL == url {
            stop()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        stop()
        failed = false
        EngineAudioQueue.activatePlayback()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        currentURL = url
        isLoading = true
        isPlaying = true
        progress = 0

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            Task { @MainActor [weak self] in
                guard let self, self.player?.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                case .failed:
                    self.failed = true
                    self.stop()
                default:
                    break
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                let total = item.duration.seconds
                guard total.isFinite, total > 0 else { return }
                self.isLoading = false
                self.duration = total
                self.progress = min(1, max(0, time.seconds / total))
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player.play()
    }

    func stop() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        let wasActive = player != nil
        player?.pause()
        player = nil
        currentURL = nil
        isPlaying = false
        isLoading = false
        progress = 0
        if wasActive {
            EngineAudioQueue.deactivate()
        }
    }
}

/// "Engine sound · 5s" capsule with a play/stop control and a static
/// waveform that fills as the clip plays.
struct EngineSoundCapsule: View {
    let isPlaying: Bool
    let isLoading: Bool
    let progress: Double
    /// Seconds, if known.
    let duration: Double?
    var failed = false
    let action: () -> Void

    // Fixed pseudo-waveform: engine clips don't need a real envelope here.
    private static let bars: [CGFloat] = [
        0.35, 0.55, 0.8, 0.6, 0.95, 0.7, 0.5, 0.85, 1.0, 0.65, 0.45, 0.75,
        0.9, 0.6, 0.4, 0.7, 0.85, 0.55, 0.35, 0.5,
    ]

    private var titleText: String {
        guard let duration, duration > 0 else { return "Engine sound" }
        return "Engine sound · \(Int(duration.rounded()))s"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor)
                    if isLoading {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if failed {
                        Text("Couldn't play this clip")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        waveform
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .background(Capsule().fill(Color.accentColor.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titleText)
        .accessibilityHint(isPlaying ? "Double-tap to stop" : "Double-tap to play")
        .accessibilityAddTraits(.startsMediaSession)
    }

    private var waveform: some View {
        let bars = Self.bars
        let filled = Int((progress * Double(bars.count)).rounded(.down))
        return HStack(alignment: .center, spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(isPlaying && i <= filled ? Color.accentColor : Color.accentColor.opacity(0.3))
                    .frame(width: 3, height: 4 + 12 * bars[i])
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

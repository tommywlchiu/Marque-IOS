import SwiftUI
import AVFoundation

/// Records a short engine clip: AAC .m4a, mono, 44.1 kHz, 64 kbps, which
/// keeps a 5 s clip around 40 KB, far under `CarStore.maxEngineSoundBytes`.
/// Stops itself at `maxDuration`.
///
/// Threading: every AVFoundation call (session category/activation, recorder
/// creation, prepare/record/stop, metering) runs on `EngineAudioQueue.queue`,
/// never on the main actor. `prepareToRecord()` makes a synchronous audio XPC
/// call that can block indefinitely (seen on the Simulator waiting on macOS
/// mic access), which froze the whole app when it ran on main. Published
/// state is only touched on the main actor. Being one serial queue, a stop
/// or cancel is ordered after the start it follows.
@MainActor
final class EngineSoundRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Phase: Equatable {
        case idle
        /// Session activation + prepare/record in flight on the audio queue.
        case starting
        case recording
        case recorded(url: URL, duration: Double)
    }

    static let maxDuration: TimeInterval = 5.0
    static let minDuration: TimeInterval = 1.0
    static let meterHistory = 28
    /// A start that hasn't produced a running recorder by then has failed.
    static let startTimeout: Duration = .seconds(3)
    /// A running recorder that hasn't captured any audio by then has failed.
    static let firstAudioTimeout: Duration = .milliseconds(1500)

    static let micUnavailableMessage =
        "Couldn't access the microphone. Check Settings \u{2192} Privacy \u{2192} Microphone."

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent normalized input levels (0...1), oldest first.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: EngineSoundRecorder.meterHistory)
    @Published var errorMessage: String?

    /// Owned by the audio queue: created, used and released only there.
    private let box = RecorderBox()
    private var meterTimer: Timer?
    private var meterSampleInFlight = false
    private var fileURL: URL?
    /// Identifies the current attempt, so a late result from an abandoned
    /// one (timed out, cancelled, reset) is ignored.
    private var attempt = UUID()
    /// True once the recorder has actually captured audio.
    private var receivedAudio = false

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    /// Starts recording without blocking the main thread. Never fails
    /// silently: every failure path ends in `.idle` with `errorMessage` set.
    func start() {
        guard phase == .idle else { return }
        discardFile()
        errorMessage = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-\(UUID().uuidString).m4a")
        fileURL = url
        elapsed = 0
        levels = Array(repeating: 0, count: Self.meterHistory)
        receivedAudio = false
        let token = UUID()
        attempt = token
        phase = .starting

        // Watchdog: the audio queue may be stuck inside prepareToRecord().
        // The UI gives up and stays usable; the queue's late result is dropped.
        Task { [weak self] in
            try? await Task.sleep(for: Self.startTimeout)
            guard let self, self.attempt == token, self.phase == .starting else { return }
            self.fail(Self.micUnavailableMessage)
        }

        let box = self.box
        let settings = Self.settings
        let maxDuration = Self.maxDuration
        EngineAudioQueue.queue.async { [weak self] in
            var started = false
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try session.setActive(true)
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                box.recorder = recorder
                box.token = token
                started = recorder.prepareToRecord() && recorder.record(forDuration: maxDuration)
            } catch {
                started = false
            }
            if !started { box.tearDown() }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.attempt == token, self.phase == .starting else {
                    // Abandoned meanwhile; make sure nothing is left running.
                    EngineAudioQueue.queue.async { if box.token == token { box.tearDown() } }
                    return
                }
                guard started else {
                    self.fail(Self.micUnavailableMessage)
                    return
                }
                self.phase = .recording
                self.startMetering()
                try? await Task.sleep(for: Self.firstAudioTimeout)
                guard self.attempt == token, self.phase == .recording, !self.receivedAudio else { return }
                self.fail("No audio is reaching the microphone. Check Settings \u{2192} Privacy \u{2192} Microphone, then try again.")
            }
        }
    }

    /// Stops early (the recorder also stops itself at `maxDuration`). The
    /// delegate then finishes the take.
    func stop() {
        guard phase == .recording else { return }
        let box = self.box
        EngineAudioQueue.queue.async { box.recorder?.stop() }
    }

    /// Cancels any attempt and throws the clip away (sheet dismissed,
    /// re-record). Returns immediately.
    func reset() {
        abandonAttempt()
        discardFile()
        phase = .idle
    }

    /// Abandons the current attempt and returns to `.idle` with `message`.
    private func fail(_ message: String) {
        abandonAttempt()
        discardFile()
        phase = .idle
        errorMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func abandonAttempt() {
        attempt = UUID()
        stopMetering()
        elapsed = 0
        levels = Array(repeating: 0, count: Self.meterHistory)
        let box = self.box
        // Queued behind any in-flight start, so it runs once that returns.
        EngineAudioQueue.queue.async { box.tearDown() }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finish(successfully: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.finish(successfully: false) }
    }

    private func finish(successfully: Bool) {
        guard phase == .recording else { return }
        stopMetering()
        let box = self.box
        EngineAudioQueue.queue.async { box.tearDown() }
        guard successfully, let url = fileURL else {
            discardFile()
            phase = .idle
            errorMessage = "Recording failed. Try again."
            return
        }
        Task {
            let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? elapsed
            guard fileURL == url else { return }
            if !seconds.isFinite || seconds < Self.minDuration {
                discardFile()
                phase = .idle
                errorMessage = "That was too short. Record at least 1 second."
            } else {
                phase = .recorded(url: url, duration: min(seconds, Self.maxDuration))
            }
        }
    }

    // MARK: - Metering (sampled on the audio queue, published on main)

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestMeterSample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        meterSampleInFlight = false
    }

    private func requestMeterSample() {
        // Skip a tick rather than queue up samples behind a slow call.
        guard !meterSampleInFlight else { return }
        meterSampleInFlight = true
        let box = self.box
        let token = attempt
        EngineAudioQueue.queue.async { [weak self] in
            let sample = box.sample()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.meterSampleInFlight = false
                guard self.attempt == token, self.phase == .recording, let sample else { return }
                if sample.time > 0 { self.receivedAudio = true }
                self.elapsed = min(sample.time, Self.maxDuration)
                // -50 dB and below reads as silence; 0 dB is full scale.
                let level = CGFloat(max(0, min(1, (sample.power + 50) / 50)))
                self.levels = Array(self.levels.dropFirst()) + [level]
            }
        }
    }

    private func discardFile() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }
}

/// Holds the recorder for `EngineSoundRecorder`. Only ever touched on
/// `EngineAudioQueue.queue` (serial), which is what makes `@unchecked
/// Sendable` sound here.
private final class RecorderBox: @unchecked Sendable {
    var recorder: AVAudioRecorder?
    var token: UUID?

    /// (currentTime, averagePower) while recording; nil otherwise.
    func sample() -> (time: TimeInterval, power: Float)? {
        guard let recorder, recorder.isRecording else { return nil }
        recorder.updateMeters()
        return (recorder.currentTime, recorder.averagePower(forChannel: 0))
    }

    /// Stops and releases the recorder (without firing the delegate) and
    /// deactivates the session. Safe to call repeatedly.
    func tearDown() {
        if let recorder {
            recorder.delegate = nil
            if recorder.isRecording { recorder.stop() }
        }
        recorder = nil
        token = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Owner-only sheet: record, preview, then save through
/// `CarStore.setEngineSound`. Opened from `EngineSoundOwnerSection`.
struct EngineSoundRecorderSheet: View {
    let carID: UUID

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var recorder = EngineSoundRecorder()
    @StateObject private var player = EngineSoundPlayer()
    @State private var showingPermissionDenied = false
    @State private var saveError: String?

    private var remaining: Int {
        max(0, Int((EngineSoundRecorder.maxDuration - recorder.elapsed).rounded(.up)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Start your engine, hold your phone near the exhaust, and tap record. Recording stops automatically after 5 seconds.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    // Above the ring so it's on screen at any text size.
                    if let message = saveError ?? recorder.errorMessage {
                        MarqueErrorBanner(message: message)
                    }

                    ring
                    levelMeter
                    controls
                }
                .padding(20)
            }
            .navigationTitle("Engine Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Microphone Access Needed", isPresented: $showingPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To record your engine, allow Marque to use the microphone in Settings > Privacy & Security > Microphone.")
            }
            .onDisappear {
                player.stop()
                recorder.reset()
            }
        }
        .interactiveDismissDisabled(recorder.phase == .recording || recorder.phase == .starting)
    }

    // MARK: - Ring

    private var ring: some View {
        let progress = recorder.phase == .recording
            ? recorder.elapsed / EngineSoundRecorder.maxDuration
            : (isRecorded ? 1 : 0)
        return ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    recorder.phase == .recording ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.05), value: progress)
            ringCenter
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityLabel)
    }

    @ViewBuilder
    private var ringCenter: some View {
        switch recorder.phase {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
        case .starting:
            ProgressView()
                .controlSize(.large)
        case .recording:
            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("seconds left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .recorded(_, let duration):
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
                Text(String(format: "%.1fs", duration))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    private var ringAccessibilityLabel: String {
        switch recorder.phase {
        case .idle: return "Ready to record"
        case .starting: return "Starting microphone"
        case .recording: return "Recording, \(remaining) seconds left"
        case .recorded(_, let duration): return "Recorded \(Int(duration.rounded())) seconds"
        }
    }

    private var isRecorded: Bool {
        if case .recorded = recorder.phase { return true }
        return false
    }

    // MARK: - Level meter

    private var levelMeter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(recorder.phase == .recording ? Color.red.opacity(0.75) : Color(.systemGray4))
                    .frame(width: 4, height: 4 + 36 * level)
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch recorder.phase {
        case .idle:
            recordButton(isRecording: false) { Task { await startRecording() } }
            Text("Tap to record")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .starting:
            recordButton(isRecording: false) {}
                .disabled(true)
                .opacity(0.5)
            Text("Starting microphone…")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .recording:
            recordButton(isRecording: true) { recorder.stop() }
            Text("Tap to stop early")
                .font(.footnote)
                .foregroundColor(.secondary)
        case .recorded(let url, let duration):
            VStack(spacing: 14) {
                EngineSoundCapsule(
                    isPlaying: player.isPlaying,
                    isLoading: player.isLoading,
                    progress: player.progress,
                    duration: duration,
                    failed: player.failed
                ) {
                    player.toggle(url: url)
                }

                MarquePrimaryButton("Save Sound") { save(url: url, duration: duration) }

                Button {
                    player.stop()
                    recorder.reset()
                } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    private func recordButton(isRecording: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 76, height: 76)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 30)
                    .fill(Color.red)
                    .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record engine sound")
    }

    // MARK: - Actions

    private func startRecording() async {
        saveError = nil
        player.stop()
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            showingPermissionDenied = true
            return
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                showingPermissionDenied = true
                return
            }
        @unknown default:
            break
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recorder.start()
    }

    private func save(url: URL, duration: Double) {
        player.stop()
        guard let car = carStore.cars.first(where: { $0.id == carID }) else {
            saveError = "This car is no longer in your garage."
            return
        }
        do {
            try carStore.setEngineSound(fileURL: url, duration: duration, for: car)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

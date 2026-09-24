import SwiftUI
import AVFoundation

// MARK: - Confetti
//
// Shared one-shot confetti burst + celebration chime, originally built for
// ProUpgradeView's post-purchase celebration and extracted here so other
// milestone moments (e.g. AddCarView's onboarding first-car celebration) can
// reuse the same visual/audio language instead of duplicating it.

// One-shot burst rendered behind a celebration screen's content. Each piece
// animates independently (own random duration/delay) so the burst reads as
// organic rather than a single synchronized drop, and settles within ~2s —
// there is no repeating/looping animation here.
struct ConfettiPiece: Identifiable {
    let id = UUID()
    let xFraction: CGFloat     // 0...1 horizontal position within the container
    let color: Color
    let size: CGFloat
    let isCircle: Bool
    let startRotation: Double
    let endRotation: Double
    let duration: Double
    let delay: Double

    // Accent color plus three tasteful (not neon) complementary tones.
    private static let palette: [Color] = [
        .accentColor,
        Color(red: 0.96, green: 0.76, blue: 0.24),  // warm yellow
        Color(red: 0.36, green: 0.66, blue: 0.46),  // green
        Color(red: 0.90, green: 0.55, blue: 0.68),  // pink
    ]

    static func burst(count: Int = 36) -> [ConfettiPiece] {
        (0..<count).map { _ in
            ConfettiPiece(
                xFraction: .random(in: 0.02...0.98),
                color: palette.randomElement() ?? .accentColor,
                size: .random(in: 6...11),
                isCircle: Bool.random(),
                startRotation: .random(in: 0...360),
                endRotation: .random(in: 180...900),
                duration: .random(in: 1.3...2.1),
                delay: .random(in: 0...0.35)
            )
        }
    }
}

struct ConfettiView: View {
    // Generated once per appearance of the celebration view, not re-rolled on
    // every body evaluation (the array is a stored property, not computed).
    private let pieces = ConfettiPiece.burst()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiPieceView(piece: piece, containerHeight: geo.size.height)
                        .position(x: piece.xFraction * geo.size.width, y: geo.size.height / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    let containerHeight: CGFloat

    @State private var fallen = false

    var body: some View {
        Group {
            if piece.isCircle {
                Circle().fill(piece.color)
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(piece.color)
            }
        }
        .frame(width: piece.size, height: piece.isCircle ? piece.size : piece.size * 0.6)
        .rotationEffect(.degrees(fallen ? piece.endRotation : piece.startRotation))
        // Starts above the top edge, falls past the bottom edge; ConfettiView
        // clips, so the piece simply exits rather than lingering.
        .offset(y: fallen ? containerHeight / 2 + 60 : -(containerHeight / 2 + 60))
        .onAppear {
            withAnimation(.easeIn(duration: piece.duration).delay(piece.delay)) {
                fallen = true
            }
        }
    }
}

// MARK: - Celebration Sound

// A short synthesized ascending arpeggio (no bundled/licensed audio asset).
// Generates raw PCM samples and wraps them in a minimal WAV (RIFF) container
// as Data, playable via AVAudioPlayer(data:).
enum CelebrationChime {
    private static let sampleRate: Double = 44_100

    // C5 -> E5 -> G5: a pleasant ascending major-triad arpeggio.
    private static let notes: [Double] = [523.25, 659.25, 783.99]
    private static let noteDuration: Double = 0.22
    private static let noteGap: Double = 0.02
    // Moderate peak amplitude (soothing, not loud) with a soft attack/decay
    // envelope per note so there are no hard clicks at note boundaries.
    private static let amplitude: Float = 0.2

    // Synthesizes the chime, sets up an ambient/mix-with-others audio
    // session, and starts playback. .ambient respects the silent switch,
    // which is the polite default for a decorative UI sound. Fire-and-forget:
    // any setup or playback failure returns nil rather than surfacing to the
    // caller — a celebration's sound must never affect its UI. The caller
    // must hold the returned player (e.g. in @State) for ARC to keep it
    // alive through playback.
    static func play() -> AVAudioPlayer? {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: wavData())
            player.prepareToPlay()
            player.play()
            return player
        } catch {
            return nil
        }
    }

    static func wavData() -> Data {
        var samples: [Float] = []
        for (index, frequency) in notes.enumerated() {
            samples.append(contentsOf: makeNote(frequency: frequency, duration: noteDuration))
            if index < notes.count - 1 {
                samples.append(contentsOf: [Float](repeating: 0, count: Int(noteGap * sampleRate)))
            }
        }
        return pcmToWav(samples: samples)
    }

    private static func makeNote(frequency: Double, duration: Double) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        let attackSamples = max(1, Int(0.015 * sampleRate))   // ~15ms fade in
        let releaseSamples = max(1, Int(0.12 * sampleRate))   // ~120ms fade out tail
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            var envelope: Float = 1.0
            if i < attackSamples {
                envelope = Float(i) / Float(attackSamples)
            } else if i > sampleCount - releaseSamples {
                let remaining = sampleCount - i
                envelope = Float(max(0, remaining)) / Float(releaseSamples)
            }
            let value = sin(2.0 * Double.pi * frequency * t)
            samples[i] = amplitude * envelope * Float(value)
        }
        return samples
    }

    private static func pcmToWav(samples: [Float]) -> Data {
        let sampleRateInt = UInt32(sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRateInt * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        let int16Samples: [Int16] = samples.map { sample in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        var data = Data()
        let dataSize = UInt32(int16Samples.count * MemoryLayout<Int16>.size)
        let chunkSize = 36 + dataSize

        func appendString(_ s: String) { data.append(s.data(using: .ascii)!) }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }

        appendString("RIFF")
        appendUInt32(chunkSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16) // PCM fmt chunk size
        appendUInt16(1)  // audio format = PCM
        appendUInt16(numChannels)
        appendUInt32(sampleRateInt)
        appendUInt32(byteRate)
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)
        appendString("data")
        appendUInt32(dataSize)
        for sample in int16Samples {
            var le = sample.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        return data
    }
}

import AVFoundation

/// Waveforms for the phase-accumulator oscillator in `SynthRenderer`.
enum SynthWaveform {
    case square
    case triangle
    case sine
}

/// One note in a rendered sequence. `frequency <= 0` renders as a silent
/// rest of the given duration.
struct SynthTone {
    var frequency: Double
    var duration: Double
    var amplitude: Float
}

/// Linear attack/release ramp. Each side is capped both by an absolute
/// length in seconds and by an integer fraction of the note, so very
/// short notes keep a proportional ramp instead of being all-envelope.
struct SynthEnvelope {
    var attackSeconds: Double
    /// Attack never exceeds `noteFrames / attackCapDivisor`.
    var attackCapDivisor: Int
    var releaseSeconds: Double
    /// Release never exceeds `noteFrames / releaseCapDivisor`.
    var releaseCapDivisor: Int
}

/// Shared synthesis primitives: a tone-sequence renderer for
/// `AVAudioPlayerNode` buffers and a minimal WAV container encoder for
/// `AVAudioPlayer`-based callers. All output is mono 44.1 kHz.
@MainActor
enum SynthRenderer {
    nonisolated static let sampleRate: Double = 44_100

    static let monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Renders a tone sequence into a Float32 PCM buffer. The whole
    /// buffer is zero-filled first so rests and rounding slack are silent.
    static func buffer(
        tones: [SynthTone],
        waveform: SynthWaveform,
        envelope: SynthEnvelope
    ) -> AVAudioPCMBuffer? {
        let totalDuration = tones.reduce(0) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(max(1, totalDuration * sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { channel[i] = 0 }

        var cursor = 0
        for tone in tones {
            let noteFrames = Int(tone.duration * sampleRate)
            let attack = min(noteFrames / envelope.attackCapDivisor,
                             Int(envelope.attackSeconds * sampleRate))
            let release = min(noteFrames / envelope.releaseCapDivisor,
                              Int(envelope.releaseSeconds * sampleRate))
            var phase: Double = 0
            for i in 0..<noteFrames {
                guard cursor + i < Int(frameCount) else { break }
                var env: Float = 1
                if i < attack {
                    env = Float(i) / Float(max(1, attack))
                } else if i > noteFrames - release {
                    env = Float(noteFrames - i) / Float(max(1, release))
                }
                let sample: Float = tone.frequency <= 0 ? 0 : value(of: waveform, at: phase)
                channel[cursor + i] = sample * tone.amplitude * env
                phase += tone.frequency / sampleRate
                if phase >= 1 { phase -= 1 }
            }
            cursor += noteFrames
        }
        return buffer
    }

    /// Oscillator sample for a normalized phase in [0, 1).
    private static func value(of waveform: SynthWaveform, at phase: Double) -> Float {
        switch waveform {
        case .square:   return phase < 0.5 ? 1 : -1
        case .triangle: return Float(4 * abs(phase - 0.5) - 1)
        case .sine:     return Float(sin(2 * .pi * phase))
        }
    }

    /// Wraps mono 16-bit PCM samples in a minimal RIFF/WAVE container so
    /// they can feed `AVAudioPlayer(data:)`.
    static func monoWaveData(samples: [Int16], sampleRate: Double = SynthRenderer.sampleRate) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func writeUInt32LE(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func writeUInt16LE(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: "RIFF".utf8)
        writeUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        writeUInt32LE(16)
        writeUInt16LE(1)               // PCM
        writeUInt16LE(1)               // mono
        writeUInt32LE(UInt32(sampleRate))
        writeUInt32LE(UInt32(sampleRate) * 2)
        writeUInt16LE(2)               // block align (bytes/sample × channels)
        writeUInt16LE(16)              // bits per sample
        data.append(contentsOf: "data".utf8)
        writeUInt32LE(UInt32(dataSize))
        samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: dataSize
            ))
        }
        return data
    }
}

/// One `AVAudioEngine` + player node per instance, so independent sound
/// sources can play simultaneously without cutting each other off.
/// The engine is stood up lazily on first use; if it fails to start
/// (rare), playback calls become silent no-ops.
@MainActor
final class SynthPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var started = false

    /// Schedules the buffer, interrupting anything already playing.
    func play(_ buffer: AVAudioPCMBuffer) {
        guard ensureRunning() else { return }
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    /// Schedules the buffer after anything already queued.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard ensureRunning() else { return }
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    /// Stops playback and drops anything queued.
    func stop() {
        guard started else { return }
        node.stop()
    }

    /// Stands the engine up ahead of time so the first play is instant.
    func warmUp() {
        _ = ensureRunning()
    }

    private func ensureRunning() -> Bool {
        if started { return true }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: SynthRenderer.monoFormat)
        do {
            try engine.start()
            started = true
        } catch {
            // Engine unavailable: stay silent; callers' visuals are unaffected.
        }
        return started
    }
}

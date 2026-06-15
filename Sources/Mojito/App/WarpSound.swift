import AppKit

/// Plays the bundled warp cue (`s10.bin`, ~8s). Kept as a singleton-style
/// enum so `WarpDrive` can call `play()` / `stop()` without thinking about
/// the underlying `NSSound` retention.
@MainActor
enum WarpSound {
    private static var current: NSSound?
    private static let fadeTicker = AnimationTicker()

    /// Linear fade applied across the tail of the clip.
    private static let tailFade: TimeInterval = 1.5

    static func play() {
        fadeTicker.stop()
        current?.stop()
        guard EggSound.effectSoundsEnabled else { return }
        guard let sound = AudioBlob.load("s10") else { return }
        sound.volume = 1.0
        current = sound
        sound.play()

        // Auto-schedule the fade against the clip's own duration so it
        // lands while the sound is still audibly playing — previously
        // we scheduled it against the visual's duration, which outruns
        // the audio and meant the ramp never actually executed.
        let total = sound.duration
        let leadIn = total - tailFade
        if leadIn > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + leadIn) { [weak _captured = sound] in
                MainActor.assumeIsolated {
                    // Only fade if this clip is still the active one.
                    guard let active = current, active === _captured else { return }
                    fadeOut(duration: tailFade)
                }
            }
        }
    }

    /// Ramps volume to 0 over `duration` seconds, then stops the clip. If
    /// no sound is playing, no-op.
    static func fadeOut(duration: TimeInterval) {
        guard let sound = current else { return }
        let startVolume = sound.volume
        fadeTicker.start(interval: 1.0 / 30.0) { elapsed in
            let p = Float(min(1.0, elapsed / duration))
            sound.volume = startVolume * (1.0 - p)
            if p >= 1.0 {
                fadeTicker.stop()
                sound.stop()
                if current === sound {
                    current = nil
                }
            }
        }
    }

    static func stop() {
        fadeTicker.stop()
        current?.stop()
        current = nil
    }
}

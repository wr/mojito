import AppKit

/// Plays the bundled warp cue (`s10.bin`, ~8s). Kept as a singleton-style
/// enum so `WarpDrive` can call `play()` / `stop()` without thinking about
/// the underlying `NSSound` retention.
@MainActor
enum WarpSound {
    private static var current: NSSound?
    private static var fadeTimer: Timer?

    /// Linear fade applied across the tail of the clip.
    private static let tailFade: TimeInterval = 1.5

    static func play() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        current?.stop()
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
        fadeTimer?.invalidate()
        let startVolume = sound.volume
        let startDate = Date()
        let step: TimeInterval = 1.0 / 30.0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { timer in
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(startDate)
                let p = Float(min(1.0, elapsed / duration))
                sound.volume = startVolume * (1.0 - p)
                if p >= 1.0 {
                    timer.invalidate()
                    sound.stop()
                    if current === sound {
                        current = nil
                        fadeTimer = nil
                    }
                }
            }
        }
    }

    static func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        current?.stop()
        current = nil
    }
}

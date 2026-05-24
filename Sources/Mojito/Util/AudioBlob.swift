import AppKit

/// Loads scrambled audio assets from the bundle.
///
/// Each `sNN.bin` file in `Resources/` is the original .mp3/.wav with every
/// byte XOR'd against a single key. The header magic (`FF FB …` for MP3,
/// `RIFF…` for WAV) is destroyed by the scramble, so `file`, Quick Look,
/// and double-clicking the file from Finder all refuse to play it. Our
/// loader reads the bytes, undoes the XOR in memory, and feeds the result
/// to `NSSound(data:)`, which decodes from header magic at runtime.
///
/// The scrambling is trivial to reverse for anyone who reads this comment —
/// the point is to deter casual exploration, not to defeat a determined
/// reverse engineer.
enum AudioBlob {
    private static let key: UInt8 = 0x5A

    /// Returns an `NSSound` decoded from the scrambled blob with the given
    /// resource name (extension is always `.bin`). Caller is responsible for
    /// retaining the returned sound — releasing it mid-playback stops it.
    static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
              let raw = try? Data(contentsOf: url) else {
            return nil
        }
        var decoded = Data(count: raw.count)
        decoded.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            raw.withUnsafeBytes { (inp: UnsafeRawBufferPointer) in
                let outBytes = out.bindMemory(to: UInt8.self)
                let inBytes = inp.bindMemory(to: UInt8.self)
                for i in 0..<raw.count {
                    outBytes[i] = inBytes[i] ^ key
                }
            }
        }
        return NSSound(data: decoded)
    }
}

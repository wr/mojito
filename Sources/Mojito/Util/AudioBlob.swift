import AppKit

/// `sNN.bin` are .mp3/.wav files XOR'd against a single key, scrambling
/// the header magic so `file`, Quick Look, and Finder refuse to play them.
/// Trivially reversible — the point is to deter casual exploration.
enum AudioBlob {
    private static let key: UInt8 = 0x5A

    /// Caller must retain the returned sound — releasing stops playback.
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

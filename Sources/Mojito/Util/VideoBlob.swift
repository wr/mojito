import Foundation

/// Decodes a scrambled video blob (`vNN.bin`) to a temp file on first use
/// and caches the resulting URL. AVPlayer wants a URL/file-backed source,
/// so unlike `AudioBlob`/`ImageBlob` we can't hand it raw decoded bytes —
/// we write the decoded payload to `NSTemporaryDirectory()/MojitoVideos/`
/// once per app launch and hand the same URL out on subsequent calls.
enum VideoBlob {
    private static let key: UInt8 = 0x5A
    /// Wrapped in a serial queue to keep concurrent first-time decodes from
    /// racing each other to write the same temp file.
    private static let lock = NSLock()
    private static var cache: [String: URL] = [:]

    /// Returns a temp-file URL pointing at the decoded `.mp4`. nil if the
    /// resource isn't present or decoding/writing fails.
    static func url(_ name: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] { return cached }

        guard let src = Bundle.main.url(forResource: name, withExtension: "bin"),
              let raw = try? Data(contentsOf: src) else {
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

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MojitoVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(name).mp4")
        do {
            try decoded.write(to: dest, options: .atomic)
            cache[name] = dest
            return dest
        } catch {
            return nil
        }
    }
}

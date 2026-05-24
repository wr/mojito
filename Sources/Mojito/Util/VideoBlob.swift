import Foundation

/// AVPlayer wants a URL, so unlike `AudioBlob`/`ImageBlob` we decode
/// `vNN.bin` to a per-launch temp file and cache the URL.
enum VideoBlob {
    private static let key: UInt8 = 0x5A
    /// Serializes concurrent first-time decodes writing the same temp file.
    private static let lock = NSLock()
    private static var cache: [String: URL] = [:]

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

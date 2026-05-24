import AppKit

/// Same XOR scheme as `AudioBlob` for `vNN.bin` image assets.
enum ImageBlob {
    private static let key: UInt8 = 0x5A

    static func load(_ name: String) -> NSImage? {
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
        return NSImage(data: decoded)
    }
}

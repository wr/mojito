import Foundation
import Testing

/// Hands out throwaway `UserDefaults` suites for store tests and deletes them
/// on deinit.
///
/// Suites are opened by absolute path inside a private temp directory, so they
/// never land in `~/Library/Preferences`. A named suite
/// (`UserDefaults(suiteName: "mojito.tests.…")`) does, and cfprefsd rewrites
/// an empty plist there even after `removePersistentDomain` + deleting the
/// file — that's how thousands of `mojito.tests.*.plist` files piled up (W-1030).
///
/// Keep one as a stored property of the test suite. Swift Testing builds a
/// fresh suite instance per test, so every domain it made is torn down when
/// that test finishes.
final class ScratchDefaults {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mojito-tests-\(UUID().uuidString)", isDirectory: true)
    private(set) var suiteNames: [String] = []
    private var suites: [UserDefaults] = []

    func make() -> UserDefaults {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = directory.appendingPathComponent(UUID().uuidString).path
        let suite = UserDefaults(suiteName: name)!
        suiteNames.append(name)
        suites.append(suite)
        return suite
    }

    deinit {
        // Clear cfprefsd's copy first so it has nothing to flush back to disk.
        for (name, suite) in zip(suiteNames, suites) {
            suite.removePersistentDomain(forName: name)
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

struct ScratchDefaultsTests {
    @Test func suitesLiveInTempAndAreRemovedOnDeinit() throws {
        var scratch: ScratchDefaults? = ScratchDefaults()
        let suite = try #require(scratch).make()
        suite.set("x", forKey: "k")
        let name = try #require(scratch?.suiteNames.first)
        let directory = try #require(scratch).directory
        #expect(name.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: directory.path))

        scratch = nil

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(suite.string(forKey: "k") == nil)
    }
}

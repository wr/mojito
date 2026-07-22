import Foundation
import Testing
@testable import Mojito

/// Guards the W-555 fix: reading Arc's tab URL must never do blocking IPC on the
/// caller's thread (that thread is the CGEventTap callback, and a synchronous
/// AppleScript there tripped the tap timeout and dropped keystrokes). These
/// pin the concurrency contract — deferred resolve, single-flight, throttle,
/// pid-guard — with a stub resolver and a controllable clock, so no live Arc,
/// AppleScript, or app switch is needed.
///
/// The end-to-end "keys don't drop while typing in Arc" behavior is timing- and
/// Arc-dependent and can't be asserted deterministically; this instead nails the
/// property that *causes* the drop when violated.
@MainActor
struct BrowserURLCacheTests {

    private static let arc = "company.thebrowser.Browser"

    /// Records how the injected resolver was called — count, argument, and the
    /// thread — so tests can assert the AppleScript work is deferred to a later
    /// main-thread turn rather than run inline on the hot path.
    private final class ResolverSpy {
        var calls = 0
        var lastBundleID: String?
        var ranOnMainThread = false
        var stub: URL?
        func resolve(_ bundleID: String) -> URL? {
            calls += 1
            lastBundleID = bundleID
            ranOnMainThread = Thread.isMainThread
            return stub
        }
    }

    private final class Clock {
        var now: Date
        init(_ start: Date) { now = start }
    }

    private func makeCache(
        spy: ResolverSpy,
        clock: Clock,
        minRefreshInterval: TimeInterval = 1_000
    ) -> BrowserURLCache {
        BrowserURLCache(
            observeActivations: false,
            minRefreshInterval: minRefreshInterval,
            now: { clock.now },
            resolver: { spy.resolve($0) }
        )
    }

    /// Let the main queue drain the `DispatchQueue.main.async` refresh block.
    private func drain() async throws {
        try await Task.sleep(nanoseconds: 30_000_000)
    }

    // MARK: - The core contract

    @Test func hotPathReturnsNilWhenColdAndDefersTheResolve() async throws {
        let spy = ResolverSpy(); spy.stub = URL(string: "https://example.com")
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        let value = cache.url(forBundleID: Self.arc, pid: 42)

        // Cold cache → nil, and — the crux — the resolver has NOT run yet.
        // If it ran synchronously here, that's the AppleScript back on the tap
        // thread and the bug is reintroduced.
        #expect(value == nil)
        #expect(spy.calls == 0)

        try await drain()

        // It runs on a later turn, on the main thread (where NSAppleScript is
        // supported), exactly once.
        #expect(spy.calls == 1)
        #expect(spy.ranOnMainThread)
        #expect(spy.lastBundleID == Self.arc)
    }

    @Test func servesCachedValueForSamePidAfterRefresh() async throws {
        let spy = ResolverSpy(); spy.stub = URL(string: "https://example.com")
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        try await drain()

        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://example.com"))
    }

    @Test func doesNotServeValueAcrossPidChange() async throws {
        let spy = ResolverSpy(); spy.stub = URL(string: "https://example.com")
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        try await drain()

        // A different pid means a different app instance — the URL resolved for
        // pid 42 must not leak to pid 99.
        #expect(cache.url(forBundleID: Self.arc, pid: 99) == nil)
    }

    @Test func burstOfReadsCollapsesToOneResolve() async throws {
        let spy = ResolverSpy(); spy.stub = URL(string: "https://example.com")
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        // A word+terminator produces several reads back-to-back; single-flight
        // must collapse them to one AppleScript.
        for _ in 0..<5 { _ = cache.url(forBundleID: Self.arc, pid: 42) }
        try await drain()

        #expect(spy.calls == 1)
    }

    @Test func throttleSkipsRefreshWithinIntervalThenAllowsAfter() async throws {
        let spy = ResolverSpy(); spy.stub = URL(string: "https://a.example")
        let clock = Clock(Date(timeIntervalSince1970: 10_000))
        let cache = makeCache(spy: spy, clock: clock, minRefreshInterval: 1.0)

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        try await drain()
        #expect(spy.calls == 1)

        // Within the throttle window: read again, no new resolve, still serving A.
        clock.now += 0.5
        spy.stub = URL(string: "https://b.example")
        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://a.example"))
        try await drain()
        #expect(spy.calls == 1)

        // Past the window: the next read refreshes and picks up B.
        clock.now += 0.6
        _ = cache.url(forBundleID: Self.arc, pid: 42)
        try await drain()
        #expect(spy.calls == 2)
        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://b.example"))
    }

    @Test func hotPathReturnsPromptlyEvenIfResolverWouldBlock() async throws {
        // Simulate a slow AppleScript: the resolver sleeps. The hot-path read
        // must still return without waiting for it (the whole point of the fix).
        let cache = BrowserURLCache(
            observeActivations: false,
            minRefreshInterval: 0,
            now: { Date() },
            resolver: { _ in Thread.sleep(forTimeInterval: 0.2); return URL(string: "https://slow.example") }
        )

        let start = Date()
        _ = cache.url(forBundleID: Self.arc, pid: 42)
        let elapsed = Date().timeIntervalSince(start)

        // The read itself did no blocking work — well under the resolver's 200ms.
        #expect(elapsed < 0.05)
        try await drain()
    }

    @Test func arcIsGatedIntoTheAppleScriptPath() {
        #expect(BrowserURLCache.appleScriptBundleIDs.contains(Self.arc))
    }
}

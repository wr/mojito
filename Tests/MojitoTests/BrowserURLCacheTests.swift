import Foundation
import Testing
@testable import Mojito

/// Guards the W-555/W-557 fix: reading Arc's tab URL must never do blocking IPC on
/// the caller's thread (that thread is the CGEventTap callback, and a synchronous
/// AppleScript there tripped the tap timeout and dropped keystrokes). These pin the
/// concurrency contract — deferred resolve, off-main, single-flight, throttle,
/// pid-guard, and keep-last-value-on-timeout — with a stub resolver and a
/// controllable clock, so no live Arc, AppleScript, or app switch is needed.
///
/// Serialized because they share the process-wide `BrowserURLCache.resolveQueue`
/// and assert on timing of the off-main hop; parallel execution could interleave.
@MainActor
@Suite(.serialized)
struct BrowserURLCacheTests {

    private static let arc = "company.thebrowser.Browser"

    /// Records how the injected resolver was called — count, argument, and the
    /// thread — so tests can assert the AppleScript work is deferred *off* the
    /// caller's (tap) thread. The resolver runs on a background queue, so the
    /// state is lock-guarded and the type is `@unchecked Sendable`.
    private final class ResolverSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private var _lastBundleID: String?
        private var _ranOnMainThread = false
        private var _outcome: BrowserURLResolution = .resolved(nil)

        var calls: Int { lock.withLock { _calls } }
        var lastBundleID: String? { lock.withLock { _lastBundleID } }
        var ranOnMainThread: Bool { lock.withLock { _ranOnMainThread } }
        func setOutcome(_ o: BrowserURLResolution) { lock.withLock { _outcome = o } }
        func setStub(_ url: URL?) { lock.withLock { _outcome = .resolved(url) } }

        func resolve(_ bundleID: String) -> BrowserURLResolution {
            lock.withLock {
                _calls += 1
                _lastBundleID = bundleID
                _ranOnMainThread = Thread.isMainThread
                return _outcome
            }
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

    /// Poll the main actor until `cond` holds or a generous timeout — replaces a
    /// fixed sleep so a loaded CI can't flake the deferred-resolve assertions.
    @discardableResult
    private func settle(
        timeout: TimeInterval = 2,
        until cond: () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() >= deadline { return false }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    // MARK: - The core contract

    @Test func hotPathReturnsNilWhenColdAndDefersTheResolve() async throws {
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://example.com"))
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        let value = cache.url(forBundleID: Self.arc, pid: 42)

        // Cold cache → nil, and — the crux — the resolver has NOT run yet.
        // If it ran synchronously here, that's the AppleScript back on the tap
        // thread and the bug is reintroduced.
        #expect(value == nil)
        #expect(spy.calls == 0)

        #expect(try await settle { spy.calls == 1 })

        // It ran OFF the main/tap thread (so a hung Arc can't stall the tap or UI).
        #expect(!spy.ranOnMainThread)
        #expect(spy.lastBundleID == Self.arc)
    }

    @Test func servesCachedValueForSamePidAfterRefresh() async throws {
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://example.com"))
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        #expect(try await settle { cache.url(forBundleID: Self.arc, pid: 42) != nil })

        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://example.com"))
    }

    @Test func doesNotServeValueAcrossPidChange() async throws {
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://example.com"))
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        #expect(try await settle { spy.calls == 1 })

        // A different pid means a different app instance — the URL resolved for
        // pid 42 must not leak to pid 99.
        #expect(cache.url(forBundleID: Self.arc, pid: 99) == nil)
    }

    @Test func burstOfReadsCollapsesToOneResolve() async throws {
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://example.com"))
        let cache = makeCache(spy: spy, clock: Clock(Date()))

        // A word+terminator produces several reads back-to-back; single-flight
        // must collapse them to one AppleScript.
        for _ in 0..<5 { _ = cache.url(forBundleID: Self.arc, pid: 42) }
        #expect(try await settle { spy.calls >= 1 })
        // Give any erroneously-scheduled extra resolves a chance to show up.
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(spy.calls == 1)
    }

    @Test func throttleSkipsRefreshWithinIntervalThenAllowsAfter() async throws {
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://a.example"))
        let clock = Clock(Date(timeIntervalSince1970: 10_000))
        let cache = makeCache(spy: spy, clock: clock, minRefreshInterval: 1.0)

        _ = cache.url(forBundleID: Self.arc, pid: 42)
        #expect(try await settle { spy.calls == 1 })

        // Within the throttle window: read again, no new resolve, still serving A.
        clock.now += 0.5
        spy.setStub(URL(string: "https://b.example"))
        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://a.example"))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(spy.calls == 1)

        // Past the window: the next read refreshes and picks up B.
        clock.now += 0.6
        _ = cache.url(forBundleID: Self.arc, pid: 42)
        #expect(try await settle { spy.calls == 2 })
        #expect(try await settle { cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://b.example") })
    }

    @Test func hotPathReturnsPromptlyEvenIfResolverWouldBlock() async throws {
        // Simulate a slow AppleScript: the resolver sleeps. The hot-path read
        // must still return without waiting for it (the whole point of the fix).
        let cache = BrowserURLCache(
            observeActivations: false,
            minRefreshInterval: 0,
            now: { Date() },
            resolver: { _ in Thread.sleep(forTimeInterval: 0.2); return .resolved(URL(string: "https://slow.example")) }
        )

        let start = Date()
        _ = cache.url(forBundleID: Self.arc, pid: 42)
        let elapsed = Date().timeIntervalSince(start)

        // The read itself did no blocking work — well under the resolver's 200ms.
        #expect(elapsed < 0.05)
    }

    @Test func unavailableResolveKeepsLastGoodValue() async throws {
        // A resolve that times out against a hung Arc returns `.unavailable`; it
        // must NOT erase a previously-cached URL (that would transiently drop a
        // denylisted-site URL and let an excluded page through). Clock-driven
        // throttling keeps the reads deterministic — no spurious reschedules.
        let spy = ResolverSpy(); spy.setStub(URL(string: "https://kept.example"))
        let clock = Clock(Date(timeIntervalSince1970: 5_000))
        let cache = makeCache(spy: spy, clock: clock, minRefreshInterval: 1.0)

        // Warm: the first read resolves and caches "kept". Reads within the 1s
        // window are throttled, so `spy.calls` stays 1.
        _ = cache.url(forBundleID: Self.arc, pid: 42)
        #expect(try await settle { spy.calls == 1 })
        #expect(try await settle { cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://kept.example") })

        // Past the window, the next resolve comes back unavailable (hung/killed).
        clock.now += 1.1
        spy.setOutcome(.unavailable)
        _ = cache.url(forBundleID: Self.arc, pid: 42)   // schedules refresh #2 (.unavailable)
        #expect(try await settle { spy.calls == 2 })
        try await Task.sleep(nanoseconds: 30_000_000)   // let the publish land

        // The cached value survived. This read is within the new throttle window
        // (lastRefreshAt advanced), so it doesn't reschedule and can't flake.
        #expect(cache.url(forBundleID: Self.arc, pid: 42) == URL(string: "https://kept.example"))
    }

    @Test func arcIsGatedIntoTheAppleScriptPath() {
        #expect(BrowserURLCache.appleScriptBundleIDs.contains(Self.arc))
    }
}

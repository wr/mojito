import Foundation
import Testing
@testable import Mojito

/// The unique-install flags are only exact if every install sets `weekly` /
/// `monthly` on exactly one ping per UTC week / month — so the boundary math
/// is what's under test.
struct TelemetryUsageFlagsTests {

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: y, month: m, day: d))!
        return TelemetryUploader.utcDay(date)
    }

    private static func flags(last: Int, today: Int) -> [String: Bool] {
        TelemetryUploader.usageFlags(lastUploadDay: last, today: today)
    }

    @Test func firstEverReportSetsEverything() {
        #expect(Self.flags(last: 0, today: Self.day(2026, 10, 7))
                == ["new": true, "weekly": true, "monthly": true])
    }

    @Test func sameWeekAndMonthSetsNothing() {
        // Mon 5 Oct → Wed 7 Oct 2026.
        #expect(Self.flags(last: Self.day(2026, 10, 5), today: Self.day(2026, 10, 7))
                == ["new": false, "weekly": false, "monthly": false])
    }

    @Test func weeksStartOnMonday() {
        // Sun 4 Oct → Mon 5 Oct 2026 crosses a week; Mon → Sun 11 Oct doesn't.
        #expect(Self.flags(last: Self.day(2026, 10, 4), today: Self.day(2026, 10, 5))["weekly"] == true)
        #expect(Self.flags(last: Self.day(2026, 10, 5), today: Self.day(2026, 10, 11))["weekly"] == false)
        #expect(Self.flags(last: Self.day(2026, 10, 11), today: Self.day(2026, 10, 12))["weekly"] == true)
    }

    @Test func monthBoundaryIndependentOfWeek() {
        // Wed 30 Sep → Thu 1 Oct 2026: same week, new month.
        let f = Self.flags(last: Self.day(2026, 9, 30), today: Self.day(2026, 10, 1))
        #expect(f["weekly"] == false)
        #expect(f["monthly"] == true)
    }

    @Test func sameMonthNumberInDifferentYearIsNewMonth() {
        #expect(Self.flags(last: Self.day(2025, 10, 7), today: Self.day(2026, 10, 7))["monthly"] == true)
    }

    @Test func weekIndexMatchesWorker() {
        // stats-worker/src/index.js uses the same Math.floor((day + 3) / 7).
        #expect(TelemetryUploader.utcWeek(Self.day(1970, 1, 4)) == 0)  // Sunday
        #expect(TelemetryUploader.utcWeek(Self.day(1970, 1, 5)) == 1)  // Monday
    }
}

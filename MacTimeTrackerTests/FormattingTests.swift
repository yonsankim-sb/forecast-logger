import Testing
import Foundation
@testable import MacTimeTracker

/// Pure-logic tests for the formatting/label helpers on `TrackerViewModel`.
struct FormattingTests {

    @Test func formatHoursRendersHoursAndMinutes() {
        #expect(TrackerViewModel.formatHours(8.0) == "8h")
        #expect(TrackerViewModel.formatHours(1.5) == "1h 30m")
        #expect(TrackerViewModel.formatHours(0.75) == "45m")
        #expect(TrackerViewModel.formatHours(0) == "0m")
        // Rounds to the nearest minute.
        #expect(TrackerViewModel.formatHours(2.0 + 29.0 / 3600.0) == "2h")
    }

    @Test func decimalHoursDropsTrailingZero() {
        #expect(TrackerViewModel.decimalHours(0.5) == "0.5hrs")
        #expect(TrackerViewModel.decimalHours(2.0) == "2hrs")
        #expect(TrackerViewModel.decimalHours(2.34) == "2.3hrs")   // rounds to 1 dp
        #expect(TrackerViewModel.decimalHours(2.36) == "2.4hrs")
    }

    @Test func shortTimeSwitchesFormatAtOneHour() {
        #expect(TrackerViewModel.shortTime(46) == "00:46")     // minutes zero-padded
        #expect(TrackerViewModel.shortTime(599) == "09:59")
        #expect(TrackerViewModel.shortTime(3661) == "1:01:01") // hours: H:MM:SS
        #expect(TrackerViewModel.shortTime(0) == "00:00")
    }

    @Test func isoDateIsGregorianYMD() {
        // 2026-07-05 12:00:00 UTC.
        let date = Date(timeIntervalSince1970: 1_783_252_800)
        let iso = TrackerViewModel.isoDate(date)
        #expect(iso.count == 10)
        #expect(iso[iso.index(iso.startIndex, offsetBy: 4)] == "-")
    }
}

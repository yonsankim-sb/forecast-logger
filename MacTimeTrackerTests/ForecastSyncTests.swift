import Testing
@testable import MacTimeTracker

/// Tests for `TrackerViewModel.syncOps` — Pattern A carving of *today* out of an
/// existing Forecast assignment (shrink original + create pieces, no delete).
struct ForecastSyncTests {
    let today = "2026-07-06"
    let yesterday = "2026-07-05"
    let tomorrow = "2026-07-07"

    private func assignment(id: Int = 1, start: String?, end: String?, allocation: Int = 28800) -> ForecastAssignment {
        ForecastAssignment(id: id, projectId: 100, personId: 1, startDate: start, endDate: end, allocation: allocation, notes: "plan")
    }

    @Test func noExistingCreatesTodayOnly() {
        let ops = TrackerViewModel.syncOps(existing: nil, loggedSeconds: 18000, notes: "work", personId: 1,
                                           today: today, yesterday: yesterday, tomorrow: tomorrow)
        #expect(ops == [.create(start: today, end: today, allocationSeconds: 18000, notes: "work")])
    }

    @Test func singleDayUpdatesInPlace() {
        let a = assignment(id: 7, start: today, end: today)
        let ops = TrackerViewModel.syncOps(existing: a, loggedSeconds: 18000, notes: "work", personId: 1,
                                           today: today, yesterday: yesterday, tomorrow: tomorrow)
        #expect(ops == [.update(id: 7, projectId: 100, personId: 1,
                                start: today, end: today, allocationSeconds: 18000, notes: "work")])
    }

    // A range spanning today: shrink the original to end yesterday, add today,
    // add the remaining "after" piece. No delete, no overlap.
    @Test func multiDaySpanningTodaySplits() {
        let a = assignment(id: 9, start: "2026-07-01", end: "2026-07-31", allocation: 28800)
        let ops = TrackerViewModel.syncOps(existing: a, loggedSeconds: 18000, notes: "work", personId: 1,
                                           today: today, yesterday: yesterday, tomorrow: tomorrow)
        #expect(ops == [
            .update(id: 9, projectId: 100, personId: 1, start: "2026-07-01", end: yesterday,
                    allocationSeconds: 28800, notes: "plan"),
            .create(start: today, end: today, allocationSeconds: 18000, notes: "work"),
            .create(start: tomorrow, end: "2026-07-31", allocationSeconds: 28800, notes: "plan"),
        ])
    }

    @Test func multiDayStartingTodayMovesStart() {
        let a = assignment(id: 3, start: today, end: "2026-07-10", allocation: 14400)
        let ops = TrackerViewModel.syncOps(existing: a, loggedSeconds: 18000, notes: "work", personId: 1,
                                           today: today, yesterday: yesterday, tomorrow: tomorrow)
        #expect(ops == [
            .update(id: 3, projectId: 100, personId: 1, start: tomorrow, end: "2026-07-10",
                    allocationSeconds: 14400, notes: "plan"),
            .create(start: today, end: today, allocationSeconds: 18000, notes: "work"),
        ])
    }

    @Test func multiDayEndingTodayShrinksEnd() {
        let a = assignment(id: 4, start: "2026-07-01", end: today, allocation: 14400)
        let ops = TrackerViewModel.syncOps(existing: a, loggedSeconds: 18000, notes: "work", personId: 1,
                                           today: today, yesterday: yesterday, tomorrow: tomorrow)
        #expect(ops == [
            .update(id: 4, projectId: 100, personId: 1, start: "2026-07-01", end: yesterday,
                    allocationSeconds: 14400, notes: "plan"),
            .create(start: today, end: today, allocationSeconds: 18000, notes: "work"),
        ])
    }
}

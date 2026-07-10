import Testing
import Foundation
@testable import MacTimeTracker

/// Tests for localization, notices, shader-param decoding, and the record/stop
/// timer flow (the same `record()`/`pause()`/`stop()` the compact and full
/// windows both call).
struct ModelLogicTests {

    // MARK: - Localization

    @Test func localizationPicksLanguage() {
        #expect(L.s("Logged", "実績", "ja") == "実績")
        #expect(L.s("Logged", "実績", "en") == "Logged")
        #expect(L.s("Logged", "実績", "") == "Logged")        // unknown → English
        #expect(L.s("Logged", "実績", "fr") == "Logged")
    }

    // MARK: - Notice

    @Test func noticeTTLByKind() {
        #expect(Notice(kind: .error, message: "x").autoDismissAfter == 7)
        #expect(Notice(kind: .success, message: "x").autoDismissAfter == 4)
        #expect(Notice(kind: .info, message: "x").autoDismissAfter == 4)
    }

    // MARK: - ShaderParams decoding

    @Test func shaderParamsDefaultsMissingKeys() throws {
        // Partial/old saved data must still decode, defaulting any missing keys.
        let json = #"{"speed":0.8,"circles":5}"#
        let params = try JSONDecoder().decode(ShaderParams.self, from: Data(json.utf8))
        #expect(params.speed == 0.8)
        #expect(params.circles == 5)
        #expect(params.saturation == 1.0)     // default
        #expect(params.iridescence == 0.35)   // default
    }

    @Test func shaderParamsRoundTrips() throws {
        let original = ShaderParams(speed: 1, circles: 5, refraction: 0.6, gloss: 1.5,
                                    aberration: 0.7, rim: 0.3, hue: 0.25, iridescence: 0.5,
                                    reflection: 0.4, caustics: 0.6, saturation: 1.2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShaderParams.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Timer: record → stop keeps the logged entry

    /// Both the compact (shader) window and the full window wire their Start /
    /// Pause / Stop buttons to `record()` / `pause()` / `stop()`. This proves
    /// that Stop closes the running segment but *keeps* it in today's log.
    @MainActor
    @Test func stopKeepsTheLoggedEntry() {
        let vm = TrackerViewModel.preview(auth: AuthStore.preview())
        let projectId = vm.selectedProject!.id

        vm.record()
        #expect(vm.isRecording)                          // session started
        #expect(vm.isTimerRunning)                       // a running segment exists

        vm.stop()
        #expect(!vm.isRecording)                         // session ended
        #expect(!vm.isTimerRunning)                      // nothing running

        // A closed entry for the project is kept in today's log (what Logged shows).
        #expect(vm.todayLoggedEntries.contains { $0.projectId == projectId && !$0.isRunning })
        #expect(vm.loggedGroupedToday.groups.contains { $0.id == projectId })
    }

    // MARK: - Cross-midnight split

    @Test func crossMidnightEntrySplitsPerDay() {
        let cal = Calendar(identifier: .gregorian)
        let today0 = cal.startOfDay(for: Date())
        let start = today0.addingTimeInterval(-3600)      // 23:00 the previous day
        let end = today0.addingTimeInterval(5400)         // 01:30 today
        let entry = LoggedEntry(projectId: 1, projectLabel: "P", notes: "n", start: start, end: end)

        let parts = TrackerViewModel.splitAtMidnights(entry, now: end)
        #expect(parts.count == 2)
        #expect(parts[0].end == today0)                   // first piece ends at midnight
        #expect(parts[1].start == today0)                 // second piece starts at midnight
        #expect(abs(parts[0].duration - 3600) < 1)        // 1h on the previous day
        #expect(abs(parts[1].duration - 5400) < 1)        // 1.5h today
        #expect(parts[0].dayKey != parts[1].dayKey)       // different dates
    }

    @Test func runningEntryAcrossMidnightKeepsLastPieceRunning() {
        let cal = Calendar(identifier: .gregorian)
        let today0 = cal.startOfDay(for: Date())
        let start = today0.addingTimeInterval(-1800)      // 23:30 the previous day
        let entry = LoggedEntry(projectId: 1, projectLabel: "P", notes: "n", start: start, end: nil)

        let now = today0.addingTimeInterval(600)          // 00:10 today
        let parts = TrackerViewModel.splitAtMidnights(entry, now: now)
        #expect(parts.count == 2)
        #expect(parts[0].end == today0)                   // previous day closed at midnight
        #expect(parts[0].isRunning == false)
        #expect(parts[1].isRunning == true)               // today's piece still running
        #expect(parts[1].start == today0)
    }

    // MARK: - Per-day breakdown

    @MainActor
    @Test func dailyBreakdownIsPerDayNewestFirst() {
        let vm = TrackerViewModel.preview(auth: AuthStore.preview())
        let days = vm.loggedDailyBreakdown(days: 7)

        #expect(days.count >= 2)                                  // preview spans today + a prior day
        #expect(Calendar(identifier: .gregorian).isDateInToday(days.first!.date))  // newest = today
        for i in 1..<days.count { #expect(days[i - 1].date > days[i].date) }        // strictly newest-first
        for day in days {                                         // each total == its segments' sum
            #expect(abs(day.total - day.segments.reduce(0) { $0 + $1.hours }) < 0.001)
        }
        // Distinct dates: no day is repeated (dates aren't lumped together).
        #expect(Set(days.map(\.id)).count == days.count)
    }

    @Test func sameDayEntryIsNotSplit() {
        let entry = LoggedEntry(projectId: 1, projectLabel: "P", notes: "n",
                                start: Date().addingTimeInterval(-120), end: Date())
        #expect(TrackerViewModel.splitAtMidnights(entry, now: Date()).count == 1)
    }

    /// Pause closes the running segment (logging it) but keeps the session so it
    /// can resume; a following Stop must still leave the paused segment logged.
    @MainActor
    @Test func pauseThenStopKeepsTheLoggedEntry() {
        let vm = TrackerViewModel.preview(auth: AuthStore.preview())
        let projectId = vm.selectedProject!.id

        vm.record()
        vm.pause()
        #expect(vm.isPaused)                             // session kept, no running segment

        vm.stop()
        #expect(!vm.isRecording)
        // The paused segment stays logged for the project today (nothing running).
        #expect(vm.todayLoggedEntries.contains { $0.projectId == projectId && !$0.isRunning })
        #expect(!vm.loggedEntries.contains { $0.isRunning })
    }
}

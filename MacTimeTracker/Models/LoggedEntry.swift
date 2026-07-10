import Foundation

/// A locally-logged time entry — real hours you actually worked. Forecast has no
/// logged-time API, so these live on this Mac (persisted via `TimeLogStore`) and
/// can optionally be pushed into Forecast as an assignment.
struct LoggedEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let projectId: Int
    /// Snapshot of the project's display label at start time.
    let projectLabel: String
    var notes: String
    let start: Date
    /// `nil` while the timer is still running.
    var end: Date?

    init(id: UUID = UUID(), projectId: Int, projectLabel: String, notes: String, start: Date = Date(), end: Date? = nil) {
        self.id = id
        self.projectId = projectId
        self.projectLabel = projectLabel
        self.notes = notes
        self.start = start
        self.end = end
    }

    var isRunning: Bool { end == nil }

    /// Elapsed seconds — live while running, fixed once stopped.
    var duration: TimeInterval {
        max(0, (end ?? Date()).timeIntervalSince(start))
    }

    /// `yyyy-MM-dd` bucket the entry belongs to (by its start).
    var dayKey: String { TrackerViewModel.isoDate(start) }
}

/// The active recording session: which project is being tracked and when the
/// current sitting began. Persisted so a paused/running session survives relaunch.
/// The elapsed time is derived from the `LoggedEntry` segments since `sessionStart`.
struct TimerSession: Codable, Hashable {
    let projectId: Int
    let projectLabel: String
    var notes: String
    let sessionStart: Date
}

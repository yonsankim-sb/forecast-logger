import Foundation
import Combine
import Network
import AppKit
import CoreGraphics

/// A project's logged time today, split into note groups.
struct LoggedProjectGroup: Identifiable {
    let id: Int            // project id
    let label: String
    let hours: Double
    let noteGroups: [LoggedNoteGroup]
}

/// Logged sessions today that share the same note, merged into one line.
struct LoggedNoteGroup: Identifiable {
    let id: String
    let note: String       // trimmed note; empty = no note
    let hours: Double
    let entryIds: [UUID]
    let isRunning: Bool
}

/// Total logged hours for one work group (a project, split out by note) over a
/// window — a colored segment of the Insights stacked bar.
struct WorkGroupHours: Identifiable {
    let id: String        // "projectId|note"
    let label: String     // the note, or the project name when there's no note
    let hours: Double
}

/// A project's logged hours split into task (note) segments — one stacked bar in
/// the Insights chart, colored per task.
struct ProjectBreakdown: Identifiable {
    let id: Int
    let projectLabel: String
    let total: Double
    let segments: [WorkGroupHours]
}

/// One calendar day's logged hours split into task segments — a row in the
/// per-day Insights chart, colored per task (shared color scale).
struct DayBreakdown: Identifiable {
    let id: String        // dayKey (yyyy-MM-dd)
    let date: Date
    let total: Double
    let segments: [WorkGroupHours]
}

/// Planned (Forecast schedule) vs actual (logged) hours for a project today.
struct PlanActual: Identifiable {
    let id: Int
    let label: String
    let planned: Double
    let actual: Double
}

/// Drives the UI against **Forecast**: projects (with client names), the current
/// person, and today's scheduled assignments. Forecast has no logged-time or
/// timer API, so the app also keeps a **local** start/stop timer (`loggedEntries`)
/// that records the real hours worked and can be pushed into Forecast.
/// All state mutations happen on the main actor; networking is awaited off it.
@MainActor
final class TrackerViewModel: ObservableObject {
    // Selection
    @Published var projects: [ForecastProject] = []
    @Published var selectedProject: ForecastProject?
    @Published var notes: String = ""

    // Today's schedule (Forecast)
    @Published var todayAssignments: [ForecastAssignment] = []

    // Local logged time (record/pause/stop timer)
    @Published private(set) var loggedEntries: [LoggedEntry] = [] {
        didSet { TimeLogStore.save(loggedEntries) }
    }
    @Published private(set) var session: TimerSession? {
        didSet { TimeLogStore.saveSession(session) }
    }
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    // Status
    @Published var isLoadingProjects = false
    @Published var isRefreshing = false
    @Published var isBusy = false
    /// A transient, typed inline message (success / error / info).
    @Published var notice: Notice?
    /// Set true after a successful sync to prompt "view changes in Forecast?".
    @Published var showForecastReviewPrompt = false
    @Published private(set) var isOnline = true
    @Published private(set) var currentUser: ForecastUser?

    private let auth: AuthStore
    private var clientsById: [Int: String] = [:]
    private var projectsById: [Int: ForecastProject] = [:]
    private var hasBootstrapped = false
    private var ticker: AnyCancellable?
    private var noticeDismissTask: Task<Void, Never>?

    /// The current UI language code, for localizing code-produced strings.
    var languageCode: String { auth.languageCode }

    /// Auto-pause the running timer after this many minutes of user inactivity,
    /// excluding the idle time from the log (guards against a forgotten running
    /// timer). `0` disables idle detection. Persisted.
    @Published var idleTimeoutMinutes: Int = 10 {
        didSet { UserDefaults.standard.set(idleTimeoutMinutes, forKey: Self.idleTimeoutKey) }
    }
    private static let idleTimeoutKey = "app.idleTimeoutMinutes"

    /// Logged sessions older than this are pruned at launch (storage hygiene).
    private static let logRetentionDays = 90

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.forecastlogger.network")

    init(auth: AuthStore) {
        self.auth = auth
        if let stored = UserDefaults.standard.object(forKey: Self.idleTimeoutKey) as? Int {
            idleTimeoutMinutes = stored
        }
        loggedEntries = TimeLogStore.load()
        pruneOldEntries()
        session = TimeLogStore.loadSession()
        // Reconcile a running segment left over without a session (older data).
        if session == nil, let running = loggedEntries.first(where: { $0.isRunning }) {
            session = TimerSession(projectId: running.projectId, projectLabel: running.projectLabel, notes: running.notes, sessionStart: running.start)
        }
        // Attribute any entry that already spans midnight to each date (done after
        // session recovery so a recovered session keeps its full elapsed time).
        splitEntriesAcrossMidnight()
        startNetworkMonitor()
        if isTimerRunning {
            startTicker()          // recover a timer left running
        } else if isRecording {
            recomputeElapsed()     // recover a paused session (show frozen time)
        }
    }

    // MARK: - Derived state

    var canSchedule: Bool {
        selectedProject != nil && isOnline && !isBusy && currentUser != nil
    }

    /// Total hours scheduled for today across all projects.
    var todayTotalHours: Double {
        todayAssignments.reduce(0) { $0 + $1.hoursPerDay }
    }

    // MARK: - Timer / logged time (local): Record · Pause · Stop

    /// The segment currently being timed, if any.
    private var runningEntry: LoggedEntry? { loggedEntries.first { $0.isRunning } }

    /// A session exists once recording starts, until Stop.
    var isRecording: Bool { session != nil }

    /// A session that exists but has no running segment is paused.
    var isPaused: Bool { session != nil && runningEntry == nil }

    /// Actively counting (recording and not paused).
    var isTimerRunning: Bool { runningEntry != nil }

    /// Label of the project being recorded (or that is paused).
    var activeProjectLabel: String? { session?.projectLabel }

    /// Record starts a new session (needs a selected project) or resumes a paused one.
    var canRecord: Bool {
        if isPaused { return true }
        return session == nil && selectedProject != nil
    }

    /// Today's logged entries, newest first.
    var todayLoggedEntries: [LoggedEntry] {
        let today = Self.today()
        return loggedEntries.filter { $0.dayKey == today }.sorted { $0.start > $1.start }
    }

    /// Total hours logged today.
    var todayLoggedHours: Double {
        todayLoggedEntries.reduce(0) { $0 + $1.duration } / 3600.0
    }

    /// Today's logged time grouped by project, and within each project **merged
    /// by note** (multiple sessions with the same note are summed).
    var loggedGroupedToday: (groups: [LoggedProjectGroup], total: Double) {
        let byProject = Dictionary(grouping: todayLoggedEntries, by: { $0.projectId })
        let groups: [LoggedProjectGroup] = byProject.map { projectId, entries in
            let sorted = entries.sorted { $0.start < $1.start }
            let label = sorted.first?.projectLabel ?? "Project #\(projectId)"

            var order: [String] = []
            var buckets: [String: [LoggedEntry]] = [:]
            for entry in sorted {
                let key = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(entry)
            }
            let noteGroups = order.map { key -> LoggedNoteGroup in
                let items = buckets[key] ?? []
                return LoggedNoteGroup(
                    id: "\(projectId)#\(key)",
                    note: key,
                    hours: items.reduce(0) { $0 + $1.duration } / 3600.0,
                    entryIds: items.map(\.id),
                    isRunning: items.contains { $0.isRunning }
                )
            }
            return LoggedProjectGroup(
                id: projectId,
                label: label,
                hours: sorted.reduce(0) { $0 + $1.duration } / 3600.0,
                noteGroups: noteGroups
            )
        }
        // Sort by label, then by id — the id tiebreaker keeps the order STABLE
        // when two projects share a display name (otherwise the cards swap on
        // every timer tick and the "recording" dot appears to jump around).
        .sorted {
            let byLabel = $0.label.localizedStandardCompare($1.label)
            return byLabel == .orderedSame ? $0.id < $1.id : byLabel == .orderedAscending
        }
        return (groups, todayLoggedHours)
    }

    /// Per-project logged hours over the last `days` days (default 7), each split
    /// into task segments: no-note sessions merge per project; noted sessions
    /// split out by note (same note merges, different notes separate). Biggest
    /// project first, biggest segment first.
    func loggedBreakdownByProject(days: Int = 7) -> [ProjectBreakdown] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) ?? .distantPast
        let recent = loggedEntries.filter { $0.start >= start }
        let grouped: [Int: [LoggedEntry]] = Dictionary(grouping: recent, by: { $0.projectId })

        var result: [ProjectBreakdown] = []
        for (pid, entries) in grouped {
            var buckets: [String: (label: String, seconds: TimeInterval)] = [:]
            for entry in entries {
                let note = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = "\(pid)|\(note)"
                var bucket = buckets[key] ?? (note.isEmpty ? entry.projectLabel : note, 0)
                bucket.seconds += entry.duration
                buckets[key] = bucket
            }
            var segments: [WorkGroupHours] = buckets.map { key, value in
                WorkGroupHours(id: key, label: value.label, hours: value.seconds / 3600.0)
            }
            segments = segments.filter { $0.hours > 0 }
            segments.sort { $0.hours == $1.hours ? $0.id < $1.id : $0.hours > $1.hours }
            let total = segments.reduce(0.0) { $0 + $1.hours }
            guard total > 0 else { continue }
            let projectLabel = entries.sorted { $0.start < $1.start }.first?.projectLabel ?? "Project #\(pid)"
            result.append(ProjectBreakdown(id: pid, projectLabel: projectLabel, total: total, segments: segments))
        }
        result.sort { $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total }
        return result
    }

    /// Logged hours grouped **by day** for the last `days` days (newest first),
    /// each day split into task segments (note, or project when no note) using
    /// the same series keys as the timeline — so a day's composition and total
    /// read cleanly without mixing dates together. Days with no logged time are
    /// omitted.
    func loggedDailyBreakdown(days: Int = 7) -> [DayBreakdown] {
        let cal = Calendar(identifier: .gregorian)
        let today0 = cal.startOfDay(for: Date())
        var result: [DayBreakdown] = []
        for offset in 0..<max(days, 1) {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today0) else { continue }
            let key = Self.isoDate(dayStart)
            let entries = loggedEntries.filter { $0.dayKey == key }
            guard !entries.isEmpty else { continue }

            var buckets: [String: (label: String, seconds: TimeInterval)] = [:]
            for entry in entries {
                let note = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let series = note.isEmpty ? entry.projectLabel : note
                var bucket = buckets[series] ?? (series, 0)
                bucket.seconds += entry.duration
                buckets[series] = bucket
            }
            var segments = buckets.map { key2, value in
                WorkGroupHours(id: "\(key)|\(key2)", label: value.label, hours: value.seconds / 3600.0)
            }.filter { $0.hours > 0 }
            segments.sort { $0.hours == $1.hours ? $0.id < $1.id : $0.hours > $1.hours }
            let total = segments.reduce(0.0) { $0 + $1.hours }
            guard total > 0 else { continue }
            result.append(DayBreakdown(id: key, date: dayStart, total: total, segments: segments))
        }
        return result
    }

    /// Today's planned (Forecast) vs actual (logged) hours per project, biggest
    /// first — for the Insights comparison.
    func todayPlannedVsActual() -> [PlanActual] {
        var planned: [Int: Double] = [:]
        var labels: [Int: String] = [:]
        for assignment in todayAssignments {
            guard let pid = assignment.projectId else { continue }
            planned[pid, default: 0] += assignment.hoursPerDay
            labels[pid] = projectLabel(for: assignment)
        }
        var actual: [Int: Double] = [:]
        for entry in todayLoggedEntries {
            actual[entry.projectId, default: 0] += entry.duration / 3600.0
            if labels[entry.projectId] == nil { labels[entry.projectId] = entry.projectLabel }
        }

        var result: [PlanActual] = []
        for pid in Set(planned.keys).union(actual.keys) {
            let plannedHours = planned[pid] ?? 0
            let actualHours = actual[pid] ?? 0
            guard plannedHours > 0 || actualHours > 0 else { continue }
            result.append(PlanActual(id: pid, label: labels[pid] ?? "Project #\(pid)",
                                     planned: plannedHours, actual: actualHours))
        }
        result.sort {
            let lhs = max($0.planned, $0.actual)
            let rhs = max($1.planned, $1.actual)
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        return result
    }

    /// Merged note summary for a project's logged sessions today, e.g.
    /// `Motion [0.5hrs]` + newline + `Web素材 [2.3hrs]`. Nil when no notes exist.
    func mergedNotes(forProjectId projectId: Int) -> String? {
        let entries = todayLoggedEntries
            .filter { $0.projectId == projectId }
            .sorted { $0.start < $1.start }
        var order: [String] = []
        var buckets: [String: TimeInterval] = [:]
        for entry in entries {
            let key = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: 0] += entry.duration
        }
        guard !order.isEmpty else { return nil }
        return order
            .map { "\($0) [\(Self.decimalHours(buckets[$0]! / 3600.0))]" }
            .joined(separator: "\n")
    }

    /// `0.5hrs`, `2.3hrs`, `2hrs` — decimal hours for merged note summaries.
    nonisolated static func decimalHours(_ hours: Double) -> String {
        let rounded = (hours * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))hrs" }
        return String(format: "%.1fhrs", rounded)
    }

    /// Start recording the selected project, or resume a paused session.
    func record() {
        if let session {
            guard runningEntry == nil else { return }  // already running
            appendRunningSegment(projectId: session.projectId, label: session.projectLabel, notes: session.notes)
        } else {
            guard let project = selectedProject else { return }
            session = TimerSession(projectId: project.id, projectLabel: project.displayName, notes: notes, sessionStart: Date())
            appendRunningSegment(projectId: project.id, label: project.displayName, notes: notes)
        }
        startTicker()
    }

    /// Pause: close the running segment but keep the session so it can resume.
    func pause() {
        closeRunningSegment()
        stopTicker()
        recomputeElapsed()
    }

    /// Stop: close the running segment and end the session.
    func stop() {
        closeRunningSegment()
        session = nil
        stopTicker()
        elapsedSeconds = 0
    }

    func deleteLogged(_ entry: LoggedEntry) {
        deleteLogged(ids: [entry.id])
    }

    /// Delete all logged sessions with the given ids (a merged note group).
    func deleteLogged(ids: [UUID]) {
        let set = Set(ids)
        loggedEntries.removeAll { set.contains($0.id) }
        recomputeElapsed()
        if runningEntry == nil { stopTicker() }
    }

    /// Set (or clear) the note on all logged sessions with the given ids.
    func setNote(_ note: String, forIds ids: [UUID]) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = Set(ids)
        for index in loggedEntries.indices where set.contains(loggedEntries[index].id) {
            loggedEntries[index].notes = trimmed
        }
    }

    /// Drop finished sessions older than the retention window (never a running
    /// one). Keeps the UserDefaults-backed log from growing without bound.
    private func pruneOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.logRetentionDays, to: Date()) ?? .distantPast
        guard loggedEntries.contains(where: { !$0.isRunning && $0.start < cutoff }) else { return }
        loggedEntries.removeAll { !$0.isRunning && $0.start < cutoff }
    }

    private func appendRunningSegment(projectId: Int, label: String, notes: String) {
        loggedEntries.append(LoggedEntry(projectId: projectId, projectLabel: label, notes: notes, start: Date()))
    }

    private func closeRunningSegment() {
        if let idx = loggedEntries.firstIndex(where: { $0.isRunning }) {
            loggedEntries[idx].end = Date()
        }
        splitEntriesAcrossMidnight()
    }

    /// Split one entry at local-midnight boundaries so each piece stays within a
    /// single calendar day (matching `dayKey`). A still-running entry keeps its
    /// current day's piece running; any earlier days are closed at midnight.
    nonisolated static func splitAtMidnights(_ entry: LoggedEntry, now: Date) -> [LoggedEntry] {
        let cal = Calendar(identifier: .gregorian)
        let effectiveEnd = entry.end ?? now
        guard effectiveEnd > entry.start,
              !cal.isDate(entry.start, inSameDayAs: effectiveEnd) else { return [entry] }

        var parts: [LoggedEntry] = []
        var segStart = entry.start
        while true {
            let nextDay = cal.date(byAdding: .day, value: 1, to: segStart) ?? effectiveEnd
            let nextMidnight = cal.startOfDay(for: nextDay)
            if effectiveEnd <= nextMidnight {
                // Final piece keeps the real end (nil if the entry is still running).
                parts.append(LoggedEntry(projectId: entry.projectId, projectLabel: entry.projectLabel,
                                         notes: entry.notes, start: segStart, end: entry.end))
                break
            }
            parts.append(LoggedEntry(projectId: entry.projectId, projectLabel: entry.projectLabel,
                                     notes: entry.notes, start: segStart, end: nextMidnight))
            segStart = nextMidnight
        }
        return parts
    }

    /// Normalize every logged entry so none spans a day boundary — cross-midnight
    /// time is attributed to each date. Assigns nothing new when nothing spans.
    private func splitEntriesAcrossMidnight() {
        let now = Date()
        var didSplit = false
        var result: [LoggedEntry] = []
        result.reserveCapacity(loggedEntries.count)
        for entry in loggedEntries {
            let parts = Self.splitAtMidnights(entry, now: now)
            if parts.count > 1 { didSplit = true }
            result.append(contentsOf: parts)
        }
        if didSplit { loggedEntries = result }
    }

    /// While recording, close the running segment at midnight and continue a new
    /// one for the new day, so a session that crosses midnight is logged per day.
    private func splitRunningIfCrossedMidnight() {
        guard let running = runningEntry,
              !Calendar(identifier: .gregorian).isDate(running.start, inSameDayAs: Date())
        else { return }
        splitEntriesAcrossMidnight()
        recomputeElapsed()
    }

    /// Session elapsed = sum of this session's segments since it started.
    private func recomputeElapsed() {
        guard let session else { elapsedSeconds = 0; return }
        elapsedSeconds = loggedEntries
            .filter { $0.projectId == session.projectId && $0.start >= session.sessionStart }
            .reduce(0) { $0 + $1.duration }
    }

    private func startTicker() {
        stopTicker()
        recomputeElapsed()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.splitRunningIfCrossedMidnight()
                self.recomputeElapsed()
                self.checkIdle()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Idle detection

    /// If the user has been inactive past `idleThreshold` while the timer runs,
    /// auto-pause and trim the idle time from the running segment (so a timer
    /// left running — e.g. over lunch or overnight — doesn't over-count).
    private func checkIdle() {
        guard isTimerRunning, idleTimeoutMinutes > 0 else { return }
        let threshold = TimeInterval(idleTimeoutMinutes * 60)
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: UInt32.max)!)
        guard idle >= threshold else { return }

        let idleStart = Date().addingTimeInterval(-idle)
        if let idx = loggedEntries.firstIndex(where: { $0.isRunning }) {
            // Trim the running segment back to when input stopped.
            loggedEntries[idx].end = max(loggedEntries[idx].start, idleStart)
        }
        stopTicker()          // session stays → paused (can be resumed)
        recomputeElapsed()

        let minutes = max(1, Int((idle / 60).rounded()))
        notify(L.s("Timer paused after \(minutes) min idle — idle time was excluded.",
                   "\(minutes)分の無操作でタイマーを一時停止しました（無操作分は除外）。",
                   languageCode),
               kind: .info)
    }

    // MARK: - Sync logged → Forecast

    /// A single Forecast write when reconciling one project's logged hours.
    enum ForecastSyncOp: Equatable {
        case create(start: String, end: String, allocationSeconds: Int, notes: String?)
        case update(id: Int, projectId: Int?, personId: Int?, start: String?, end: String?, allocationSeconds: Int?, notes: String?)
    }

    /// Pattern A: decide how to set *today* to `loggedSeconds` for one project,
    /// **without ever overlapping ranges** (Forecast rejects overlaps with 422):
    /// - none → create a single-day booking for today.
    /// - single day → update its allocation in place.
    /// - multi-day covering today → shrink the original off of today (it becomes
    ///   the "before" or "after" block, keeping its hours), then create today,
    ///   plus the remaining block. Nothing is deleted, so no data is lost.
    nonisolated static func syncOps(
        existing: ForecastAssignment?, loggedSeconds: Int, notes: String?, personId: Int,
        today: String, yesterday: String, tomorrow: String
    ) -> [ForecastSyncOp] {
        guard let a = existing else {
            return [.create(start: today, end: today, allocationSeconds: loggedSeconds, notes: notes)]
        }
        let pid = a.projectId
        let person = personId
        if a.isSingleDay {
            return [.update(id: a.id, projectId: pid, personId: person,
                            start: a.startDate, end: a.endDate, allocationSeconds: loggedSeconds, notes: notes)]
        }

        let hasBefore = (a.startDate.map { $0 < today }) ?? false
        let hasAfter = (a.endDate.map { $0 > today }) ?? false
        let todayOp = ForecastSyncOp.create(start: today, end: today, allocationSeconds: loggedSeconds, notes: notes)

        if hasBefore {
            // Shrink original to end yesterday (= "before" block), then today,
            // then the "after" block if the range extends past today.
            var ops: [ForecastSyncOp] = [
                .update(id: a.id, projectId: pid, personId: person,
                        start: a.startDate, end: yesterday, allocationSeconds: a.allocation, notes: a.notes),
                todayOp,
            ]
            if hasAfter {
                ops.append(.create(start: tomorrow, end: a.endDate ?? today,
                                   allocationSeconds: a.allocation ?? 0, notes: a.notes))
            }
            return ops
        } else if hasAfter {
            // Starts today → move original's start to tomorrow (= "after" block).
            return [
                .update(id: a.id, projectId: pid, personId: person,
                        start: tomorrow, end: a.endDate, allocationSeconds: a.allocation, notes: a.notes),
                todayOp,
            ]
        } else {
            return [.update(id: a.id, projectId: pid, personId: person,
                            start: a.startDate, end: a.endDate, allocationSeconds: loggedSeconds, notes: notes)]
        }
    }

    /// Push today's logged hours into Forecast, setting today's allocation to the
    /// logged total (creating one if none exists, or carving today out of a
    /// multi-day range so only today changes). Projects with no logged time are
    /// left alone.
    func syncLoggedToForecast() async {
        guard let api = makeAPI(), let personId = currentUser?.id else {
            notify(L.s("Connect in Settings before syncing.",
                       "同期の前に設定で接続してください。", languageCode), kind: .error)
            return
        }
        let logged = loggedGroupedToday.groups.filter { $0.hours > 0 }
        guard !logged.isEmpty else {
            notify(L.s("Nothing logged today to sync.",
                       "今日は同期する記録がありません。", languageCode), kind: .info)
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Pull the latest schedule first, so we split/overwrite against the
        // current Forecast state (not a stale snapshot).
        await refreshToday()

        let today = Self.today()
        let cal = Calendar(identifier: .gregorian)
        let todayDate = cal.startOfDay(for: Date())
        let yesterday = Self.isoDate(cal.date(byAdding: .day, value: -1, to: todayDate) ?? todayDate)
        let tomorrow = Self.isoDate(cal.date(byAdding: .day, value: 1, to: todayDate) ?? todayDate)

        // Sync each project independently so one project that Forecast rejects
        // doesn't block the rest — and so we can report *which* project failed.
        var synced = 0
        var failures: [(label: String, id: Int, message: String)] = []
        for group in logged {
            do {
                let seconds = Int((group.hours * 3600).rounded())
                let noteText = mergedNotes(forProjectId: group.id)
                let existing = todayAssignments.first(where: { $0.projectId == group.id })
                let ops = Self.syncOps(existing: existing, loggedSeconds: seconds, notes: noteText,
                                       personId: personId, today: today, yesterday: yesterday, tomorrow: tomorrow)
                for op in ops {
                    switch op {
                    case let .create(start, end, allocationSeconds, notes):
                        _ = try await api.createAssignment(
                            projectId: group.id, personId: personId,
                            start: start, end: end, allocationSeconds: allocationSeconds, notes: notes)
                    case let .update(id, projectId, personId, start, end, allocationSeconds, notes):
                        _ = try await api.updateAssignment(id: id, projectId: projectId, personId: personId,
                                                           start: start, end: end,
                                                           allocationSeconds: allocationSeconds, notes: notes)
                    }
                }
                synced += 1
            } catch {
                let message = (error as? APIError)?.localizedDescription ?? error.localizedDescription
                failures.append((group.label, group.id, message))
            }
        }
        await refreshToday()

        if failures.isEmpty {
            notify(L.s("Synced \(synced) project\(synced == 1 ? "" : "s") to Forecast.",
                       "\(synced)件のプロジェクトを Forecast に同期しました。", languageCode),
                   kind: .success)
            showForecastReviewPrompt = true
        } else {
            // Name the offending project(s) and the reason, so it's clear what to fix.
            let names = failures.map { "「\($0.label)」(#\($0.id))" }.joined(separator: "、")
            let reason = failures.first?.message ?? ""
            let msg: String
            if synced == 0 {
                msg = L.s("Couldn't sync \(names): \(reason)",
                          "\(names)を同期できませんでした：\(reason)", languageCode)
            } else {
                msg = L.s("Synced \(synced); couldn't sync \(names): \(reason)",
                          "\(synced)件同期。\(names)は同期できませんでした：\(reason)", languageCode)
                showForecastReviewPrompt = true
            }
            notify(msg, kind: .error)
        }
    }

    /// URL of the Forecast schedule for the current account (web app).
    var forecastScheduleURL: URL? {
        let account = auth.accountId.trimmingCharacters(in: .whitespaces)
        guard !account.isEmpty else { return nil }
        return URL(string: "https://forecastapp.com/\(account)/schedule/team")
    }

    /// Open the Forecast schedule in the user's default browser.
    func openForecastInBrowser() {
        guard let url = forecastScheduleURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Client name for a project, if any.
    func clientName(for project: ForecastProject) -> String? {
        guard let clientId = project.clientId, let name = clientsById[clientId], !name.isEmpty else { return nil }
        return name
    }

    /// Search text for a project including its client name.
    func searchHaystack(for project: ForecastProject) -> String {
        project.searchHaystack(clientName: project.clientId.flatMap { clientsById[$0] })
    }

    // MARK: - Lifecycle

    /// Loads the person, projects, clients, and today's schedule. Idempotent:
    /// the window and menu-bar panel both trigger it, but it runs once unless
    /// `force` is passed (e.g. right after connecting in Settings).
    func bootstrap(force: Bool = false) async {
        guard auth.isConfigured else { return }
        if hasBootstrapped && !force { return }
        hasBootstrapped = true
        await loadReferenceData()
        await refreshToday()
    }

    private func loadReferenceData() async {
        guard let api = makeAPI() else { return }
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            async let user = api.whoami()
            async let fetchedProjects = api.fetchProjects()
            async let fetchedClients = api.fetchClients()

            currentUser = try await user
            clientsById = Dictionary(uniqueKeysWithValues: try await fetchedClients.compactMap { client in
                client.name.map { (client.id, $0) }
            })
            let active = try await fetchedProjects.filter { $0.isActive }
            projectsById = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            projects = active.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            // Restore the last-used project so the selection is remembered.
            if selectedProject == nil,
               let savedId = UserDefaults.standard.object(forKey: Self.selectedProjectKey) as? Int,
               let saved = projectsById[savedId] {
                selectedProject = saved
            }
        } catch {
            show(error)
        }
    }

    private static let selectedProjectKey = "app.selectedProjectId"

    // MARK: - Selection

    func selectProject(_ project: ForecastProject) {
        selectedProject = project
        UserDefaults.standard.set(project.id, forKey: Self.selectedProjectKey)
        noteRecentProject(project)
    }

    // MARK: - Recent projects

    private static let recentProjectsKey = "app.recentProjectIds"
    private static let maxRecentProjects = 6

    /// Ids of recently chosen projects, most recent first (persisted).
    @Published private(set) var recentProjectIds: [Int] =
        (UserDefaults.standard.array(forKey: recentProjectsKey) as? [Int]) ?? []

    /// Recently chosen projects that still exist, most recent first.
    var recentProjects: [ForecastProject] {
        recentProjectIds.compactMap { projectsById[$0] }
    }

    /// Record `project` as most-recently used (dedup + capped).
    func noteRecentProject(_ project: ForecastProject) {
        var ids = recentProjectIds.filter { $0 != project.id }
        ids.insert(project.id, at: 0)
        if ids.count > Self.maxRecentProjects { ids = Array(ids.prefix(Self.maxRecentProjects)) }
        recentProjectIds = ids
        UserDefaults.standard.set(ids, forKey: Self.recentProjectsKey)
    }

    // MARK: - Scheduling

    /// Schedule `hours` per day on a project across a date range.
    func addAssignment(project: ForecastProject, start: String, end: String, hours: Double, notes: String) async -> Bool {
        guard let api = makeAPI(), let personId = currentUser?.id else {
            if currentUser == nil {
                notify(L.s("Not connected yet — open Settings and Test Connection.",
                           "未接続です。設定を開いて「接続テスト」を実行してください。", languageCode), kind: .error)
            }
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await api.createAssignment(
                projectId: project.id,
                personId: personId,
                start: start,
                end: end,
                allocationSeconds: Int((hours * 3600).rounded()),
                notes: notes
            )
            await refreshToday()
            showForecastReviewPrompt = true
            return true
        } catch {
            show(error)
            return false
        }
    }

    // MARK: - Today

    func refreshToday() async {
        guard let api = makeAPI() else { return }
        if currentUser == nil {
            do { currentUser = try await api.whoami() }
            catch { show(error); return }
        }
        guard let personId = currentUser?.id else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let today = Self.today()
            let assignments = try await api.fetchAssignments(personId: personId, start: today, end: today)
            todayAssignments = assignments.sorted { $0.id > $1.id }
        } catch {
            show(error)
        }
    }

    func deleteAssignment(_ assignment: ForecastAssignment) async {
        guard let api = makeAPI() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.deleteAssignment(id: assignment.id)
            await refreshToday()
        } catch {
            show(error)
        }
    }

    /// A display label for an assignment's project (falls back gracefully).
    func projectLabel(for assignment: ForecastAssignment) -> String {
        if let id = assignment.projectId, let project = projectsById[id] {
            return project.displayName
        }
        return assignment.projectId.map { "Project #\($0)" } ?? "Unknown project"
    }

    /// Today's assignments grouped by project, each with summed hours, plus total.
    var groupedToday: (groups: [(label: String, hours: Double, assignments: [ForecastAssignment])], total: Double) {
        let grouped = Dictionary(grouping: todayAssignments, by: { projectLabel(for: $0) })
        let groups = grouped
            .map { (label: $0.key, hours: $0.value.reduce(0) { $0 + $1.hoursPerDay }, assignments: $0.value) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return (groups, todayTotalHours)
    }

    // MARK: - Network monitor

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Helpers

    private func makeAPI() -> ForecastAPI? {
        guard let creds = auth.credentials() else {
            notify(localizedAPIError(.notConfigured), kind: .error)
            return nil
        }
        return ForecastAPI(credentials: creds)
    }

    // MARK: - Notices

    /// Show a transient, typed inline message; auto-dismisses after its TTL.
    func notify(_ message: String, kind: Notice.Kind) {
        noticeDismissTask?.cancel()
        let newNotice = Notice(kind: kind, message: message)
        notice = newNotice
        let ttl = newNotice.autoDismissAfter
        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
            guard let self, self.notice?.id == newNotice.id else { return }
            self.notice = nil
        }
    }

    func dismissNotice() {
        noticeDismissTask?.cancel()
        notice = nil
    }

    private func show(_ error: Error) {
        notify(localizedError(error), kind: .error)
    }

    private func localizedError(_ error: Error) -> String {
        (error as? APIError).map(localizedAPIError) ?? error.localizedDescription
    }

    /// Localized message for an `APIError` (the enum's own text is English-only).
    private func localizedAPIError(_ error: APIError) -> String {
        switch error {
        case .notConfigured:
            return L.s("Add your Account ID and token in Settings first.",
                       "先に設定でアカウントIDとトークンを入力してください。", languageCode)
        case .invalidURL:
            return L.s("Could not build a valid request URL.",
                       "有効なリクエストURLを作成できませんでした。", languageCode)
        case let .http(status, message):
            let base = L.s("Forecast returned HTTP \(status).",
                           "Forecast が HTTP \(status) を返しました。", languageCode)
            return message.isEmpty ? base : "\(base) \(message)"
        case .rateLimited:
            return L.s("Rate limited by Forecast. Please retry in a moment.",
                       "Forecast のレート制限中です。少し待って再試行してください。", languageCode)
        case let .decoding(detail):
            return L.s("Unexpected response from Forecast. \(detail)",
                       "Forecast から予期しない応答がありました。\(detail)", languageCode)
        case let .transport(detail):
            return detail
        }
    }

    nonisolated static func today() -> String { isoDate(Date()) }

    nonisolated static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Format decimal hours as `8h`, `1h 30m`, or `45m`.
    nonisolated static func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Live clock format for the running timer: `h:mm:ss` (or `mm:ss` under 1h).
    nonisolated static func shortTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        // Zero-pad minutes so the M:SS readout is a constant width (the colon and
        // digits never shift as the value changes).
        return String(format: "%02d:%02d", m, s)
    }
}

#if DEBUG
extension TrackerViewModel {
    /// A view model populated with sample data for SwiftUI previews — no network.
    /// `running` seeds an active (recording) session.
    static func preview(auth: AuthStore, running: Bool = false) -> TrackerViewModel {
        let model = TrackerViewModel(auth: auth)
        let p1 = ForecastProject(id: 100001, name: "Website Redesign", code: "24-0001", clientId: 1, harvestId: nil, archived: false)
        let p2 = ForecastProject(id: 100002, name: "Mobile App", code: "24-0002", clientId: 2, harvestId: nil, archived: false)

        model.projects = [p1, p2]
        model.projectsById = [p1.id: p1, p2.id: p2]
        model.clientsById = [1: "Acme Inc.", 2: "Globex"]
        model.selectedProject = p1
        model.currentUser = ForecastUser(id: 1, firstName: "Sample", lastName: "User", email: "you@example.com")

        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) ?? now
        model.loggedEntries = [
            LoggedEntry(projectId: p1.id, projectLabel: p1.displayName, notes: "Motion",
                        start: now.addingTimeInterval(-5400), end: now.addingTimeInterval(-3600)),
            LoggedEntry(projectId: p1.id, projectLabel: p1.displayName, notes: "Web素材",
                        start: now.addingTimeInterval(-3500), end: now.addingTimeInterval(-600)),
            LoggedEntry(projectId: p2.id, projectLabel: p2.displayName, notes: "",
                        start: now.addingTimeInterval(-560), end: now.addingTimeInterval(-80)),
            // A prior day, so the per-day Insights chart shows more than "Today".
            LoggedEntry(projectId: p2.id, projectLabel: p2.displayName, notes: "リサーチ",
                        start: yesterday.addingTimeInterval(36000), end: yesterday.addingTimeInterval(41400)),
        ]
        model.todayAssignments = [
            ForecastAssignment(id: 1, projectId: p1.id, personId: 1,
                               startDate: nil, endDate: nil, allocation: 28800, notes: "Design"),
        ]

        if running {
            model.session = TimerSession(projectId: p1.id, projectLabel: p1.displayName, notes: "Motion", sessionStart: now.addingTimeInterval(-46))
            model.loggedEntries.append(LoggedEntry(projectId: p1.id, projectLabel: p1.displayName, notes: "Motion", start: now.addingTimeInterval(-46), end: nil))
            model.elapsedSeconds = 46
        }

        model.hasBootstrapped = true   // prevent the .task network bootstrap in previews
        return model
    }
}
#endif

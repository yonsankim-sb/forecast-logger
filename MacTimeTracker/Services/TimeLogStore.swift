import Foundation

/// Persists locally-logged time entries (the real hours from the start/stop
/// timer). Stored as JSON in UserDefaults — small, private to this Mac, and
/// survives relaunch so a running timer can be recovered.
enum TimeLogStore {
    private static let entriesKey = "timelog.entries.v1"
    private static let sessionKey = "timelog.session.v1"

    static func load() -> [LoggedEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey) else { return [] }
        return (try? JSONDecoder().decode([LoggedEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [LoggedEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    static func loadSession() -> TimerSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(TimerSession.self, from: data)
    }

    static func saveSession(_ session: TimerSession?) {
        guard let session, let data = try? JSONEncoder().encode(session) else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }
}

import Foundation

/// Immutable snapshot of the credentials needed to talk to Forecast.
struct APICredentials {
    let token: String
    let accountId: String
    let contactEmail: String
}

/// Errors surfaced by the API client, each with a user-readable message.
enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, message: String)
    case rateLimited
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Account ID and token in Settings first."
        case .invalidURL:
            return "Could not build a valid request URL."
        case let .http(status, message):
            let base = "Forecast returned HTTP \(status)."
            return message.isEmpty ? base : "\(base) \(message)"
        case .rateLimited:
            return "Rate limited by Forecast. Please retry in a moment."
        case let .decoding(detail):
            return "Unexpected response from Forecast. \(detail)"
        case let .transport(detail):
            return detail
        }
    }
}

/// Async `URLSession` client for the Forecast API. Forecast is Harvest's
/// scheduling sibling: it exposes projects, clients, people, and **assignments**
/// (scheduled allocations), but has no logged-time or timer concept.
///
/// Note: Forecast's API is unofficial/undocumented; base URL and shapes are the
/// community-known ones. Auth uses the same personal access token as Harvest,
/// but with the `Forecast-Account-ID` header.
struct ForecastAPI {
    private static let baseURL = URL(string: "https://api.forecastapp.com")!

    let credentials: APICredentials
    private let session: URLSession

    init(credentials: APICredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Account discovery (Harvest ID service)

    /// `GET https://id.getharvest.com/api/v2/accounts` — lists every account the
    /// token can reach (Harvest and Forecast). Static: used before an Account ID
    /// is known.
    static func fetchAccounts(token: String, contactEmail: String, session: URLSession = .shared) async throws -> [HarvestAccount] {
        guard let url = URL(string: "https://id.getharvest.com/api/v2/accounts") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("MacTimeTracker (\(agent(contactEmail)))", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.transport(urlError.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }
        switch http.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(AccountsResponse.self, from: data).accounts }
            catch { throw APIError.decoding(error.localizedDescription) }
        case 401:
            throw APIError.http(status: 401, message: "Invalid or expired token.")
        default:
            throw APIError.http(status: http.statusCode, message: errorMessage(from: data))
        }
    }

    // MARK: - Endpoints

    /// `GET /whoami` — validates the token/account and returns the current person.
    func whoami() async throws -> ForecastUser {
        let response: WhoAmIResponse = try await request(path: "/whoami", decode: WhoAmIResponse.self)
        return response.currentUser
    }

    /// `GET /projects` — all projects (filter to active in the caller).
    func fetchProjects() async throws -> [ForecastProject] {
        try await request(path: "/projects", decode: ProjectsResponse.self).projects
    }

    /// `GET /clients` — all clients, for resolving project client names.
    func fetchClients() async throws -> [ForecastClient] {
        try await request(path: "/clients", decode: ClientsResponse.self).clients
    }


    /// `GET /assignments` — the person's assignments overlapping a date range.
    func fetchAssignments(personId: Int, start: String, end: String) async throws -> [ForecastAssignment] {
        try await request(
            path: "/assignments",
            query: [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end),
                URLQueryItem(name: "person_id", value: String(personId)),
            ],
            decode: AssignmentsResponse.self
        ).assignments
    }

    /// `POST /assignments` — schedule `allocationSeconds` per day on a project.
    /// Matches the Forecast web app exactly: wrapped in `assignment`, with
    /// `project_id`/`person_id` sent as **strings** and `placeholder_id: null`
    /// (a person assignment, not a placeholder).
    func createAssignment(projectId: Int, personId: Int, start: String, end: String, allocationSeconds: Int, notes: String?) async throws -> ForecastAssignment {
        var assignment: [String: Any] = [
            "start_date": start,
            "end_date": end,
            "allocation": allocationSeconds,
            "active_on_days_off": false,
            "project_id": String(projectId),
            "person_id": String(personId),
            "placeholder_id": NSNull(),
        ]
        if let notes, !notes.isEmpty { assignment["notes"] = notes }
        let body: [String: Any] = ["assignment": assignment]
        return try await request(path: "/assignments", method: "POST", body: body, decode: AssignmentResponse.self).assignment
    }

    /// `PUT /assignments/{id}` — update the given fields (same shape as create:
    /// wrapped, string ids).
    @discardableResult
    func updateAssignment(id: Int, projectId: Int? = nil, personId: Int? = nil,
                          start: String? = nil, end: String? = nil,
                          allocationSeconds: Int? = nil, notes: String? = nil) async throws -> ForecastAssignment {
        var assignment: [String: Any] = [:]
        if let projectId { assignment["project_id"] = String(projectId) }
        if let personId { assignment["person_id"] = String(personId) }
        if let start { assignment["start_date"] = start }
        if let end { assignment["end_date"] = end }
        if let allocationSeconds { assignment["allocation"] = allocationSeconds }
        if let notes, !notes.isEmpty { assignment["notes"] = notes }
        let body: [String: Any] = ["assignment": assignment]
        return try await request(path: "/assignments/\(id)", method: "PUT", body: body, decode: AssignmentResponse.self).assignment
    }

    /// `DELETE /assignments/{id}`.
    func deleteAssignment(id: Int) async throws {
        try await requestVoid(path: "/assignments/\(id)", method: "DELETE")
    }

    // MARK: - Request plumbing

    private static func agent(_ email: String) -> String {
        email.isEmpty ? "user@example.com" : email
    }

    private func makeRequest(path: String, method: String, query: [URLQueryItem], body: [String: Any]?) throws -> URLRequest {
        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountId, forHTTPHeaderField: "Forecast-Account-ID")
        request.setValue("MacTimeTracker (\(Self.agent(credentials.contactEmail)))", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        decode type: T.Type
    ) async throws -> T {
        let data = try await perform(path: path, method: method, query: query, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func requestVoid(path: String, method: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws {
        _ = try await perform(path: path, method: method, query: query, body: body)
    }

    private func perform(path: String, method: String, query: [URLQueryItem], body: [String: Any]?, isRetry: Bool = false) async throws -> Data {
        let request = try makeRequest(path: path, method: method, query: query, body: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.transport(urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 429:
            guard !isRetry else { throw APIError.rateLimited }
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 2
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await perform(path: path, method: method, query: query, body: body, isRetry: true)
        default:
            throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    /// Best-effort extraction of an error message from a JSON body (handles a
    /// plain `message`/`error`, or a nested `errors` object/array — Forecast's
    /// 422 validation shape).
    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return "" }
        if let dict = object as? [String: Any] {
            if let message = dict["message"] as? String { return message }
            if let error = dict["error"] as? String { return error }
            if let errors = dict["errors"] { return describe(errors) }
        }
        return describe(object)
    }

    /// Flatten an arbitrary JSON value into a readable string.
    private static func describe(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            return array.map { describe($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
        if let dict = value as? [String: Any] {
            return dict.map { "\($0.key): \(describe($0.value))" }.filter { !$0.isEmpty }.joined(separator: "; ")
        }
        return ""
    }
}

import Foundation

/// A project from Forecast (`GET /projects`). Forecast stores the short `code`
/// (e.g. `24-0001`) and the descriptive `name` separately, and links a client
/// by `clientId` rather than nesting it.
struct ForecastProject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let code: String?
    let clientId: Int?
    let harvestId: Int?
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case code
        case clientId = "client_id"
        case harvestId = "harvest_id"
        case archived
    }

    var isActive: Bool { archived != true }

    /// `[24-0001] Website Redesign` when both are present.
    var displayName: String {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespaces)
        if let code, !code.isEmpty {
            return trimmedName.isEmpty ? "[\(code)]" : "[\(code)] \(trimmedName)"
        }
        return trimmedName.isEmpty ? "Project #\(id)" : trimmedName
    }

    /// Lowercased text for search: matches code, name (and is combined with the
    /// client name by the view model), Unicode-aware via `localizedCaseInsensitive`.
    func searchHaystack(clientName: String?) -> String {
        [name, code, clientName]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}

/// `GET /projects`.
struct ProjectsResponse: Codable {
    let projects: [ForecastProject]
}

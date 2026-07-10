import Foundation

/// A client from Forecast (`GET /clients`). Used to resolve a project's
/// `clientId` into a display name.
struct ForecastClient: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let archived: Bool?
}

/// `GET /clients`.
struct ClientsResponse: Codable {
    let clients: [ForecastClient]
}
